create function object.clone_instance_to_client_company(
    src_instance           object.instance,
    dest_client_company_id uuid,
    created_by             trimmed_text = 'CLONING'
) returns object.instance
language plpgsql volatile strict as
$$
declare
    dest_instance object.instance;
begin
    if src_instance.client_company_id = dest_client_company_id
    then
        raise exception 'can''t clone to same client company %', dest_client_company_id;
    end if;

    insert into object.instance (client_company_id, class_name, created_by)
    values (dest_client_company_id, src_instance.class_name, clone_instance_to_client_company.created_by)
    returning * into dest_instance;

    insert into object.text_prop (
        instance_id,
        class_prop_id,
        array_index,
        value,
        updated_by,
        created_by)
    select
        dest_instance.id,
        src.class_prop_id,
        src.array_index,
        src.value,
        clone_instance_to_client_company.created_by,
        clone_instance_to_client_company.created_by
    from object.text_prop as src
    where src.instance_id = src_instance.id;

    insert into object.text_option_prop (
        instance_id,
        class_prop_id,
        array_index,
        option_index,
        updated_by,
        created_by)
    select
        dest_instance.id,
        src.class_prop_id,
        src.array_index,
        src.option_index,
        clone_instance_to_client_company.created_by,
        clone_instance_to_client_company.created_by
    from object.text_option_prop as src
    where src.instance_id = src_instance.id;

    insert into object.number_prop (
        instance_id,
        class_prop_id,
        array_index,
        value,
        updated_by,
        created_by)
    select
        dest_instance.id,
        src.class_prop_id,
        src.array_index,
        src.value,
        clone_instance_to_client_company.created_by,
        clone_instance_to_client_company.created_by
    from object.number_prop as src
    where src.instance_id = src_instance.id;

    insert into object.integer_prop (
        instance_id,
        class_prop_id,
        array_index,
        value,
        updated_by,
        created_by)
    select
        dest_instance.id,
        src.class_prop_id,
        src.array_index,
        src.value,
        clone_instance_to_client_company.created_by,
        clone_instance_to_client_company.created_by
    from object.integer_prop as src
    where src.instance_id = src_instance.id;

    insert into object.boolean_prop (
        instance_id,
        class_prop_id,
        array_index,
        value,
        updated_by,
        created_by)
    select
        dest_instance.id,
        src.class_prop_id,
        src.array_index,
        src.value,
        clone_instance_to_client_company.created_by,
        clone_instance_to_client_company.created_by
    from object.boolean_prop as src
    where src.instance_id = src_instance.id;

    insert into object.date_prop (
        instance_id,
        class_prop_id,
        array_index,
        value,
        updated_by,
        created_by)
    select
        dest_instance.id,
        src.class_prop_id,
        src.array_index,
        src.value,
        clone_instance_to_client_company.created_by,
        clone_instance_to_client_company.created_by
    from object.date_prop as src
    where src.instance_id = src_instance.id;

    insert into object.date_time_prop (
        instance_id,
        class_prop_id,
        array_index,
        value,
        updated_by,
        created_by)
    select
        dest_instance.id,
        src.class_prop_id,
        src.array_index,
        src.value,
        clone_instance_to_client_company.created_by,
        clone_instance_to_client_company.created_by
    from object.date_time_prop as src
    where src.instance_id = src_instance.id;

    insert into object.iban_prop (
        instance_id,
        class_prop_id,
        array_index,
        value,
        updated_by,
        created_by)
    select
        dest_instance.id,
        src.class_prop_id,
        src.array_index,
        src.value,
        clone_instance_to_client_company.created_by,
        clone_instance_to_client_company.created_by
    from object.iban_prop as src
    where src.instance_id = src_instance.id;

    insert into object.bic_prop (
        instance_id,
        class_prop_id,
        array_index,
        value,
        updated_by,
        created_by)
    select
        dest_instance.id,
        src.class_prop_id,
        src.array_index,
        src.value,
        clone_instance_to_client_company.created_by,
        clone_instance_to_client_company.created_by
    from object.bic_prop as src
    where src.instance_id = src_instance.id;

    insert into object.vat_id_prop (
        instance_id,
        class_prop_id,
        array_index,
        value,
        updated_by,
        created_by)
    select
        dest_instance.id,
        src.class_prop_id,
        src.array_index,
        src.value,
        clone_instance_to_client_company.created_by,
        clone_instance_to_client_company.created_by
    from object.vat_id_prop as src
    where src.instance_id = src_instance.id;

    insert into object.country_prop (
        instance_id,
        class_prop_id,
        array_index,
        value,
        updated_by,
        created_by)
    select
        dest_instance.id,
        src.class_prop_id,
        src.array_index,
        src.value,
        clone_instance_to_client_company.created_by,
        clone_instance_to_client_company.created_by
    from object.country_prop as src
    where src.instance_id = src_instance.id;

    insert into object.currency_prop (
        instance_id,
        class_prop_id,
        array_index,
        value,
        updated_by,
        created_by)
    select
        dest_instance.id,
        src.class_prop_id,
        src.array_index,
        src.value,
        clone_instance_to_client_company.created_by,
        clone_instance_to_client_company.created_by
    from object.currency_prop as src
    where src.instance_id = src_instance.id;

    insert into object.currency_amount_prop (
        instance_id,
        class_prop_id,
        array_index,
        value,
        updated_by,
        created_by)
    select
        dest_instance.id,
        src.class_prop_id,
        src.array_index,
        src.value,
        clone_instance_to_client_company.created_by,
        clone_instance_to_client_company.created_by
    from object.currency_amount_prop as src
    where src.instance_id = src_instance.id;

    insert into object.email_address_prop (
        instance_id,
        class_prop_id,
        array_index,
        value,
        updated_by,
        created_by)
    select
        dest_instance.id,
        src.class_prop_id,
        src.array_index,
        src.value,
        clone_instance_to_client_company.created_by,
        clone_instance_to_client_company.created_by
    from object.email_address_prop as src
    where src.instance_id = src_instance.id;

    insert into object.user_prop (
        instance_id,
        class_prop_id,
        array_index,
        value,
        updated_by,
        created_by)
    select
        dest_instance.id,
        src.class_prop_id,
        src.array_index,
        src.value,
        clone_instance_to_client_company.created_by,
        clone_instance_to_client_company.created_by
    from object.user_prop as src
    where src.instance_id = src_instance.id;

    return dest_instance;
end
$$;

create function object.clone_class_instances_to_client_company(
    class_name             trimmed_text,
    src_client_company_id  uuid,
    dest_client_company_id uuid,
    created_by             trimmed_text = 'CLONING'
) returns setof object.instance
language sql volatile strict as
$$
    select object.clone_instance_to_client_company(
        instance,
        clone_class_instances_to_client_company.dest_client_company_id,
        clone_class_instances_to_client_company.created_by
    )
    from object.instance
    where instance.client_company_id = clone_class_instances_to_client_company.src_client_company_id
        and instance.class_name      = clone_class_instances_to_client_company.class_name
$$;

