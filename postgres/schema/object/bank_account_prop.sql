create table object.bank_account_prop (
    id uuid primary key default uuid_generate_v4(),

    instance_id   uuid not null references object.instance(id) on delete cascade,
    class_prop_id uuid not null references object.class_prop(id) on delete restrict,

    array_index int check(array_index >= 0), -- zero based
    constraint bank_account_prop_unique_array_index unique (instance_id, class_prop_id, array_index),

    iban     public.bank_iban not null,
    bic      public.bank_bic,
    currency public.currency_code,
    holder   public.trimmed_text,

    updated_by trimmed_text not null,
    updated_at timestamptz  not null default now(),
    created_by trimmed_text not null,
    created_at timestamptz  not null default now()
);

grant all on object.bank_account_prop to domonda_user;
grant select on object.bank_account_prop to domonda_wg_user;

create index bank_account_prop_instance_id_idx on object.bank_account_prop (instance_id);
create index bank_account_prop_class_prop_id_idx on object.bank_account_prop (class_prop_id);
create index bank_account_prop_instance_id_class_prop_id_idx on object.bank_account_prop (instance_id, class_prop_id);

----

create function object.bank_account_prop_value(
    prop object.bank_account_prop
) returns json
language sql stable as
$$
    select json_strip_nulls(json_build_object('iban', prop.iban, 'bic', prop.bic, 'currency', prop.currency, 'holder', prop.holder))
$$;

----

create function object.update_bank_account_prop(
    instance_id uuid,
    prop_name   text,
    iban        public.bank_iban = null,
    bic         public.bank_bic = null,
    currency    public.currency_code = null,
    holder      public.trimmed_text = null,
    updated_by  trimmed_text = private.current_user_id()::trimmed_text
) returns object.bank_account_prop
language plpgsql volatile as
$$
declare
    class_prop   object.class_prop;
    command      text;
    updated_prop object.bank_account_prop;
begin
    class_prop := object.get_instance_class_prop_and_check(instance_id, prop_name, 'BANK_ACCOUNT');
    command := object.query_for_update_prop_4values(
        'object.bank_account_prop',
        instance_id,
        class_prop,
        update_bank_account_prop.iban is null,
        'iban',
        'bic',
        'currency',
        'holder'
    );
    execute command
        into updated_prop
        using
            update_bank_account_prop.iban,
            update_bank_account_prop.bic,
            update_bank_account_prop.currency,
            update_bank_account_prop.holder,
            update_bank_account_prop.updated_by;
    return updated_prop;
end
$$;

grant execute on function object.update_bank_account_prop to domonda_user;

----

create function object.update_bank_account_array_prop(
    instance_id uuid,
    prop_name   text,
    ibans       public.bank_iban[] = null, -- defines the array length
    bics        public.bank_bic[] = null,
    currencies  public.currency_code[] = null,
    holders     public.trimmed_text[] = null,
    updated_by  trimmed_text = private.current_user_id()::trimmed_text
) returns setof object.bank_account_prop
language plpgsql volatile as $$
declare
    class_prop object.class_prop;
    array_len  int;
    command    text;
begin
    class_prop := object.get_instance_class_prop_and_check(instance_id, prop_name, 'BANK_ACCOUNT_ARRAY');
    array_len  := coalesce(cardinality(ibans), 0);
    for array_index in 0..array_len-1 loop
        command := object.query_for_update_prop_array_elem('object.bank_account_prop', 'iban');
        execute command using instance_id, class_prop.id, array_index, ibans[array_index+1], updated_by;

        command := object.query_for_update_prop_array_elem('object.bank_account_prop', 'bic');
        execute command using instance_id, class_prop.id, array_index, bics[array_index+1], updated_by;

        command := object.query_for_update_prop_array_elem('object.bank_account_prop', 'currency');
        execute command using instance_id, class_prop.id, array_index, currencies[array_index+1], updated_by;

        command := object.query_for_update_prop_array_elem('object.bank_account_prop', 'holder');
        execute command using instance_id, class_prop.id, array_index, holders[array_index+1], updated_by;
    end loop;
    command := object.query_for_trimmed_prop_array('object.bank_account_prop');
    return query
        execute command using instance_id, class_prop.id, array_len;
end
$$;

grant execute on function object.update_bank_account_array_prop to domonda_user;
