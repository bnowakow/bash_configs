#!/bin/bash

# TODO make sure it's root

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# https://www.bookstack.cn/read/longhorn-1.6.3-en/cb37176a301d5f07.md#prerequisite
# https://github.com/longhorn/longhorn/issues/5187#issuecomment-1369354673
kubectl -n longhorn-system patch -p '{"value": "true"}' --type=merge lhs deleting-confirmation-flag
helm uninstall longhorn --namespace longhorn-system --debug


