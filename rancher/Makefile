.PHONY: help k3s-inventory k3s-inventory-check k3s-nodes-check k3s-nodes-apply

.DEFAULT_GOAL := help

ANSIBLE_DIR := ansible
# Extra options for run-cluster-nodes.sh, e.g.
#   make k3s-nodes-apply ARGS="--limit proxmox3"
#   make k3s-nodes-apply ARGS="--become-password-file ../../tmp-sudo-password"
ARGS ?=

help:
	@echo "Rancher cluster targets"
	@echo ""
	@echo "  k3s-inventory        Regenerate ansible/inventory/k3s-cluster.ini from"
	@echo "                       nas/ansible/inventory/proxmox-vms.yml, filtered to live k3s nodes"
	@echo "  k3s-inventory-check  Show the inventory diff only; fails if it is out of date"
	@echo "  k3s-nodes-check      Dry-run site.yml host config on the k3s nodes (--check --diff)"
	@echo "  k3s-nodes-apply      Apply site.yml host config (host-prep, longhorn-disks) to the k3s nodes"
	@echo ""
	@echo "  Pass run-cluster-nodes.sh options with ARGS=\"...\", e.g. ARGS=\"--limit proxmox3\""

k3s-inventory:
	cd $(ANSIBLE_DIR) && ./sync-k3s-inventory.sh

k3s-inventory-check:
	cd $(ANSIBLE_DIR) && ./sync-k3s-inventory.sh --check

k3s-nodes-check:
	cd $(ANSIBLE_DIR) && ./run-cluster-nodes.sh --check --diff $(ARGS)

k3s-nodes-apply:
	cd $(ANSIBLE_DIR) && ./run-cluster-nodes.sh $(ARGS)
