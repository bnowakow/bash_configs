# Docker resource monitor

`docker-resource-monitor.service` records a host and Docker snapshot every 30 seconds in `/var/log/docker-resource-monitor/`. It also records Docker container lifecycle events immediately. Logs are compressed and retained for 21 days.

To investigate a Jetpack alert, give Codex its timestamp or run:

```bash
/home/sup/code/bash_configs/ovh/docker-resource-monitor/resource-report.sh '2026-09-18 18:55:00 CEST'
```

The report displays ten minutes before and after the given time, including resource snapshots, restarts/OOM state, Docker events, and matching kernel OOM or blocked-task messages.

The maintained logrotate source is `docker-resource-monitor.logrotate`; it is installed at `/etc/logrotate.d/docker-resource-monitor`.
