\echo 'Creating legacy flat table and loading synthetic data'

select set_config('gig_refactor.target_row_count', :'target_row_count', false);

create table if not exists transaction_logs_flat (
  id bigserial primary key,
  created_at timestamptz not null,
  brand_id integer not null,
  payload jsonb not null
);

do $$
declare
  existing_rows bigint;
  requested_rows bigint;
begin
  requested_rows := current_setting('gig_refactor.target_row_count')::bigint;

  select count(*) into existing_rows from transaction_logs_flat;

  if existing_rows <> requested_rows then
    raise notice 'Reloading transaction_logs_flat: existing %, requested %', existing_rows, requested_rows;

    truncate table transaction_logs_flat restart identity;

    insert into transaction_logs_flat (created_at, brand_id, payload)
    select
      now() - (random() * interval '365 days') as created_at,
      (1 + floor(random() * 20))::integer as brand_id,
      jsonb_build_object(
        'transaction_id', md5(series_id::text || clock_timestamp()::text || random()::text),
        'amount', round((random() * 500)::numeric, 2),
        'currency', (array['EUR', 'USD', 'GBP', 'PLN'])[1 + floor(random() * 4)::integer],
        'status', (array['accepted', 'declined', 'pending'])[1 + floor(random() * 3)::integer],
        'source', 'legacy-flat'
      ) as payload
    from generate_series(1, requested_rows) as series_id;
  else
    raise notice 'transaction_logs_flat already contains % rows; skipping reload', existing_rows;
  end if;
end $$;

create index if not exists idx_transaction_logs_flat_created_at
  on transaction_logs_flat (created_at);

create index if not exists idx_transaction_logs_flat_brand_created_at
  on transaction_logs_flat (brand_id, created_at);

analyze transaction_logs_flat;
