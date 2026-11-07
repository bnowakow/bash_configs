# Provisioning and temporary rollback

- Whenever `provision.sh` gains or changes a persistent action, update
  `undo-provision.sh` in the same change to reverse it in the opposite order.
- Record changes in `~/.homelab-provision-state` outside the checkout. Track only
  resources created or modified by provisioning; preserve pre-existing resources.
  Record intent before operations that can partially fail and keep markers until
  rollback succeeds. Repeated provisioning runs must retain earlier markers.
- Keep rollback usable after a partial provisioning failure and when its own
  checkout is removed. Update the README with behavior and rollback limitations.
- Validate both scripts with `bash -n` and exercise changed branches using mocks
  or an isolated test environment. Do not install/uninstall real software or
  delete the working checkout just to test these scripts.
