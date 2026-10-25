#!/bin/sh
set -eu
pgdir=/target/pgdata
# Same PostgreSQL minor release as the source; native manifest and WAL checks.
gosu postgres ionice -c 3 pg_verifybackup --exit-on-error "$pgdir"
mkdir -p /tmp/zabbix-verify-socket
chown postgres:postgres /tmp/zabbix-verify-socket
chmod 700 /tmp/zabbix-verify-socket
opts="-c data_directory=$pgdir -c hba_file=$pgdir/pg_hba.conf -c ident_file=$pgdir/pg_ident.conf -c listen_addresses='' -c unix_socket_directories=/tmp/zabbix-verify-socket -c port=55432 -c shared_buffers=128MB -c max_connections=50"
gosu postgres pg_ctl -D "$pgdir" -o "$opts" -l /tmp/zabbix-verify.log -w start
trap 'gosu postgres pg_ctl -D "$pgdir" -m fast -w stop >/dev/null 2>&1 || true' EXIT INT TERM
psql -h /tmp/zabbix-verify-socket -p 55432 -U zabbix -d zabbix -At -v ON_ERROR_STOP=1 -c \
 "SELECT 'system_identifier='||system_identifier FROM pg_control_system(); SELECT 'schema='||mandatory||':'||optional FROM dbversion; SELECT 'recovery='||pg_is_in_recovery(); SELECT 'public_tables='||count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN ('r','p');"
gosu postgres pg_ctl -D "$pgdir" -m fast -w stop
trap - EXIT INT TERM
printf '%s\n' 'Native basebackup restored, manifest/WAL verified, isolated PostgreSQL started and stopped cleanly'
