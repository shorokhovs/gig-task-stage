\echo 'Creating monthly partitioned modern table'

create table if not exists transaction_logs_modern (
  id bigint not null,
  created_at timestamptz not null,
  brand_id integer not null,
  payload jsonb not null,
  migrated_at timestamptz not null default now(),
  primary key (id, created_at)
) partition by range (created_at);

do $$
declare
  partition_start timestamptz := date_trunc('month', now()) - interval '12 months';
  partition_end timestamptz := date_trunc('month', now()) + interval '2 months';
  current_start timestamptz;
  current_end timestamptz;
  partition_name text;
begin
  current_start := partition_start;

  while current_start < partition_end loop
    current_end := current_start + interval '1 month';
    partition_name := 'transaction_logs_modern_' || to_char(current_start, 'YYYY_MM');

    execute format(
      'create table if not exists %I partition of transaction_logs_modern for values from (%L) to (%L)',
      partition_name,
      current_start,
      current_end
    );

    current_start := current_end;
  end loop;
end $$;

create index if not exists idx_transaction_logs_modern_created_at
  on transaction_logs_modern (created_at);

create index if not exists idx_transaction_logs_modern_brand_created_at
  on transaction_logs_modern (brand_id, created_at);
