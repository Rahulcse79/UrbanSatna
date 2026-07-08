# Database migrations — workflow and rules

How schema changes move through this repo safely: from a feature branch,
across branch switches and reverts, into production. SQLx migrations are the
only way the schema changes; there is no manual DDL against shared databases.

## TL;DR — the golden rules

1. **Applied migrations are immutable.** Once a migration file is on `main`,
   never edit, rename, renumber, or delete it. CI rejects such diffs
   (`backend/scripts/check_migrations.sh`). To change what it did, write a
   **new** migration.
2. **Every migration is a pair**: `NNNN_name.up.sql` + `NNNN_name.down.sql`.
   The down must exactly reverse the up. Down migrations are **development
   tools only** — production never runs `revert`; production fixes roll
   *forward* with a new migration.
3. **Versions are sequential** (`0001`, `0002`, …), created with
   `backend/scripts/db.sh new <name>`. If two branches claim the same number,
   the branch that merges second renumbers its (still unmerged) migration.
4. **Reverting an app commit does not revert the database.** If a commit that
   shipped a migration must be reverted, follow [§5](#5-reverting-a-commit-that-contained-a-migration) —
   deleting the file alone strands the ledger and the backend will refuse to start.
5. **Never bypass the ledger.** Don't hand-edit `_sqlx_migrations` except as
   part of the documented repair recipes below, and never in production.

## 1. How migrations run here

- Files live in `backend/migrations/` and are **embedded into the binary** at
  compile time (`sqlx::migrate!` in `backend/src/main.rs`).
- On startup, when `RUN_MIGRATIONS=true`, the app applies pending migrations
  before serving. SQLx takes a Postgres advisory lock, so several instances
  starting at once is safe — one migrates, the rest wait.
- Applied migrations are recorded in the `_sqlx_migrations` table: version,
  description, and a **SHA-384 checksum of the up file**. On every startup
  SQLx validates that ledger against the embedded files and refuses to boot on:
  - `VersionMissing` — the DB applied a version that no longer has a file
    (someone deleted/renamed a migration, or you switched to a branch that
    doesn't have it yet — see §4/§5);
  - `VersionMismatch` — the file's content changed after being applied
    (someone edited a shipped migration).

  These errors are the guard rails working, not something to silence: never
  enable `ignore_missing` to make them go away.

## 2. Writing a migration

```bash
backend/scripts/db.sh new add_worker_ratings   # creates 00NN_add_worker_ratings.{up,down}.sql
```

- **Ups** follow CLAUDE.md §6: UUID PKs, `created_at`/`updated_at` +
  trigger, soft delete, money in BIGINT paise, CHECK-constrained statuses,
  index every FK and hot filter column.
- **Downs** reverse the up exactly, in reverse order: drop what it created,
  un-alter what it altered, delete precisely the rows it seeded. When
  narrowing a CHECK constraint back, first map rows in the removed states to
  a surviving state (see `0005_*.down.sql` for the pattern). If part of an up
  is genuinely irreversible (e.g. a lossy data merge), say so in a comment in
  the down and restore the closest sensible state.
- One concern per migration. Small migrations make branch switching and
  review trivial; `0009` (five concerns in one file) is the anti-pattern.
- Migrations run inside a transaction by default. Statements that can't
  (e.g. `CREATE INDEX CONCURRENTLY`) need the first line of the file to be
  `-- no-transaction`, and then the file must contain **only** such statements.
- Seed data in migrations is for the minimum the code assumes (RBAC seed,
  launch city). Everything else is admin-managed runtime data.

## 3. Everyday development

```bash
backend/scripts/db.sh status    # applied vs pending vs missing
backend/scripts/db.sh check     # drift: stranded ledger rows, edited files
backend/scripts/db.sh reset     # drop + recreate + re-migrate (asks first)
backend/scripts/db.sh revert 2  # run the last 2 down migrations (needs sqlx-cli)
```

`db.sh` reads `DATABASE_URL` from `backend/.env`. `revert`/`reset` migration
runs need sqlx-cli (`brew install sqlx-cli`); everything else needs only psql.

## 4. Switching branches

The database doesn't switch branches with git. The rule of thumb:

- **Target branch has *more* migrations** (e.g. switching back to a feature
  branch, or pulling main): nothing to do — the backend applies the pending
  ones on next start.
- **Target branch has *fewer* migrations** (e.g. leaving a feature branch
  whose migration isn't merged yet): revert your branch-only migrations
  **before** switching, while you still have the files:

  ```bash
  backend/scripts/db.sh revert     # once per branch-only migration
  git switch main
  ```

  Forgot, and the backend now fails with `VersionMissing`? Either switch back
  and revert properly, or `db.sh reset` if you don't care about dev data.
  `db.sh check` tells you exactly which versions are stranded.

Two branches that each add a migration with the same number can't both be
right: whoever merges second renumbers their migration (allowed — it isn't on
`main` yet) and `db.sh reset`s locally.

## 5. Reverting a commit that contained a migration

`git revert` deletes the migration **file** but leaves it applied in every
database that ran it — including yours and production. That's the failure this
repo hit with `0012_three_fixed_roles.sql` (revert `073fb76`): the dev DB kept
version 12 in its ledger and the reverted code expected the pre-12 role names,
so the backend could neither start nor would the data have matched.

Do it in this order instead:

1. **Ship a new migration** that reverses the old one's schema/data changes
   (its `.down.sql` content is usually exactly what you need — copy it into a
   new `NNNN_revert_<name>.up.sql`), **or** for a same-day mistake in dev
   only: run the down against your DB and delete the ledger row
   (`DELETE FROM _sqlx_migrations WHERE version = NN;`).
2. Only then revert/remove the application code.
3. The original migration file stays in the repo forever if any shared or
   production database ever applied it. Roll forward; don't rewrite history.

If a database was already stranded (ledger row without file), repair it the
way step 1's dev variant does: reverse the schema/data by hand in one
transaction, delete the ledger row, and record what you did (this repo writes
an `audit_logs` row — see the 2026-07-08 `ops.migration_ledger_repair` entry).

## 6. Production deployments

- Migrations run automatically at startup (`RUN_MIGRATIONS=true`); the app
  refuses to serve if they fail — a bad migration fails the deploy loudly
  instead of serving against a half-migrated schema.
- **Take a backup/snapshot before any deploy that includes a migration.**
  Backups, not down migrations, are the production rollback story.
- **Never run `sqlx migrate revert` in production.** If a shipped migration
  is wrong, write a new forward migration that corrects it.
- Rolling deploys need **expand → migrate → contract**: old code must work
  against the new schema. Add columns as nullable-or-defaulted first; ship
  code that writes both; remove the old column in a later release. Never
  rename a column in place; add-copy-drop across releases.
- Watch lock behavior on hot tables: `ALTER TABLE … ADD COLUMN` (no volatile
  default) is instant, but constraint additions validate the whole table —
  use `NOT VALID` + `VALIDATE CONSTRAINT`, and `CREATE INDEX CONCURRENTLY`
  (with `-- no-transaction`) on large tables.
- A fresh environment (staging, new region) rebuilds correctly from the full
  migration chain alone — which is why the chain must never be edited.

## 7. What CI enforces

The `Migration guard` job (`backend/scripts/check_migrations.sh`) fails any
push or PR that:

- modifies, deletes, or renames an existing migration (the one allowed rename
  is the legacy `NNNN_x.sql` → `NNNN_x.up.sql` conversion with identical
  content, which preserves the SQLx checksum);
- adds a migration without its `.down.sql` (or vice versa);
- introduces duplicate version numbers or malformed filenames.
