#!/usr/bin/env bash
# Migration history guard (docs/MIGRATIONS.md).
#
# Enforces that backend/migrations is append-only:
#   - every file is NNNN_snake_name.up.sql / NNNN_snake_name.down.sql
#   - every version has exactly one up/down pair, no duplicate versions
#   - relative to the base ref, migrations are only ever ADDED — never
#     modified, deleted, or renamed. The single exception is converting a
#     legacy simple migration NNNN_x.sql to NNNN_x.up.sql with byte-identical
#     content (checksum-safe by construction).
#
# Usage: check_migrations.sh [base-ref]
#   base-ref defaults to $BASE_REF, then merge-base with origin/main.
#   With no resolvable base, only the static checks run.
set -eu
cd "$(git rev-parse --show-toplevel)"
DIR=backend/migrations
fail=0

err() { echo "ERROR: $*" >&2; fail=1; }

# ---------------------------------------------------------- static checks
stems=""
found=0
for f in "$DIR"/*.sql; do
    [ -e "$f" ] || continue
    found=1
    base=$(basename "$f")
    case "$base" in
        *.up.sql)   stem=${base%.up.sql} ;;
        *.down.sql) stem=${base%.down.sql} ;;
        *)          err "bad migration filename: $base (expected NNNN_snake_name.up.sql/.down.sql)"; continue ;;
    esac
    if ! printf '%s' "$stem" | grep -qE '^[0-9]{4}_[a-z0-9_]+$'; then
        err "bad migration filename: $base (expected NNNN_snake_name.up.sql/.down.sql)"
        continue
    fi
    stems="$stems$stem"$'\n'
done
[ "$found" -eq 1 ] || err "no migrations found in $DIR"

stems=$(printf '%s' "$stems" | sort -u)
for stem in $stems; do
    [ -f "$DIR/$stem.up.sql" ]   || err "missing $stem.up.sql (down exists without up)"
    [ -f "$DIR/$stem.down.sql" ] || err "missing $stem.down.sql (every migration needs a down)"
done

dupes=$(printf '%s\n' "$stems" | cut -c1-4 | sort | uniq -d)
[ -z "$dupes" ] || err "duplicate migration version(s): $(echo "$dupes" | tr '\n' ' ')— renumber the unmerged branch's migration"

# ------------------------------------------------------ history is append-only
base="${1:-${BASE_REF:-}}"
if [ -z "$base" ] || printf '%s' "$base" | grep -qE '^0+$'; then
    if git rev-parse --verify -q origin/main >/dev/null 2>&1; then
        base=$(git merge-base origin/main HEAD)
    else
        base=""
    fi
fi

if [ -n "$base" ] && git rev-parse --verify -q "$base^{commit}" >/dev/null 2>&1; then
    while IFS=$'\t' read -r status old new; do
        [ -n "$status" ] || continue
        case "$status" in
            A*) ;;                       # additions are the only normal change
            R100)
                # allow legacy NNNN_x.sql -> NNNN_x.up.sql, content identical
                if [ "$new" != "${old%.sql}.up.sql" ]; then
                    err "migration renamed: $old -> $new (applied migrations must keep their name)"
                fi
                ;;
            D*) err "migration deleted: $old (revert its schema first, see docs/MIGRATIONS.md)" ;;
            *)  err "migration modified: $old${new:+ -> $new} (write a new migration instead)" ;;
        esac
    done <<EOF
$(git diff --name-status -M100% "$base"...HEAD -- "$DIR")
EOF
else
    echo "note: no base ref to diff against; ran static checks only"
fi

if [ "$fail" -ne 0 ]; then
    echo
    echo "Migration history must be append-only once a file is on main." >&2
    echo "See docs/MIGRATIONS.md for the correct workflow." >&2
    exit 1
fi
echo "migration checks passed"
