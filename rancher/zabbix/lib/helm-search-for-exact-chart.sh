#!/bin/bash

name="${1:-duckdns}"

# return only first result. elasticsearch is present in elastic helm repo and bitnami. adding zz-prefixes to get expected one as first. could be problematic in future
echo $(helm search repo $name | grep "/$name[^a-z-]" | head -n1)


