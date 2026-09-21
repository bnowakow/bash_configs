# VM 401 noVNC black screen and GNOME restart investigation

Investigation date: 2026-09-20. Times below are local time in the guest (CEST, UTC+02:00).

## Symptoms

The Proxmox noVNC console for VM 401 sometimes displays the guest briefly and then turns black. Refreshing can return to the login screen, including after a successful GNOME login. After several refreshes, the desktop may remain usable.

## Host-side findings (reported separately)

- VM 401 remained running for about 22.5 hours; QEMU reported it as running. No QEMU crash, VM reboot, or VNC-server error was found.
- noVNC sessions started and ended normally in host logs. Browser/proxy connections closed during refreshes. Invalid PVE ticket messages coincided with refresh/re-authentication and did not explain the black screen.
- The Proxmox host showed intermittent storage latency: `txg_sync` was hung for more than 122 seconds, HA loops were delayed by up to 78 seconds, and recent live I/O pressure reached roughly 30–40%. VM 401 showed roughly 20% I/O pressure. This could cause visible freezes, but the host observations alone do not establish why the GNOME session restarted.
- The host NVMe SMART report showed no media/errors, 51°C, and 46% wear. That does not rule out storage-stack or load-related latency.

These host findings are from the separate host investigation; the commands below were run in the Ubuntu guest.

## Guest-side findings

The investigated shell is inside a KVM guest running Ubuntu 24.04.5 LTS. Its hostname is `crashplan-proxmox`, but it is not the Proxmox host (`qm` is unavailable). The guest uses the `bochs-drm` virtual display device; GNOME Shell was running as a Wayland display server.

### Failure timeline

| Time | Guest log observation |
| --- | --- |
| 14:30:28 and repeatedly afterward | systemd could not add control and memory inotify watches to cgroups: `No space left on device`. This predates the GNOME failure. |
| 14:37:48–14:37:50 | GNOME settings daemons reported broken display pipes. `gnome-session-binary` reported `Application 'org.gnome.Shell.desktop' killed by signal 9`, then `Unrecoverable failure in required component org.gnome.Shell.desktop`. |
| 14:37:51 | Xwayland reported a broken pipe. |
| 14:37:59–14:38:19 | The GDM greeter session closed and GDM cycled through sessions `c50` to `c58`. Several new greeter shells were also reported killed by signal 9. The inotify errors continued. |
| 14:39:12 | A new graphical login session for user `sup` (`session 192`) opened. |
| 14:39:14 | The previous greeter's GNOME Shell reported `Xwayland exited unexpectedly` while the new user session was starting. |

This directly supports the observed return to the login screen: the guest's graphical session was restarting. A browser refresh may simply reveal the new guest display. It does not prove that noVNC itself caused the restart.

### Inotify exhaustion and CrashPlan

At investigation time, `/proc/sys/fs/inotify/max_user_watches` was **1,048,576**. A read-only count of `/proc/*/fdinfo/*` showed that `/usr/local/crashplan/bin/CrashPlanService` (PID 1308, running as root) held **1,048,344 watches** across two inotify instances. This is about **99.98%** of the per-user watch limit and leaves only 232 watches for other processes with the same UID. systemd also runs as root and was reporting failed watch creation. CrashPlan had been running since 2026-09-19 16:27:48.

The guest root filesystem was 92% used with about 3.8 GiB available, and only 11% of its inodes were used. Thus the observed `No space left on device` watch errors are consistent with inotify exhaustion, not a full disk.

CrashPlan's systemd status reported about 6.6 GiB service memory at inspection time, an 11.4 GiB peak, and a 1.4 GiB swap peak. The guest has 12 GiB RAM and 1.5 GiB swap; swap was effectively full at inspection time. Those peaks are not timestamped to 14:37, so they are evidence of substantial resource use, not proof of a memory-triggered kill at that moment.

### Checks that did not identify the killer

- The guest kernel log for 14:30–14:45 showed no kernel OOM kill, GPU reset/error, guest I/O error, or hung task corresponding to the failure. Its messages in the immediate interval were mainly `rfkill` and hibernation-lockdown notices as sessions changed.
- The `systemd-oomd` journal had no entries for 14:30–14:40.
- No log entry identified the process that sent signal 9 to GNOME Shell. A SIGKILL does not produce a normal application crash dump.
- `coredumpctl` is not installed in this guest.
- `snapd-desktop-integration` was repeatedly failing to open a display and restarting (restart counter exceeded 750 around 14:37). This added noise and load to the session logs, but the evidence does not establish it as the cause of the GNOME kills.

## Assessment

There is a confirmed guest-side graphical session failure and a confirmed, severe inotify resource exhaustion caused by CrashPlan's watch use. The watch failures began before and continued through the GDM restart loop, making them the strongest actionable guest-side lead. **The logs do not prove that inotify exhaustion directly sent SIGKILL to GNOME Shell.** CrashPlan's high memory use and the separately observed host ZFS latency are additional plausible contributors; their timing has not been tied definitively to the first GNOME kill.

## Follow-up

1. Review CrashPlan's selected backup paths and file-monitoring behavior. Reduce the number of watched paths where practical, then verify that its watch count falls well below the limit.
2. If that is not practical, consider raising `fs.inotify.max_user_watches` in the guest as a mitigation, allowing headroom for systemd and other root processes. Monitor the resulting memory use; increasing the limit does not address the underlying number of watches.
3. Monitor CrashPlan memory and swap use, as well as guest and host I/O pressure, while reproducing the issue. Correlate timestamps between host and guest.
4. On recurrence, capture guest `journalctl` output for GNOME Shell, GDM, systemd, and the kernel immediately around the first black screen. Check whether watch creation errors precede another session restart and whether an OOM killer or explicit service action is logged.
5. If the graphical session remains stable while only the noVNC picture blacks out, investigate the Proxmox/Traefik WebSocket path separately.

After the investigation, at the user's request, the guest limit was raised to 2,097,152 in /etc/sysctl.conf and applied with sysctl -w. Both active and persistent values were verified. CrashPlan still held 1,048,344 watches at verification. The service was not restarted and its backup selection was not changed.
