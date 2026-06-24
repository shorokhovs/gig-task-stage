# GIG Database Refactor Lab

Hands-on implementation for the Database Architect take-home assignment.

The lab uses PostgreSQL 16, Docker Compose, and Ansible to demonstrate an
idempotent database setup, synthetic legacy data generation, native monthly
partitioning, throttled batch migration, validation, and final archive cleanup.

## Prerequisites

- Docker with Docker Compose v2
- Ansible

I have used Colima instead of Docker Desktop due to corporate restrictions.

```bash
brew install colima
colima start --cpu 4 --memory 6 --disk 40
docker context use colima
```

## Run

```bash
ansible-playbook playbooks/site.yml
```

PostgreSQL is exposed on a non-default local port:

```text
host: 127.0.0.1
port: 55432
database: GIG_REFACTOR_LAB
admin user: gig_admin
```

The playbook performs the full lab flow:

1. Starts PostgreSQL 16.
2. Creates the `GIG_REFACTOR_LAB` database and `gig_admin` role.
3. Creates `transaction_logs_flat`.
4. Populates 1,000,000 randomized rows across the last 12 months.
5. Creates `transaction_logs_modern`, partitioned monthly by `created_at`.
6. Migrates only the latest 3 months in throttled batches.
7. Validates source and destination row counts.
8. Drops `transaction_logs_flat` to simulate archive/purge completion.

## Batching Strategy

The migration uses `sql/03_batch_migration.sql`.

- Scope: rows where `created_at >= date_trunc('day', now()) - interval '3 months'`.
- Batch size: `25,000` rows by default.
- Ordering: `created_at, id` for stable incremental movement.
- Throttling: `pg_sleep(0.2)` between batches by default.
- Audit trail: each run writes to `migration_audit`.
- Repeatability: the destination rows for the current 3-month window are cleared
  before a new migration run, so the demo can be rerun cleanly.

The default values are in `group_vars/all.yml`:

```yaml
target_row_count: 1000000
migration_batch_size: 25000
migration_throttle_seconds: 0.2
```

## Useful Commands

Connect with `psql`:

```bash
docker compose -p gig_refactor_lab exec postgres psql -U postgres -d GIG_REFACTOR_LAB
```

Inspect partitions:

```sql
SELECT inhrelid::regclass AS partition
FROM pg_inherits
WHERE inhparent = 'transaction_logs_modern'::regclass
ORDER BY 1;
```

Inspect the latest migration audit:

```sql
SELECT *
FROM migration_audit
ORDER BY id DESC
LIMIT 1;
```

Stop the lab:

```bash
docker compose -p gig_refactor_lab down
```

Remove all generated database data:

```bash
docker compose -p gig_refactor_lab down -v
```

## Assignment Notes

The theoretical proposal for Parts 1-3 is in
`docs/technical_proposal.md`.
