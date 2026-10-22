# Fleet changes

Before pushing changes under this directory, apply every changed bundle that
can be applied to the configured cluster and validate the resulting deployment.
Do this before `git push`, including when preparing changes for the user to push.

Use Fleet-native bundle generation and application, preserve existing GitRepo
ownership labels and targeting, and apply only the bundles changed for the task.
For new bundles, use the existing `rancher-cluster` GitRepo ownership and local
cluster targeting. Do not use a direct `helm install` to bypass Fleet.

Check Fleet BundleDeployment readiness, workload rollout, storage mounts and
configured ingress endpoints as applicable. Do not claim success based only on
manifest generation or a successful apply command.

If an apply or validation cannot be completed, report the exact blocker and
which changes remain unapplied or unverified before pushing. Do not bypass
required tool approvals or perform destructive storage operations to satisfy
this rule. Do not push unless the user has authorized it.
