#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
k=(kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n apps-bookstack)
private=/tmp/longhorn-bookstack-originals
services=(svc-cron svc-queue-worker svc-nginx svc-php-fpm)
"${k[@]}" wait --for=condition=Ready pod/bookstack-config-transfer-20261025 --timeout=55s
"${k[@]}" cp "$here/config-manifest.php" bookstack-58946d95dc-2dwk8:/tmp/migration-manifest.php -c bookstack
"${k[@]}" cp "$here/check-config.py" bookstack-config-transfer-20261025:/tmp/check-config.py -c transfer
frozen=1
# Called by EXIT if the short freeze fails before old pod retirement.
# shellcheck disable=SC2317
resume_on_failure() {
 result=$?
 if [ "$result" -ne 0 ] && [ "$frozen" -eq 1 ]; then
  for service in "${services[@]}"; do "${k[@]}" exec deployment/bookstack -c bookstack -- s6-svc -u "/run/service/$service" || true; done
 fi
 exit "$result"
}
trap resume_on_failure EXIT
for service in "${services[@]}"; do
 if [ "$service" = svc-php-fpm ]; then signal=-dq; else signal=-d; fi
 "${k[@]}" exec deployment/bookstack -c bookstack -- s6-svc "$signal" "/run/service/$service"
done
# The supervisor lacks CAP_KILL for processes owned by abc.
"${k[@]}" exec deployment/bookstack -c bookstack -- s6-setuidgid abc sh -c 'pkill -TERM -u 568 -x php || true; pkill -QUIT -u 568 -x php-fpm85 || true'
for service in "${services[@]}"; do
 echo "Waiting for $service shutdown"
 "${k[@]}" exec deployment/bookstack -c bookstack -- s6-svwait -d -t 10000 "/run/service/$service"
done
"${k[@]}" exec deployment/bookstack -c bookstack -- tar -C /config -cpf - . > "$private/config-frozen.tar"
chmod 600 "$private/config-frozen.tar"
"${k[@]}" exec deployment/bookstack -c bookstack -- php /tmp/migration-manifest.php > "$private/config-manifest.json"
"${k[@]}" exec -i bookstack-config-transfer-20261025 -c transfer -- tar -C /target/config -xpf - < "$private/config-frozen.tar"
"${k[@]}" exec -i bookstack-config-transfer-20261025 -c transfer -- python /tmp/check-config.py /target/config < "$private/config-manifest.json"
"${k[@]}" exec bookstack-config-transfer-20261025 -c transfer -- sync -f /target/config
"${k[@]}" scale deployment bookstack --replicas=0
frozen=0
gone=0
for ((i=0;i<4;i++)); do
 if "${k[@]}" wait --for=delete pod/bookstack-58946d95dc-2dwk8 --timeout=55s; then gone=1; break; fi
done
[ "$gone" -eq 1 ] || exit 1
"${k[@]}" delete pod bookstack-config-transfer-20261025 --wait=true
cp "$here/config-stage-values.yaml" "$root/fleet/apps/bookstack/values.yaml"
cp "$here/final-fleet.yaml" "$root/fleet/apps/bookstack/fleet.yaml"
"$here/../pilot-2026-10-24/apply-bundle.sh" bookstack rancher/fleet/apps/bookstack
for ((i=0;i<90;i++)); do
 if "${k[@]}" get deployment bookstack -o json | jq -e '.spec.replicas==1 and any(.spec.template.spec.volumes[];.persistentVolumeClaim.claimName=="bookstack-config-longhorn-rwo")' >/dev/null; then break; fi
 sleep 2
done
for ((i=0;i<5;i++)); do
 if "${k[@]}" rollout status deployment/bookstack --timeout=55s; then echo 'BookStack config persisted and app restarted against original MariaDB'; exit 0; fi
done
exit 1
