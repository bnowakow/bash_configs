#!/usr/bin/python3
"""Relinquish only the two confirmed stale field claims, then retry Fleet."""
import copy
import datetime
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
KUBE = ["kubectl", "--kubeconfig", os.environ.get("KUBECONFIG", "/etc/rancher/k3s/k3s.yaml"), "--request-timeout=30s"]


def relinquish(fields, path):
    """Remove one field claim, pruning empty ancestors without claiming subtrees."""
    if not path or path[0] not in fields:
        return False
    key = path[0]
    if len(path) == 1:
        del fields[key]
        return True
    if not isinstance(fields[key], dict) or not relinquish(fields[key], path[1:]):
        return False
    if not fields[key]:
        del fields[key]
    return True


def payload(obj):
    return {k: v for k, v in obj.items() if k not in ["metadata", "status"]}


def main():
    os.umask(0o077)
    run = ROOT / ("fleet-field-ownership-" + datetime.datetime.now().strftime("%Y%m%d-%H%M%S"))
    run.mkdir()

    def log(message):
        line = datetime.datetime.now().astimezone().isoformat() + " " + message
        print(line, flush=True)
        with (run / "report.txt").open("a") as f:
            f.write(line + "\n")

    def command(args):
        result = subprocess.run(args, text=True, capture_output=True)
        if result.returncode:
            raise RuntimeError(result.stderr.strip() or result.stdout.strip())
        return result.stdout

    def get(args):
        return json.loads(command(KUBE + args + ["-o", "json", "--show-managed-fields"]))

    def save(name, data):
        path = run / name
        path.write_text(json.dumps(data, indent=2) + "\n")
        return path

    def check_unchanged(before, after):
        if before["metadata"]["uid"] != after["metadata"]["uid"] or payload(before) != payload(after):
            raise RuntimeError("Resource identity or workload configuration changed; stop and inspect snapshots")

    try:
        targets = [
            (["-n", "pve-proxy", "get", "endpointslice", "pve-api-ipv4"],
             "kubectl-client-side-apply", ["f:endpoints"], "traefik-resources"),
            (["-n", "cloudcasa-io", "get", "deployment", "cloudcasa-kubeagent-manager"],
             "cloudcasa-kubeagent-manager", ["f:spec", "f:template", "f:spec", "f:containers",
              'k:{"name":"kubeagentmanager"}', "f:env", 'k:{"name":"MY_POD_NAME"}',
              "f:valueFrom", "f:fieldRef"], "cloudcasa"),
        ]
        plans = []
        # Validate both plans and server dry runs before either metadata patch.
        for args, manager, path, bundle in targets:
            before = get(args)
            save(bundle + "-resource-before.json", before)
            annotations = before["metadata"].get("annotations", {})
            if annotations.get("meta.helm.sh/release-name") != bundle:
                raise RuntimeError("Unexpected Helm release owner on " + before["metadata"]["name"])
            if bundle == "traefik-resources":
                if before["endpoints"] != [{"addresses": ["10.0.0.72"], "conditions": {}}]:
                    raise RuntimeError("PVE endpoints changed since inspection")
            else:
                containers = before["spec"]["template"]["spec"]["containers"]
                container = next(c for c in containers if c["name"] == "kubeagentmanager")
                ref = next(e for e in container["env"] if e["name"] == "MY_POD_NAME")
                if ref.get("valueFrom") != {"fieldRef": {"apiVersion": "v1", "fieldPath": "metadata.name"}}:
                    raise RuntimeError("CloudCasa pod-name reference changed since inspection")
                if container["image"] != "cloudcasaAgent.azurecr.io/catalogicsoftware/amds-kagent:3.1.0-production.48":
                    raise RuntimeError("CloudCasa image changed since inspection")
            original = before["metadata"].get("managedFields", [])
            updated = copy.deepcopy(original)
            changed = 0
            for entry in updated:
                if entry.get("manager") == manager and not entry.get("subresource"):
                    changed += relinquish(entry.get("fieldsV1", {}), path)
            if not changed:
                raise RuntimeError(f"Expected field ownership not found for {bundle}; no broad reset will be used")
            updated = [e for e in updated if e.get("fieldsV1")]
            if not updated:
                raise RuntimeError("Refusing to clear all field ownership")
            patch = [
                {"op": "test", "path": "/metadata/resourceVersion", "value": before["metadata"]["resourceVersion"]},
                {"op": "test", "path": "/metadata/managedFields", "value": original},
                {"op": "replace", "path": "/metadata/managedFields", "value": updated},
            ]
            path_file = save(bundle + "-metadata-patch.json", patch)
            patch_args = args[:2] + ["patch"] + args[3:] + ["--type=json", "--patch-file", str(path_file), "-o", "json", "--show-managed-fields"]
            simulated = json.loads(command(KUBE + patch_args + ["--dry-run=server"]))
            check_unchanged(before, simulated)
            plans.append((bundle, args, patch_args, before))
            log(f"Server dry run passed for {bundle}; only {manager}'s {'/'.join(path)} claim will be relinquished")
        for bundle, args, patch_args, before in plans:
            after = json.loads(command(KUBE + patch_args))
            save(bundle + "-resource-after.json", after)
            check_unchanged(before, after)
            log(f"Confirmed {bundle} metadata repair; resource UID and configuration are unchanged")
        for bundle, *_ in plans:
            before = get(["-n", "fleet-local", "get", "bundle", bundle])
            previous = before["spec"].get("forceSyncGeneration", 0)
            patch = {"metadata": {"resourceVersion": before["metadata"]["resourceVersion"]},
                     "spec": {"forceSyncGeneration": previous + 1}}
            save(bundle + "-bundle-before.json", before)
            after = json.loads(command(KUBE + ["-n", "fleet-local", "patch", "bundle", bundle,
                "--type=merge", "-p", json.dumps(patch), "-o", "json"]))
            save(bundle + "-bundle-after.json", after)
            if after["spec"].get("forceSyncGeneration") != previous + 1:
                raise RuntimeError("Requested sync generation was not applied")
            log(f"Confirmed targeted Fleet retry for {bundle}: sync generation {previous} -> {previous + 1}; readiness remains pending")
        log("Metadata repairs complete; keep monitoring the existing repair script for readiness and rollout validation.")
    except Exception as exc:
        log("FAILED: " + str(exc))
        return 1
    finally:
        print("Report: " + str(run / "report.txt"), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
