create table rule.invoice_cost_unit_condition (
  id uuid primary key default uuid_generate_v4(),

  action_id uuid not null references rule.action(id) on delete cascade,

  client_company_cost_unit_id_equality rule.equality_operator not null,
  client_company_cost_unit_id          uuid references public.client_company_cost_unit(id) on delete cascade,

  created_by uuid not null
    default '08a34dc4-6e9a-4d61-b395-d123005e65d3' -- SYSTEM Unknown
    references public.user(id) on delete set default,
  updated_by uuid references public.user(id) on delete set null,

  updated_at updated_time not null,
  created_at created_time not null
);

grant all on rule.invoice_cost_unit_condition to domonda_user;
grant select on rule.invoice_cost_unit_condition to domonda_wg_user;

----

create function rule.check_invoice_cost_unit_condition_is_used()
returns trigger as $$
declare
  rec rule.invoice_cost_unit_condition;
begin
  if TG_OP = 'DELETE' then
    rec = OLD;
  else
    rec = NEW;
  end if;

  if exists (
    select from rule.action_reaction
    where action_reaction.action_id = rec.action_id
  ) and not rule.current_user_is_special()
  then
    raise exception 'Action is in use';
  end if;

  return rec;
end
$$ language plpgsql stable;

create trigger rule_check_invoice_cost_unit_condition_is_used_trigger
  before insert or update or delete
  on rule.invoice_cost_unit_condition
  for each row
  execute procedure rule.check_invoice_cost_unit_condition_is_used();

----

create function rule.create_invoice_cost_unit_condition (
  action_id                            uuid,
  client_company_cost_unit_id_equality rule.equality_operator,
  client_company_cost_unit_id          uuid = null
) returns rule.invoice_cost_unit_condition as $$
  insert into rule.invoice_cost_unit_condition (action_id, client_company_cost_unit_id_equality, client_company_cost_unit_id, created_by)
    values (create_invoice_cost_unit_condition.action_id, create_invoice_cost_unit_condition.client_company_cost_unit_id_equality, create_invoice_cost_unit_condition.client_company_cost_unit_id, private.current_user_id())
  returning *
$$ language sql volatile;

----

create function rule.update_invoice_cost_unit_condition (
  id                                   uuid,
  client_company_cost_unit_id_equality rule.equality_operator,
  client_company_cost_unit_id          uuid = null
) returns rule.invoice_cost_unit_condition as $$
  update rule.invoice_cost_unit_condition
    set
      client_company_cost_unit_id_equality=update_invoice_cost_unit_condition.client_company_cost_unit_id_equality,
      client_company_cost_unit_id=update_invoice_cost_unit_condition.client_company_cost_unit_id,
      updated_by=private.current_user_id(),
      updated_at=now()
  where id = update_invoice_cost_unit_condition.id
  returning *
$$ language sql volatile;

----

create function rule.delete_invoice_cost_unit_condition (
  id uuid
) returns rule.invoice_cost_unit_condition as $$
  delete from rule.invoice_cost_unit_condition
  where id = delete_invoice_cost_unit_condition.id
  returning *
$$ language sql volatile strict;
