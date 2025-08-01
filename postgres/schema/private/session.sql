-- This table MUST look like this because of `cmd/domonda-graphql/src/session-store.ts`
create table private.session (
  sid varchar primary key,

	sess jsonb not null,
  constraint sess_contains_user_id check(public.is_valid_uuid(sess->>'user_id')),

	expire timestamptz(6) not null,

	updated_at updated_time not null,
	created_at created_time not null
);

create index session_sess_idx on private.session using gin (sess);
create index session_sess_user_id_idx on private.session ((sess->>'user_id'));
create index session_expire_idx on private.session (expire);

----

create function private.session_sync_expire()
returns trigger as $$
begin
	new.sess = jsonb_set(new.sess, '{cookie,expires}', to_jsonb(new.expire));
  return new;
end
$$ language plpgsql volatile security definer;

create trigger private_session_sync_expire_trigger
  before update on private.session
  for each row
  when (old.expire is distinct from new.expire)
  execute procedure private.session_sync_expire();

create function private.session_sync_expire_in_min()
returns trigger as $$
begin
  new.expire = old.updated_at + ((new.sess->>'expire_session_in_min')::int * interval '1 minute');
  new.sess = jsonb_set(new.sess, '{cookie,expires}', to_jsonb(new.expire));
  return new;
end
$$ language plpgsql volatile security definer;

create trigger private_session_sync_expire_in_min_trigger
  before update on private.session
  for each row
  when (old.sess->>'expire_session_in_min' is distinct from new.sess->>'expire_session_in_min')
  execute procedure private.session_sync_expire_in_min();
