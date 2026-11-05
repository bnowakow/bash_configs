#!/usr/bin/python3
"""Apply only the five investigated Fleet bundles; retain backups and a report."""
import datetime
import json
import os
from pathlib import Path
import subprocess
import sys
import time

import yaml

ROOT = Path(__file__).resolve().parent
os.chdir(ROOT)
os.umask(0o077)
RUN = ROOT / ("fleet-health-repair-" + datetime.datetime.now().strftime("%Y%m%d-%H%M%S"))
RUN.mkdir()
REPORT = RUN / "report.txt"
KUBE = ["kubectl", "--kubeconfig", os.environ.get("KUBECONFIG", "/etc/rancher/k3s/k3s.yaml"), "--request-timeout=30s"]
BUNDLES = {
    "calibre-storage": "fleet/apps/calibre-storage",
    "longhorn-backups": "fleet/infrastructure/longhorn-backups",
    "traefik-resources": "fleet/infrastructure/traefik-resources",
    "cert-manager-resources": "fleet/infrastructure/cert-manager-resources",
    "cloudcasa": "fleet/infrastructure/cloudcasa",
}


def log(message):
    line = datetime.datetime.now().astimezone().isoformat() + " " + message
    print(line, flush=True)
    with REPORT.open("a") as f:
        f.write(line + "\n")


def command(args):
    result = subprocess.run(args, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or str(args))
    return result.stdout


def get(*args):
    return json.loads(command(KUBE + list(args) + ["-o", "json"]))


def save(name, value):
    path = RUN / name
    path.write_text(json.dumps(value, indent=2) + "\n")
    return path


def resource_args(obj):
    group = obj["apiVersion"].split("/")[0] if "/" in obj["apiVersion"] else ""
    kind = obj["kind"] + ("." + group if group else "")
    return ["-n", obj["metadata"]["namespace"], kind, obj["metadata"]["name"]]


