create view monitor.locks_advisory as (
  select
    objid as "key",           -- the actual key used for the lock
    (not granted) as blocked, -- if the lock is waiting for another lock
    mode,
    pid
  from pg_locks
  where locktype = 'advisory'
);
