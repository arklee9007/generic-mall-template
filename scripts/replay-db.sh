#!/usr/bin/env bash
# 本地迁移真回放：全新 PG 簇 -> 建桩 -> 顺序执行全部迁移 -> 通用迁移重跑一次（幂等）-> 验收 SQL。
# 退出码非 0 即失败；簇在 /tmp，随跑随建、随停随删，不动系统集群。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK=/tmp/pg-replay-generic
PGBIN=/usr/lib/postgresql/16/bin
sudo -n true || { echo "need passwordless sudo for postgres user"; exit 1; }
sudo -u postgres rm -rf "$WORK"
sudo -u postgres mkdir -p "$WORK"
sudo -u postgres "$PGBIN/initdb" -D "$WORK/data" -U postgres --auth=trust >/dev/null
sudo -u postgres "$PGBIN/pg_ctl" -D "$WORK/data" -o "-p 54399 -k $WORK -c listen_addresses=''" -l "$WORK/log.txt" start >/dev/null
trap 'sudo -u postgres "$PGBIN/pg_ctl" -D "$WORK/data" stop -m fast >/dev/null 2>&1 || true; sudo -u postgres rm -rf "$WORK"' EXIT
PSQL="psql -h $WORK -p 54399 -U postgres -d postgres -v ON_ERROR_STOP=1 -q"
$PSQL -f "$ROOT/scripts/replay-setup.sql"
for f in "$ROOT"/cloudbase/migrations/*.sql; do echo "MIGRATION $(basename "$f")"; $PSQL -f "$f" || { echo "FAILED: $f"; sudo -u postgres cat "$WORK/log.txt" | tail -n 30; exit 1; }; done
echo "MIGRATION-REPLAY 20261115000000_generic_base.sql (idempotency, 2nd run)"
$PSQL -f "$ROOT/cloudbase/migrations/20261115000000_generic_base.sql"
echo "VERIFY"
$PSQL -f "$ROOT/scripts/verify-db.sql"
echo "REPLAY PASS"
