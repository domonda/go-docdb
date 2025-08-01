create table automation.special_user(
  user_id uuid primary key references public.user(id) on delete cascade,

  created_at created_time not null
);

grant select on automation.special_user to domonda_user;
grant select on automation.special_user to domonda_wg_user;

----

create function automation.current_user_is_special() returns boolean as $$
  select private.current_user_id() is null or exists (
    select from automation.special_user
    where user_id = private.current_user_id()
  )
$$ language sql stable strict;
comment on function automation.current_user_is_special is '@omit';
