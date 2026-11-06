# Zabbix chart 8 StatefulSet repair — 6 November 2026

Chart 8.0.0 changes the immutable PostgreSQL governing serviceName from `zabbix` to `zabbix-postgresql-headless`. The controller was replaced using orphan deletion with UID/resourceVersion preconditions, retaining its original pod and the existing Longhorn PVC. Native Fleet apply then deployed the chart. The subsequent chart rollout may restart PostgreSQL.

Completed validation and step-by-step action log: `zabbix-statefulset-repair-20261106-081210/report.txt`. Helm latest revision deployed chart 8.0.0; Fleet Bundle and current BundleDeployment Ready; PostgreSQL and application rollouts, database connection readiness and both HTTPS endpoints passed. PVC UID and bound PV were unchanged. No PVC data was copied or deleted; no credentials rotated. The scripts did not commit or push.
