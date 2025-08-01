-- can return:
    -- null: no document checks are present
    -- true: document check passed, perform reaction
    -- false: document check hasent passed, no reaction
create function rule.document_macro_check(
  action rule.action,
  document public.document
) returns boolean as
$$
declare
  -- initially the ok value is true because we and the conditions
  ok boolean := true;
  --
  document_macro_conditions rule.document_macro_condition[];
  condition rule.document_macro_condition;
begin
    -- find document macro conditions
    select array_agg(document_macro_condition) into document_macro_conditions
    from rule.document_macro_condition
    where action_id = action.id;

    -- if there are no conditions, return null
    if coalesce(array_length(document_macro_conditions, 1), 0) = 0
    then
      return null;
    end if;

    -- check document category id conditions
    foreach condition in array document_macro_conditions loop

      case condition.macro
      when 'SIGNA_COMPANY_IS_PRUEFER2_NOTSET'
      then
        ok = ok and not exists (
          select from document_category_object_instance
            inner join object.email_address_prop
            on email_address_prop.instance_id = document_category_object_instance.object_instance_id
          where email_address_prop.class_prop_id = 'ed7fd1ba-5e14-47f9-aabe-b67725b03b4f' -- Prüfer 2
          and document_category_object_instance.document_category_id = document.category_id
        );
      when 'SIGNA_COMPANY_IS_FREIGEBER2_NOTSET'
      then
        ok = ok and not exists (
          select from document_category_object_instance
            inner join object.email_address_prop
            on email_address_prop.instance_id = document_category_object_instance.object_instance_id
          where email_address_prop.class_prop_id = 'a0fa0525-cec6-49c7-a598-1f8be051aec7' -- Freigeber 2
          and document_category_object_instance.document_category_id = document.category_id
        );
      else
        raise exception 'Unrecognized document macro condition "%"', condition.macro;
      end case;

    end loop;

    return ok;
end
$$
language plpgsql stable;
comment on function rule.document_macro_check is '@omit';
