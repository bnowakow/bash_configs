#!/bin/bash

# https://stackoverflow.com/a/66362156
echo run as root, export kubeconfig

# https://k3s.rocks/https-cert-manager-letsencrypt/

cd /home/sup/code/bash_configs/rancher/cert-manager

cat cloudflare-api-token.yaml | envsubst | kubectl apply -f - \
    && cat cert-clusterissuer-prod.yaml | envsubst | kubectl apply -f - \
    && cat cert-clusterissuer-stag.yaml | envsubst | kubectl apply -f - \
    && ./test-cert-issue-prod.sh \
    && ./test-cert-issue-stag.sh


