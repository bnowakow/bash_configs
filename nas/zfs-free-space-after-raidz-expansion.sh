#!/bin/bash

# waiting fix to be merged and released and into TrueNAS: https://github.com/openzfs/zfs/pull/18324

# after RAIDZ expansion `zfs rewrite -r` should be run in order to calculate new parity ratios https://github.com/openzfs/zfs/issues/17784#issuecomment-4233316308

# don't know if that returns correct numbers
# https://github.com/openzfs/zfs/issues/18199#issuecomment-4056821366
sudo printf "%-12s %-10s %-10s %-10s %-6s\n" "POOL" "TOTAL" "USED" "FREE" "USED%"; zpool list -H -o name | while read pool; do used=$(zfs list -Hp -o used "$pool" 2>/dev/null); avail=$(zfs list -Hp -o available "$pool" 2>/dev/null); raw_size=$(zpool list -Hp -o size "$pool" 2>/dev/null); ndisk=$(zpool status "$pool" | grep -E "^\s+[a-zA-Z0-9_-]+\s+ONLINE" | grep -v "^\s*($(zpool list -H -o name | tr "\n" "|")logs|cache|spare|mirror|raidz)" | wc -l); nparity=$(zpool status "$pool" | grep -oP "raidz\K[0-9]" | head -1); if [ -n "$ndisk" ] && [ -n "$nparity" ] && [ "$ndisk" -gt 0 ]; then total=$(awk "BEGIN {printf \"%d\", $raw_size * ($ndisk - $nparity) / $ndisk}"); else total=$((used+avail)); fi; free=$((total-used)); pct=$(awk "BEGIN {printf \"%.1f\", ($used*100)/$total}"); used_hr=$(numfmt --to=iec "$used"); free_hr=$(numfmt --to=iec "$free"); total_hr=$(numfmt --to=iec "$total"); printf "%-12s %-10s %-10s %-10s %-6s\n" "$pool" "$total_hr" "$used_hr" "$free_hr" "$pct%"; done

