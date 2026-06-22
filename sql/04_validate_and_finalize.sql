\echo 'Validating migrated counts and dropping legacy table'

do $$
declare
  latest_cutoff timestamptz;
  source_rows bigint;
  destination_rows bigint;
begin
  select cutoff_at
  into latest_cutoff
  from migration_audit
  where status = 'completed'
  order by id desc
  limit 1;

  if latest_cutoff is null then
    raise exception 'No completed migration audit row found';
  end if;

  select count(1)
  into source_rows
  from transaction_logs_flat
  where created_at >= latest_cutoff;

  select count(1)
  into destination_rows
  from transaction_logs_modern;

  raise notice 'source_rows=%, destination_rows=%, cutoff_at=%', source_rows, destination_rows, latest_cutoff;

  if source_rows != destination_rows then
    raise exception 'Validation failed: source_rows %, destination_rows %', source_rows, destination_rows;
  end if;

  drop table transaction_logs_flat;
end $$;

select
  status,
  migrated_rows,
  cutoff_at,
  started_at,
  finished_at
from migration_audit
order by id desc
limit 1;
