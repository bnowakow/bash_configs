#!/usr/bin/env bash

set -euo pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

kubectl_cmd=(kubectl --request-timeout=30s)

usage() {
  cat <<'EOF'
Usage:
  delete-stuck-expired-cert-requests.sh [--delete] [--all-problem-certs] [--stuck-after-minutes MINUTES] [--namespace NAMESPACE]

Checks cert-manager Certificates, finds expired certificates, detects stuck
CertificateRequests for those certificates, and optionally deletes the stuck
requests so cert-manager can create a fresh request.

Default mode is dry-run.

Options:
  --delete             Delete stuck CertificateRequests.
  --all-problem-certs  Also inspect certificates that are not Ready for reasons
                       other than expiration.
  --stuck-after-minutes MINUTES
                       Only delete non-ready CertificateRequests older than this.
                       Default: 60.
  --namespace NAME     Limit checks to one namespace.
  -h, --help           Show this help.

Requirements:
  kubectl, jq, and access to the cluster.
EOF
}

delete=false
all_problem_certs=false
stuck_after_minutes=60
namespace_arg=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --delete)
      delete=true
      shift
      ;;
    --all-problem-certs)
      all_problem_certs=true
      shift
      ;;
    --stuck-after-minutes)
      if [[ $# -lt 2 || ! "${2:-}" =~ ^[0-9]+$ || "$2" -eq 0 ]]; then
        echo "ERROR: --stuck-after-minutes requires a positive integer" >&2
        exit 2
      fi
      stuck_after_minutes="$2"
      shift 2
      ;;
    --namespace)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "ERROR: --namespace requires a value" >&2
        exit 2
      fi
      namespace_arg=(-n "$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

need_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $1" >&2
    exit 1
  fi
}

need_command kubectl
need_command jq
need_command flock
exec 9>/tmp/delete-stuck-expired-cert-requests.lock
flock -n 9 || exit 0

if [[ ${#namespace_arg[@]} -eq 0 ]]; then
  cert_scope=(-A)
  cr_scope=(-A)
else
  cert_scope=("${namespace_arg[@]}")
  cr_scope=("${namespace_arg[@]}")
fi

now_epoch="$(date -u +%s)"
certs_json="$("${kubectl_cmd[@]}" get certificates.cert-manager.io "${cert_scope[@]}" -o json)"
requests_json="$("${kubectl_cmd[@]}" get certificaterequests.cert-manager.io "${cr_scope[@]}" -o json)"
orders_json="$("${kubectl_cmd[@]}" get orders.acme.cert-manager.io "${cr_scope[@]}" -o json)"
challenges_json="$("${kubectl_cmd[@]}" get challenges.acme.cert-manager.io "${cr_scope[@]}" -o json)"

if [[ "$all_problem_certs" == true ]]; then
  cert_filter='
    .items[]
    | {
        namespace: .metadata.namespace,
        name: .metadata.name,
        secret: .spec.secretName,
        notAfter: (.status.notAfter // ""),
        ready: ((.status.conditions // []) | map(select(.type == "Ready")) | last // {}),
        issuing: ((.status.conditions // []) | map(select(.type == "Issuing")) | last // {})
      }
    | select(
        (.notAfter != "" and (.notAfter | fromdateiso8601) < $now)
        or (.ready.status // "") != "True"
      )
    | [
        .namespace,
        .name,
        .secret,
        .notAfter,
        (.ready.reason // ""),
        (.ready.message // ""),
        (.issuing.reason // ""),
        (.issuing.message // "")
      ]
    | @tsv
  '
else
  cert_filter='
    .items[]
    | {
        namespace: .metadata.namespace,
        name: .metadata.name,
        secret: .spec.secretName,
        notAfter: (.status.notAfter // ""),
        ready: ((.status.conditions // []) | map(select(.type == "Ready")) | last // {}),
        issuing: ((.status.conditions // []) | map(select(.type == "Issuing")) | last // {})
      }
    | select(
        (.notAfter != "" and (.notAfter | fromdateiso8601) < $now)
        or (.ready.reason // "") == "Expired"
      )
    | [
        .namespace,
        .name,
        .secret,
        .notAfter,
        (.ready.reason // ""),
        (.ready.message // ""),
        (.issuing.reason // ""),
        (.issuing.message // "")
      ]
    | @tsv
  '
fi

mapfile -t problem_certs < <(jq -r --argjson now "$now_epoch" "$cert_filter" <<<"$certs_json")

if [[ ${#problem_certs[@]} -eq 0 ]]; then
  if [[ "$all_problem_certs" == true ]]; then
    echo "No expired or non-ready certificates found."
  else
    echo "No expired certificates found."
  fi
  exit 0
fi

echo "Mode: $([[ "$delete" == true ]] && echo delete || echo dry-run)"
echo "Stuck threshold: ${stuck_after_minutes} minutes"
echo

stuck_after_seconds=$((stuck_after_minutes * 60))
deleted=0
deleted_orders=0
deleted_challenges=0
stuck=0
recent=0
stale_orders=0
stale_challenges=0

for cert_line in "${problem_certs[@]}"; do
  IFS=$'\t' read -r cert_ns cert_name cert_secret not_after ready_reason ready_message issuing_reason issuing_message <<<"$cert_line"

  echo "Certificate: ${cert_ns}/${cert_name}"
  echo "  Secret: ${cert_secret:-<none>}"
  echo "  NotAfter: ${not_after:-<unknown>}"
  echo "  Ready reason: ${ready_reason:-<none>}"
  [[ -n "${ready_message:-}" ]] && echo "  Ready message: $ready_message"
  [[ -n "${issuing_reason:-}" ]] && echo "  Issuing reason: $issuing_reason"
  [[ -n "${issuing_message:-}" ]] && echo "  Issuing message: $issuing_message"

  mapfile -t cert_requests < <(
    jq -r \
      --arg ns "$cert_ns" \
      --arg cert "$cert_name" \
      --argjson now "$now_epoch" \
      '
        .items[]
        | select(.metadata.namespace == $ns)
        | select(.metadata.annotations["cert-manager.io/certificate-name"] == $cert)
        | {
            name: .metadata.name,
            created: .metadata.creationTimestamp,
            ageSeconds: ($now - (.metadata.creationTimestamp | fromdateiso8601)),
            ready: ((.status.conditions // []) | map(select(.type == "Ready")) | last // {}),
            approved: ((.status.conditions // []) | map(select(.type == "Approved")) | last // {})
          }
        | [
            .name,
            .created,
            (.ageSeconds | floor | tostring),
            (.ready.status // "<none>"),
            (.ready.reason // "<none>"),
            (.ready.message // "<none>"),
            (.approved.status // "<none>")
          ]
        | @tsv
      ' <<<"$requests_json"
  )

  mapfile -t cert_orders < <(
    jq -r \
      --arg ns "$cert_ns" \
      --arg cert "$cert_name" \
      --argjson now "$now_epoch" \
      '
        .items[]
        | select(.metadata.namespace == $ns)
        | select(.metadata.annotations["cert-manager.io/certificate-name"] == $cert)
        | {
            name: .metadata.name,
            created: .metadata.creationTimestamp,
            ageSeconds: ($now - (.metadata.creationTimestamp | fromdateiso8601)),
            state: (.status.state // ""),
            owner: ((.metadata.ownerReferences // []) | map(.name) | join(","))
          }
        | select(.ageSeconds >= 0)
        | [
            .name,
            .created,
            (.ageSeconds | floor | tostring),
            (.state // "<none>"),
            (if .owner == "" then "<none>" else .owner end)
          ]
        | @tsv
      ' <<<"$orders_json"
  )

  for order_line in "${cert_orders[@]}"; do
    IFS=$'\t' read -r order_name order_created order_age_seconds order_state order_owner <<<"$order_line"
    order_age_minutes=$((order_age_seconds / 60))

    mapfile -t order_challenges < <(
      jq -r \
        --arg ns "$cert_ns" \
        --arg order "$order_name" \
        --argjson now "$now_epoch" \
        '
          .items[]
          | select(.metadata.namespace == $ns)
          | select(((.metadata.ownerReferences // []) | map(select(.kind == "Order" and .name == $order)) | length) > 0)
          | {
              name: .metadata.name,
              created: .metadata.creationTimestamp,
              ageSeconds: ($now - (.metadata.creationTimestamp | fromdateiso8601)),
              state: (.status.state // ""),
              reason: (.status.reason // ""),
              domain: (.spec.dnsName // "")
            }
          | [
              .name,
              .created,
              (.ageSeconds | floor | tostring),
              (if .state == "" then "<none>" else .state end),
              (if .domain == "" then "<none>" else .domain end),
              (if .reason == "" then "<none>" else .reason end)
            ]
          | @tsv
        ' <<<"$challenges_json"
    )

    if (( order_age_seconds >= stuck_after_seconds )); then
      for challenge_line in "${order_challenges[@]}"; do
        IFS=$'\t' read -r challenge_name challenge_created challenge_age_seconds challenge_state challenge_domain challenge_reason <<<"$challenge_line"
        challenge_age_minutes=$((challenge_age_seconds / 60))
        stale_challenges=$((stale_challenges + 1))
        echo "  Stale ACME Challenge: ${cert_ns}/${challenge_name}"
        echo "    Created: ${challenge_created} (${challenge_age_minutes}m old)"
        echo "    State: ${challenge_state:-<none>}"
        echo "    Domain: ${challenge_domain:-<none>}"
        echo "    Reason: ${challenge_reason:-<none>}"

        if [[ "$delete" == true ]]; then
          "${kubectl_cmd[@]}" delete challenge.acme.cert-manager.io -n "$cert_ns" "$challenge_name"
          deleted_challenges=$((deleted_challenges + 1))
        else
          echo "    Dry-run: would delete ${cert_ns}/${challenge_name}"
        fi
      done

      stale_orders=$((stale_orders + 1))
      echo "  Stale ACME Order: ${cert_ns}/${order_name}"
      echo "    Created: ${order_created} (${order_age_minutes}m old)"
      echo "    State: ${order_state:-<none>}"
      echo "    Owner: ${order_owner:-<none>}"

      if [[ "$delete" == true ]]; then
        "${kubectl_cmd[@]}" delete order.acme.cert-manager.io -n "$cert_ns" "$order_name"
        deleted_orders=$((deleted_orders + 1))
      else
        echo "    Dry-run: would delete ${cert_ns}/${order_name}"
      fi
    elif [[ ${#order_challenges[@]} -gt 0 ]]; then
      for challenge_line in "${order_challenges[@]}"; do
        IFS=$'\t' read -r challenge_name challenge_created challenge_age_seconds challenge_state challenge_domain challenge_reason <<<"$challenge_line"
        challenge_age_minutes=$((challenge_age_seconds / 60))
        echo "  Recent ACME Challenge: ${cert_ns}/${challenge_name}"
        echo "    Created: ${challenge_created} (${challenge_age_minutes}m old)"
        echo "    Threshold: ${stuck_after_minutes}m"
        echo "    State: ${challenge_state:-<none>}"
        echo "    Domain: ${challenge_domain:-<none>}"
        echo "    Reason: ${challenge_reason:-<none>}"
        echo "    Action: leave it alone for now"
      done
    fi
  done

  if [[ ${#cert_requests[@]} -eq 0 ]]; then
    echo "  CertificateRequests: none found"
    echo
    continue
  fi

  for request_line in "${cert_requests[@]}"; do
    IFS=$'\t' read -r request_name request_created request_age_seconds request_ready request_reason request_message request_approved <<<"$request_line"
    request_age_minutes=$((request_age_seconds / 60))

    if [[ "$request_ready" != "True" ]] && (( request_age_seconds >= stuck_after_seconds )); then
      stuck=$((stuck + 1))
      echo "  Old/stuck CertificateRequest: ${cert_ns}/${request_name}"
      echo "    Created: ${request_created} (${request_age_minutes}m old)"
      echo "    Approved: ${request_approved:-<unknown>}"
      echo "    Ready: ${request_ready:-<none>}"
      echo "    Reason: ${request_reason:-<none>}"
      [[ -n "${request_message:-}" ]] && echo "    Message: $request_message"

      if [[ "$delete" == true ]]; then
        "${kubectl_cmd[@]}" delete certificaterequest.cert-manager.io -n "$cert_ns" "$request_name"
        deleted=$((deleted + 1))
      else
        echo "    Dry-run: would delete ${cert_ns}/${request_name}"
      fi
    elif (( request_age_seconds < stuck_after_seconds )); then
      recent=$((recent + 1))
      echo "  Recent CertificateRequest: ${cert_ns}/${request_name}"
      echo "    Created: ${request_created} (${request_age_minutes}m old)"
      echo "    Threshold: ${stuck_after_minutes}m"
      echo "    Approved: ${request_approved:-<unknown>}"
      echo "    Ready: ${request_ready:-<none>}"
      echo "    Reason: ${request_reason:-<none>}"
      [[ -n "${request_message:-}" ]] && echo "    Message: $request_message"
      echo "    Action: leave it alone for now"
    else
      echo "  Ready CertificateRequest: ${cert_ns}/${request_name}"
      echo "    Created: ${request_created} (${request_age_minutes}m old)"
      echo "    Approved: ${request_approved:-<unknown>}"
      echo "    Ready: ${request_ready:-<none>}"
      echo "    Reason: ${request_reason:-<none>}"
      [[ -n "${request_message:-}" ]] && echo "    Message: $request_message"
      echo "    Action: leave it alone because it is Ready"
    fi
  done

  echo
done

echo "Expired/problem certificates inspected: ${#problem_certs[@]}"
echo "Old/stuck CertificateRequests found: $stuck"
echo "Recent CertificateRequests left alone: $recent"
echo "Stale ACME Challenges found: $stale_challenges"
echo "Stale ACME Orders found: $stale_orders"
if [[ "$delete" == true ]]; then
  echo "Old/stuck CertificateRequests deleted: $deleted"
  echo "Stale ACME Challenges deleted: $deleted_challenges"
  echo "Stale ACME Orders deleted: $deleted_orders"
else
  echo "No changes made. Re-run with --delete to delete stale ACME Challenges, stale ACME Orders, and old/stuck CertificateRequests."
fi
