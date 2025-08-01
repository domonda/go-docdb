create function private.find_real_estate_object(
    client_company_id uuid,
    fulltext          text,
    searchtext        tsvector = null
) returns uuid[]
language plpgsql stable as $$
declare
    instance_ids  uuid[];
    own_addresses text[];
    -- address_variations text[]; -- for debugging
begin
    -- If an object has the same address than the client-company
    -- then it would always be found on every invoice,
    -- so collect own_addresses here to ignore them below:
    select coalesce(array_agg(lower(street)), '{}')
        into own_addresses
    from public.company_location
    where company_id = find_real_estate_object.client_company_id
        and street is not null;

    -- First try exact address match
    select array_agg(instance.id)
        into instance_ids
    from object.instance
        join object.text_prop
            on text_prop.instance_id = instance.id
            and (text_prop.class_prop_id = 'ad9a9051-9df6-4a65-9804-d5c77cc2ec23' -- 'Straßenadresse'
                or text_prop.class_prop_id = '1020a852-326b-4602-ba5f-5abf677f3a7a') -- 'Alternative Straßenadressen'
        join private.gen_address_variations(text_prop.value) as addr
            on not (lower(addr) = any(own_addresses))
    where instance.client_company_id = find_real_estate_object.client_company_id
        and instance.class_name = 'RealEstateObject'
        and instance.disabled_at is null -- only active objects
        -- Ignore Objekttyp KREIS and MANDANT
        and not exists (
            select from object.text_option_prop
            where text_option_prop.instance_id = instance.id
                and text_option_prop.class_prop_id = '0f370879-6d5a-414a-8ce8-539e7b57361e' -- 'Objekttyp'
                and (text_option_prop.option_index = 3 -- index 3 is KREIS in array '{"WEG","HI","SUB","KREIS","MANDANT","MRG"}'
                    or text_option_prop.option_index = 4 -- index 4 is MANDANT in array '{"WEG","HI","SUB","KREIS","MANDANT","MRG"}'
                )
        )
        -- Here is the actual text match:
        -- addr is one of the generated address variations
        and find_real_estate_object.fulltext ilike '%' || addr || '%';
        -- and position(addr in find_real_estate_object.fulltext) > 0;

    if instance_ids is not null and cardinality(instance_ids) > 0 then
        -- Enable for debugging:
        -- raise notice 'Found real estate objects by exact address match: %', instance_ids;
        -- select array_agg(addr)
        --     into address_variations
        -- from object.text_prop
        -- ... insert query from above
        -- raise notice 'Found real estate objects with address variations: %', address_variations;
        return instance_ids;
    end if;

    if searchtext is null then
        return null;
    end if;

    -- Then try tsquery
    select array_agg(instance.id)
        into instance_ids
    from object.instance
        join object.text_prop
            on text_prop.instance_id = instance.id
            and (text_prop.class_prop_id = 'ad9a9051-9df6-4a65-9804-d5c77cc2ec23' -- 'Straßenadresse'
                or text_prop.class_prop_id = '1020a852-326b-4602-ba5f-5abf677f3a7a') -- 'Alternative Straßenadressen'
        join private.gen_address_variations(text_prop.value) as addr
            on not (lower(addr) = any(own_addresses))
    where instance.client_company_id = find_real_estate_object.client_company_id
        and instance.class_name = 'RealEstateObject'
        and instance.disabled_at is null -- only active objects
        and not exists (
            select from object.text_option_prop
            where text_option_prop.instance_id = instance.id
                and text_option_prop.class_prop_id = '0f370879-6d5a-414a-8ce8-539e7b57361e' -- 'Objekttyp'
                and (text_option_prop.option_index = 3 -- index 3 is KREIS in array '{"WEG","HI","SUB","KREIS","MANDANT","MRG"}'
                    or text_option_prop.option_index = 4 -- index 4 is MANDANT in array '{"WEG","HI","SUB","KREIS","MANDANT","MRG"}'
                )
        )
        -- Here is the actual text match:
        and find_real_estate_object.searchtext @@ plainto_tsquery('german', addr);

    return coalesce(instance_ids, '{}');
end
$$;

----

create function private.find_document_real_estate_object(
    document_id uuid
) returns uuid[]
language sql stable strict as $$
    select private.find_real_estate_object(d.client_company_id, d.fulltext, d.searchtext)
    from public.document as d
    where d.id = document_id;
$$;

----

create function private.match_document_real_estate_object(
    document_id uuid,
    created_by  trimmed_text
) returns uuid
language plpgsql volatile strict as $$
declare
    instance_ids uuid[];
begin
    -- Check if already matched
    if exists (select from public.document_real_estate_object as o
        where o.document_id = match_document_real_estate_object.document_id)
    then
        return null;
    end if;

    instance_ids := private.find_document_real_estate_object(document_id);

    if instance_ids is null or cardinality(instance_ids) = 0
    then
        return null;
    end if;

    insert into public.document_real_estate_object (
        document_id,
        object_instance_id,
        updated_by,
        created_by
    ) values (
        document_id,
        instance_ids[1],
        created_by,
        created_by
    );

    return instance_ids[1];
end
$$;
