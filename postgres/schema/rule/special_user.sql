create table rule.special_user(
  user_id uuid primary key references public.user(id) on delete cascade,

  created_at created_time not null
);

grant select on rule.special_user to domonda_user;
grant select on rule.special_user to domonda_wg_user;

----

create function rule.current_user_is_special() returns boolean as $$
  select private.current_user_id() is null or exists (
    select from rule.special_user
    where user_id = private.current_user_id()
  )
$$ language sql stable strict;
comment on function rule.current_user_is_special is '@omit';
