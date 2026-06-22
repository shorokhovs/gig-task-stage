\echo 'Migrating the latest 3 months in throttled batches'

select set_config('gig_refactor.batch_size', :'batch_size', false);
select set_config('gig_refactor.throttle_seconds', :'throttle_seconds', false);

create table if not exists migration_audit (
  id bigserial primary key,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  source_table text not null,
  destination_table text not null,
  cutoff_at timestamptz not null,
  batch_size integer not null,
  throttle_seconds numeric not null,
  migrated_rows bigint not null default 0,
  status text not null default 'running',
  error_message text
);

do $$
declare
  cutoff_at timestamptz := date_trunc('day', now()) - interval '3 months';
  requested_batch_size integer;
  requested_throttle_seconds numeric;
  inserted_rows integer := 0;
  total_inserted bigint := 0;
  audit_id bigint;
  migration_error text;
begin
  requested_batch_size := current_setting('gig_refactor.batch_size')::integer;
  requested_throttle_seconds := current_setting('gig_refactor.throttle_seconds')::numeric;

  insert into migration_audit (
    source_table,
    destination_table,
    cutoff_at,
    batch_size,
    throttle_seconds
  )
  values (
    'transaction_logs_flat',
    'transaction_logs_modern',
    cutoff_at,
    requested_batch_size,
    requested_throttle_seconds
  )
  returning id into audit_id;

  begin
    truncate table transaction_logs_modern;

    raise notice 'Cleared transaction_logs_modern before migrating from cutoff %', cutoff_at;

    loop
      with next_batch as (
        select flat.id, flat.created_at, flat.brand_id, flat.payload
        from transaction_logs_flat as flat
        where flat.created_at >= cutoff_at
          and not exists (
            select 1
            from transaction_logs_modern as modern
            where modern.id = flat.id
              and modern.created_at = flat.created_at
          )
        order by flat.created_at, flat.id
        limit requested_batch_size
      ),
      inserted as (
        insert into transaction_logs_modern (id, created_at, brand_id, payload)
        select id, created_at, brand_id, payload
        from next_batch
        on conflict (id, created_at) do nothing
        returning id
      )
      select count(1) into inserted_rows from inserted;

      exit when inserted_rows = 0;

      total_inserted := total_inserted + inserted_rows;

      update migration_audit
      set migrated_rows = total_inserted
      where id = audit_id;

      raise notice 'migrated_rows=%, last_batch_rows=%', total_inserted, inserted_rows;

      perform pg_sleep(requested_throttle_seconds);
    end loop;

    update migration_audit
    set
      finished_at = now(),
      migrated_rows = total_inserted,
      status = 'completed'
    where id = audit_id;

  exception when others then
    migration_error := sqlerrm;

    update migration_audit
    set
      finished_at = now(),
      migrated_rows = total_inserted,
      status = 'failed',
      error_message = migration_error
    where id = audit_id;
  end;
end $$;

do $$
declare
  latest_status text;
  latest_error text;
begin
  select status, error_message
  into latest_status, latest_error
  from migration_audit
  order by id desc
  limit 1;

  if latest_status = 'failed' then
    raise exception 'Migration failed: %', latest_error;
  end if;
end $$;
