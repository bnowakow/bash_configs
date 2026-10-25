#!/usr/bin/env sh
set -eu
mariadbd --no-defaults --basedir=/opt/bitnami/mariadb --datadir=/target/db/data --socket=/tmp/bookstack-verify.sock --pid-file=/tmp/bookstack-verify.pid --skip-networking --skip-grant-tables --event-scheduler=OFF --skip-log-bin --innodb-buffer-pool-size=128M --aria-pagecache-buffer-size=32M --log-error=/tmp/bookstack-verify.log &
pid=$!
trap 'kill -TERM "$pid" 2>/dev/null || true; wait "$pid" || true' EXIT
ready=0
for _attempt in $(seq 1 90); do
 if mariadb --no-defaults --socket=/tmp/bookstack-verify.sock -uroot -NBe 'SELECT 1' >/dev/null 2>&1; then ready=1; break; fi
 kill -0 "$pid"
 sleep 1
done
[ "$ready" = 1 ] || { cat /tmp/bookstack-verify.log; exit 1; }
if ! mariadb-check --no-defaults --socket=/tmp/bookstack-verify.sock -uroot --all-databases --check > /tmp/bookstack-tables-check.txt; then
 cat /tmp/bookstack-tables-check.txt
 cat /tmp/bookstack-verify.log
 exit 1
fi
if grep -Ei '(^|[[:space:]])(error|corrupt)([[:space:]:]|$)' /tmp/bookstack-tables-check.txt; then exit 1; fi
mariadb --no-defaults --socket=/tmp/bookstack-verify.sock -uroot -N < /tmp/bookstack-checksums.sql > /tmp/database-checksums.txt
mariadb --no-defaults --socket=/tmp/bookstack-verify.sock -uroot -NBe 'SELECT VERSION(); SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA="bookstack";' 
printf 'Isolated MariaDB startup and all-database table checks passed\n'
kill -TERM "$pid"
wait "$pid"
trap - EXIT
printf 'Isolated MariaDB stopped cleanly\n'
