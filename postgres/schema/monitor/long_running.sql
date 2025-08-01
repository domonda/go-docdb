create view monitor.long_running as (
  select
    pid,
    state,
    pg_stat_activity.query_start as started_at,
    now() - pg_stat_activity.query_start as running,
    query
  from pg_stat_activity
  where (now() - query_start) > interval '10 seconds'
  and state != 'idle'
  order by query_start asc
);