def main():
    log("Preflight; no storage copies or workload scaling are performed.")
    current = {name: get("-n", "fleet-local", "get", "bundle", name) for name in BUNDLES}
    for name, obj in current.items():
        if obj["metadata"].get("labels", {}).get("fleet.cattle.io/repo-name") != "rancher-cluster":
            raise RuntimeError(f"Unexpected GitRepo owner on {name}")
        save(name + "-before.json", obj)

    pvcs = get("-n", "apps-calibre", "get", "pvc")["items"]
    claims = {p["metadata"]["name"]: p for p in pvcs}
    old_claims = {"calibre-library", "calibre-web-config"}
    if old_claims & claims.keys():
        raise RuntimeError("Old Calibre PVC exists again; stop and inspect before retiring its manifests")
    for name in ["calibre-library-longhorn-rwo", "calibre-web-config-longhorn-rwo"]:
        if claims.get(name, {}).get("status", {}).get("phase") != "Bound":
            raise RuntimeError(f"Replacement claim {name} is not Bound")
    pods = get("-n", "apps-calibre", "get", "pods")
    save("calibre-pods-before.json", pods)
    for pod in pods["items"]:
        for volume in pod["spec"].get("volumes", []):
            if volume.get("persistentVolumeClaim", {}).get("claimName") in old_claims:
                raise RuntimeError("A pod still references an old Calibre claim")

    releases = json.loads(command(["helm", "--kubeconfig", KUBE[2], "list", "-A", "--all", "-o", "json"]))
    if any(r["name"] == "traefik-resources" and r["namespace"] != "fleet-local" for r in releases):
        raise RuntimeError("Traefik resources has a Helm release outside fleet-local; inspect before proceeding")

    deployment = get("-n", "cloudcasa-io", "get", "deployment", "cloudcasa-kubeagent-manager")
    container = deployment["spec"]["template"]["spec"]["containers"][0]
    image = "cloudcasaAgent.azurecr.io/catalogicsoftware/amds-kagent:3.1.0-production.48"
    env = {e["name"]: e.get("value") for e in container.get("env", [])}
    if container["image"] != image or env.get("KUBEMOVER_IMAGE") != image:
        raise RuntimeError("CloudCasa images changed since inspection; inspect before pinning")
    log("CloudCasa manager and mover already use the pinned image; preserving it in Fleet.")

    # Generate every bundle first. Preserve the live GitRepo's exact targeting.
    prepared = {}
    for name, directory in BUNDLES.items():
        rendered = command(["fleet", "apply", "--kubeconfig", KUBE[2], "-n", "fleet-local", "-o", "-", name, directory])
        documents = list(yaml.safe_load_all(rendered))
        objects = []
        for doc in documents:
            if doc:
                objects.extend(doc["items"] if doc.get("kind") == "List" else [doc])
        bundles = [o for o in objects if o.get("kind") == "Bundle"]
        if len(bundles) != 1 or bundles[0]["metadata"]["name"] != name:
            raise RuntimeError(f"Unexpected generated Bundle set for {name}")
        bundle = bundles[0]
        bundle["metadata"]["labels"] = current[name]["metadata"].get("labels", {})
        for key in ["targets", "targetRestrictions", "targetCustomizationMode", "forceSyncGeneration"]:
            if key in current[name]["spec"]:
                bundle["spec"][key] = current[name]["spec"][key]
        prepared[name] = save(name + "-generated.json", {"apiVersion": "v1", "kind": "List", "items": objects})
        command(KUBE + ["apply", "--dry-run=server", "-f", str(prepared[name])])
        log(f"Generated {name}; preserved live ownership labels and targeting.")

    # Only adopt manifest resources that are unowned or already owned by this release.
    adoptions = []
    for name, namespace in [("longhorn-backups", "longhorn-system"), ("traefik-resources", "fleet-local")]:
        for path in sorted((ROOT / BUNDLES[name]).glob("*.yaml")):
            if path.name == "fleet.yaml":
                continue
            for desired in yaml.safe_load_all(path.read_text()):
                if not desired:
                    continue
                desired["metadata"].setdefault("namespace", namespace)
                args = resource_args(desired)
                raw = command(KUBE + args[:2] + ["get"] + args[2:] + ["--ignore-not-found", "-o", "json"])
                if not raw.strip():
                    continue
                obj = json.loads(raw)
                meta = obj["metadata"]
                annotations = meta.get("annotations", {})
                labels = meta.get("labels", {})
                if annotations.get("meta.helm.sh/release-name") not in [None, name]:
                    raise RuntimeError(f"Conflicting Helm owner for {meta['name']}")
                if annotations.get("meta.helm.sh/release-namespace") not in [None, namespace]:
                    raise RuntimeError(f"Conflicting Helm namespace for {meta['name']}")
                if labels.get("app.kubernetes.io/managed-by") not in [None, "Helm"] or meta.get("ownerReferences"):
                    raise RuntimeError(f"Conflicting controller for {meta['name']}")
                if name == "longhorn-backups":
                    if any(obj["spec"].get(k) != v for k, v in desired["spec"].items()):
                        raise RuntimeError("Live backup schedule differs from Git; inspect before adoption")
                save(f"{name}-{desired['kind']}-{meta['name']}-before.json", obj)
                patch = {"metadata": {"resourceVersion": meta["resourceVersion"],
                    "labels": {"app.kubernetes.io/managed-by": "Helm"},
                    "annotations": {"meta.helm.sh/release-name": name, "meta.helm.sh/release-namespace": namespace}}}
                adoptions.append((args, patch))

    log("All preflight checks passed. Applying metadata ownership and Fleet-generated bundles.")
    for args, patch in adoptions:
        command(KUBE + args[:2] + ["patch"] + args[2:] + ["--type=merge", "-p", json.dumps(patch)])
        log("Confirmed Helm ownership metadata on " + " ".join(args))
    for name, path in prepared.items():
        log(command(KUBE + ["apply", "-f", str(path)]).strip())

    deadline = time.monotonic() + 600
    pending = set(BUNDLES)
    while pending and time.monotonic() < deadline:
        for name in list(pending):
            obj = get("-n", "fleet-local", "get", "bundle", name)
            status = obj.get("status", {})
            ready = any(c["type"] == "Ready" and c["status"] == "True" for c in status.get("conditions", []))
            if ready and status.get("observedGeneration") == obj["metadata"]["generation"]:
                pending.remove(name)
                log(f"Confirmed current Bundle generation Ready: {name}")
        if pending:
            log("Waiting: " + ", ".join(sorted(pending)))
            time.sleep(10)
    for name in BUNDLES:
        save(name + "-after.json", get("-n", "fleet-local", "get", "bundle", name))
    deployments = get("get", "bundledeployments", "-A")
    save("bundledeployments-after.json", deployments)
    for name in BUNDLES:
        matches = [o for o in deployments["items"] if o["metadata"]["name"] == name]
        if not matches or any(o.get("status", {}).get("appliedDeploymentID") != o["spec"].get("deploymentID") for o in matches):
            raise RuntimeError(f"BundleDeployment has not applied its current deployment ID: {name}")
        log(f"Confirmed BundleDeployment applied current deployment ID: {name}")
    if pending:
        raise RuntimeError("Timed out waiting for Bundle readiness: " + ", ".join(sorted(pending)))
    for name in ["calibre", "calibre-web", "kavita"]:
        log(command(KUBE + ["-n", "apps-calibre", "rollout", "status", "deployment/" + name, "--timeout=120s"]).strip())
    log(command(KUBE + ["-n", "cloudcasa-io", "rollout", "status", "deployment/cloudcasa-kubeagent-manager", "--timeout=120s"]).strip())
    after_pods = get("-n", "apps-calibre", "get", "pods")
    save("calibre-pods-after.json", after_pods)
    for pod in after_pods["items"]:
        if pod["status"].get("phase") != "Running":
            continue
        mounts = [v["persistentVolumeClaim"]["claimName"] for v in pod["spec"].get("volumes", []) if "persistentVolumeClaim" in v]
        if old_claims.intersection(mounts):
            raise RuntimeError("A running Calibre pod references retired storage")
        log(f"Running pod {pod['metadata']['name']} mounts claims: {', '.join(mounts)}")
    for name in ["calibre-library-longhorn-rwo", "calibre-web-config-longhorn-rwo"]:
        if get("-n", "apps-calibre", "get", "pvc", name).get("status", {}).get("phase") != "Bound":
            raise RuntimeError(f"Replacement claim {name} is no longer Bound")
    log(command(KUBE + ["wait", "clusterissuer/letsencrypt", "--for=condition=Ready", "--timeout=120s"]).strip())
    log(command(KUBE + ["-n", "pve-proxy", "wait", "certificate/pve-ui", "--for=condition=Ready", "--timeout=120s"]).strip())
    for host in ["proxmox2-old.localdomain.bnowakowski.pl", "proxmox2-old.tailscale.bnowakowski.pl"]:
        result = command(["curl", "--fail", "--show-error", "--silent", "--max-time", "30", "--output", "/dev/null", "--write-out", "%{http_code}", "https://" + host + "/"]).strip()
        log(f"Confirmed HTTPS ingress {host}: HTTP {result}")
    log(command(KUBE + ["-n", "apps-calibre", "get", "pvc"]).strip())
    log(command(KUBE + ["-n", "fleet-local", "get", "gitrepo", "rancher-cluster"]).strip())
    log("Repair and validation finished. No commit or push performed.")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        log("FAILED: " + str(exc))
        log("Changes already applied are retained. Inspect the report and before/after snapshots.")
        sys.exit(1)
    finally:
        print("Report: " + str(REPORT), flush=True)
