#!/usr/bin/env bash
# Dev database helper (docs/MIGRATIONS.md). DEV ONLY — never point this at
# production: `reset` drops the database and `revert` runs down migrations.
#
#   db.sh status         applied vs on-disk migrations
#   db.sh check          drift detection: stranded ledger rows, edited files
#   db.sh new <name>     create the next NNNN_<name>.up.sql/.down.sql pair
#   db.sh revert [n]     revert the last n migrations (default 1; sqlx-cli)
#   db.sh reset          drop, recreate, and re-migrate the database
set -eu
cd "$(dirname "$0")/../.."          # repo root
MIG=backend/migrations

# DATABASE_URL from the environment, falling back to backend/.env
if [ -z "${DATABASE_URL:-}" ] && [ -f backend/.env ]; then
    DATABASE_URL=$(grep -E '^DATABASE_URL=' backend/.env | head -1 | cut -d= -f2-)
fi
[ -n "${DATABASE_URL:-}" ] || { echo "DATABASE_URL not set (env or backend/.env)" >&2; exit 1; }

find_psql() {
    command -v psql 2>/dev/null && return
    for p in /Applications/Postgres.app/Contents/Versions/latest/bin/psql \
             /opt/homebrew/bin/psql /usr/local/bin/psql; do
        [ -x "$p" ] && { echo "$p"; return; }
    done
    echo "psql not found" >&2; exit 1
}
PSQL=$(find_psql)

sha384() {
    if command -v shasum >/dev/null 2>&1; then shasum -a 384 "$1" | cut -d' ' -f1
    elif command -v sha384sum >/dev/null 2>&1; then sha384sum "$1" | cut -d' ' -f1
    else openssl dgst -sha384 -r "$1" | cut -d' ' -f1; fi
}

q() { "$PSQL" "$DATABASE_URL" -X -Atc "$1"; }

up_file_for() {  # version like 3 -> path of 0003_*.up.sql (or legacy .sql)
    pad=$(printf '%04d' "$1")
    for f in "$MIG/${pad}_"*.up.sql "$MIG/${pad}_"*.sql; do
        [ -e "$f" ] && { echo "$f"; return; }
    done
    return 1
}

applied_rows() { q "SELECT version||E'\t'||description||E'\t'||encode(checksum,'hex') FROM _sqlx_migrations ORDER BY version;" 2>/dev/null; }

cmd_status() {
    echo "database: $DATABASE_URL"
    echo
    rows=$(applied_rows) || { echo "no _sqlx_migrations table — database has never been migrated"; }
    printf '%-9s %-42s %s\n' "version" "migration" "state"
    while IFS=$'\t' read -r v desc _cksum; do
        [ -n "$v" ] || continue
        if f=$(up_file_for "$v"); then state="applied"; else state="applied, FILE MISSING"; fi
        printf '%-9s %-42s %s\n' "$v" "$desc" "$state"
    done <<EOF
$rows
EOF
    for f in "$MIG"/*.up.sql; do
        [ -e "$f" ] || continue
        v=$((10#$(basename "$f" | cut -c1-4)))
        if ! printf '%s\n' "$rows" | cut -f1 | grep -qx "$v"; then
            printf '%-9s %-42s %s\n' "$v" "$(basename "$f")" "pending"
        fi
    done
}

cmd_check() {
    fail=0
    rows=$(applied_rows) || { echo "no _sqlx_migrations table — run migrations first"; exit 1; }
    while IFS=$'\t' read -r v desc cksum; do
        [ -n "$v" ] || continue
        if ! f=$(up_file_for "$v"); then
            echo "DRIFT: version $v ($desc) is applied but has no file on this branch."
            echo "       Fix: run its .down.sql by hand against this DB, then"
            echo "       DELETE FROM _sqlx_migrations WHERE version = $v;  (or: db.sh reset)"
            fail=1
            continue
        fi
        if [ "$(sha384 "$f")" != "$cksum" ]; then
            echo "DRIFT: $f was edited after being applied (checksum mismatch)."
            echo "       Restore the original content (git checkout) or db.sh reset."
            fail=1
        fi
    done <<EOF
$rows
EOF
    [ "$fail" -eq 0 ] && echo "no drift: applied history matches the files on disk"
    exit "$fail"
}

cmd_new() {
    name="${1:?usage: db.sh new <snake_case_name>}"
    printf '%s' "$name" | grep -qE '^[a-z0-9_]+$' || { echo "name must be snake_case [a-z0-9_]" >&2; exit 1; }
    last=$(ls "$MIG" | grep -oE '^[0-9]{4}' | sort -u | tail -1)
    next=$(printf '%04d' $((10#${last:-0} + 1)))
    up="$MIG/${next}_${name}.up.sql"; down="$MIG/${next}_${name}.down.sql"
    printf -- '-- %s\n' "$name" > "$up"
    printf -- '-- Reverse of %s_%s.\n' "$next" "$name" > "$down"
    echo "created $up"
    echo "created $down"
    echo "Remember: the down must exactly reverse the up (docs/MIGRATIONS.md)."
}

cmd_revert() {
    n="${1:-1}"
    command -v sqlx >/dev/null 2>&1 || { echo "sqlx-cli required: brew install sqlx-cli" >&2; exit 1; }
    i=0
    while [ "$i" -lt "$n" ]; do
        sqlx migrate revert --source "$MIG" --database-url "$DATABASE_URL"
        i=$((i + 1))
    done
}

cmd_reset() {
    db="${DATABASE_URL##*/}"; db="${db%%\?*}"
    admin="${DATABASE_URL%/*}/postgres"
    printf 'This DROPS database "%s" and re-runs all migrations. Continue? [y/N] ' "$db"
    read -r ans
    [ "$ans" = "y" ] || [ "$ans" = "Y" ] || { echo "aborted"; exit 1; }
    "$PSQL" "$admin" -X -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$db' AND pid <> pg_backend_pid();" >/dev/null
    "$PSQL" "$admin" -X -c "DROP DATABASE IF EXISTS \"$db\";"
    "$PSQL" "$admin" -X -c "CREATE DATABASE \"$db\";"
    if command -v sqlx >/dev/null 2>&1; then
        sqlx migrate run --source "$MIG" --database-url "$DATABASE_URL"
    else
        echo "sqlx-cli not found — start the backend with RUN_MIGRATIONS=true to migrate,"
        echo "or: brew install sqlx-cli"
    fi
}

case "${1:-}" in
    status) cmd_status ;;
    check)  cmd_check ;;
    new)    shift; cmd_new "$@" ;;
    revert) shift; cmd_revert "${1:-1}" ;;
    reset)  cmd_reset ;;
    *)      sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
