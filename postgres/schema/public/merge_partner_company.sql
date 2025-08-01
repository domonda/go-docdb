create function public.merge_partner_companies(
    destination_partner_company_id uuid,
    source_partner_company_ids     uuid[]
) returns public.partner_company as $$
declare
    destination_partner_company public.partner_company;
    source_partner_company      public.partner_company;
    source_company_location     public.company_location;
begin
    -- ensures the partner company exists and the row is locked
    select
        * into destination_partner_company
    from public.partner_company
    where partner_company.id = destination_partner_company_id
    for update;

    if destination_partner_company is null then
        raise exception 'Partner company % does not exist', merge_partner_companies.destination_partner_company_id;
    end if;

    -- merge partner accounts by the lowest number always
    if 1 < (select count(1) from public.partner_account
        where "type" = 'VENDOR'
            and (partner_company_id = any(source_partner_company_ids)
                or partner_company_id = destination_partner_company_id)
            )
    then
        with lowest_vendor as (
            select id from public.partner_account
            where "type" = 'VENDOR'
                and (partner_company_id = any(source_partner_company_ids)
                    or partner_company_id = destination_partner_company_id
                )
            order by "number" asc
            limit 1
        )
        delete from public.partner_account
        using lowest_vendor
        where partner_account.id <> lowest_vendor.id
            and (partner_company_id = any(source_partner_company_ids)
                or partner_company_id = destination_partner_company_id
            )
            and "type" = 'VENDOR';
    end if;

    if 1 < (select count(1) from public.partner_account
        where "type" = 'CLIENT'
            and (partner_company_id = any(source_partner_company_ids)
                or partner_company_id = destination_partner_company_id
            )
    )
    then
        with lowest_client as (
            select id from public.partner_account
            where "type" = 'CLIENT'
                and (partner_company_id = any(source_partner_company_ids)
                    or partner_company_id = destination_partner_company_id
                )
            order by "number" asc
            limit 1
        )
        delete from public.partner_account
        using lowest_client
        where partner_account.id <> lowest_client.id
            and (partner_company_id = any(source_partner_company_ids)
                or partner_company_id = destination_partner_company_id
            )
            and "type" = 'CLIENT';
    end if;

    update public.partner_account
    set partner_company_id=destination_partner_company_id, updated_at=now()
    where (partner_company_id = any(source_partner_company_ids)
        or partner_company_id = destination_partner_company_id
    );

    -- perform merge of all sources
    for source_partner_company in (select * from public.partner_company where id = any(source_partner_company_ids) for update) loop
        if destination_partner_company.id = source_partner_company.id then
            raise exception 'Cannot merge partners on themselves.';
        end if;
        if destination_partner_company.client_company_id <> source_partner_company.client_company_id then
            raise exception 'Cannot merge partners across different clients.';
        end if;

        -- TODO-db-210714 once we start supporting more than one payment presets,
        -- this part should be refactored to accomodate merging the others
        if exists(select from public.partner_company_payment_preset
            where partner_company_id = destination_partner_company.id
        )
        then
            -- destination has preset, delete other
            delete from public.partner_company_payment_preset
            where partner_company_id = source_partner_company.id;
        else
            -- destination has no preset, copy other over
            update public.partner_company_payment_preset set
                partner_company_id=destination_partner_company.id, updated_at=now()
            where partner_company_id = source_partner_company.id;
        end if;

        -- update all references of the source partner
        update public.invoice set
            partner_company_id=destination_partner_company.id, updated_at=now()
        where partner_company_id = source_partner_company.id;

        update public.delivery_note set
            partner_company_id=destination_partner_company.id, updated_at=now()
        where partner_company_id = source_partner_company.id;

        update public.other_document set
            partner_company_id=destination_partner_company.id, updated_at=now()
        where partner_company_id = source_partner_company.id;

        update public.document_field_value_partner_company set
            "value"=destination_partner_company.id
        where "value" = source_partner_company.id;

        update rule.invoice_partner_company_condition set
            partner_company_id=destination_partner_company.id, updated_at=now()
        where partner_company_id = source_partner_company.id;

        update automation.workflow_trigger_filter_group_document_with_partner set
            partner_company_id=destination_partner_company.id, updated_at=now()
        where partner_company_id = source_partner_company.id;

        update public.bank_transaction set
            partner_company_id=destination_partner_company.id, updated_at=now()
        where partner_company_id = source_partner_company.id;

        update public.credit_card_transaction set
            partner_company_id=destination_partner_company.id, updated_at=now()
        where partner_company_id = source_partner_company.id;

        update public.cash_transaction set
            partner_company_id=destination_partner_company.id, updated_at=now()
        where partner_company_id = source_partner_company.id;

        update public.paypal_transaction set
            partner_company_id=destination_partner_company.id, updated_at=now()
        where partner_company_id = source_partner_company.id;

        update public.stripe_transaction set
            partner_company_id=destination_partner_company.id, updated_at=now()
        where partner_company_id = source_partner_company.id;


        -- unique location columns per partner company have to be set to null if
        -- there is already a location in the destination partner with the same value
        for source_company_location in (select * from public.company_location
            where company_id = source_partner_company.company_id
            or partner_company_id = source_partner_company.id
            for update)
        loop
            if exists (select from public.company_location
                where (company_id = destination_partner_company.company_id
                    or partner_company_id = destination_partner_company.id)
                and registration_no = source_company_location.registration_no)
            then
                update public.company_location set
                    registration_no=null, updated_at=now()
                where id = source_company_location.id;
            end if;

            if exists (select from public.company_location
                where (company_id = destination_partner_company.company_id
                    or partner_company_id = destination_partner_company.id)
                and tax_id_no = source_company_location.tax_id_no)
            then
                update public.company_location set
                    tax_id_no=null, updated_at=now()
                where id = source_company_location.id;
            end if;

            if exists (select from public.company_location
                where (company_id = destination_partner_company.company_id
                    or partner_company_id = destination_partner_company.id)
                and vat_id_no = source_company_location.vat_id_no)
            then
                update public.company_location set
                    vat_id_no=null, updated_at=now()
                where id = source_company_location.id;
            end if;
        end loop;

        if exists (select from public.company_location
            where main and (partner_company_id = source_partner_company.id
                or company_id = source_partner_company.company_id
            )
        )
        then
            update public.company_location set
                main=false, -- the destination already has a main location
                partner_company_id=destination_partner_company.id,
                updated_at=now()
            where partner_company_id = source_partner_company.id;
        else
            update public.company_location set
                -- main is inherited from the source
                partner_company_id=destination_partner_company.id,
                updated_at=now()
            where partner_company_id = source_partner_company.id;
        end if;

        -- copy over all company locations referenced from the general company
        -- to the partner and update the affected invoices
        for source_company_location in (select * from public.company_location where company_id = source_partner_company.company_id for update) loop
            with copied_company_location as (
                insert into public.company_location (
                    partner_company_id,
                    created_by,
                    main,
                    street,
                    city,
                    zip,
                    country,
                    phone,
                    email,
                    website,
                    registration_no,
                    tax_id_no,
                    vat_id_no
                ) values (
                    destination_partner_company.id,
                    source_company_location.created_by,
                    (select
                        case exists (
                                select from public.company_location
                                where main and (company_id = destination_partner_company.company_id
                                    or partner_company_id = destination_partner_company.id
                                )
                            )
                            when true then false -- destination already has main location
                            else source_company_location.main
                        end
                    ), -- main
                    source_company_location.street,
                    source_company_location.city,
                    source_company_location.zip,
                    source_company_location.country,
                    source_company_location.phone,
                    source_company_location.email,
                    source_company_location.website,
                    case when
                        not exists (
                            select from public.company_location
                            where registration_no = source_company_location.registration_no
                                and (company_id = destination_partner_company.company_id
                                    or partner_company_id = destination_partner_company.id
                                )
                        )
                        then source_company_location.registration_no
                        else null
                    end,
                    case when
                        not exists (
                            select from public.company_location
                            where tax_id_no = source_company_location.tax_id_no
                                and (company_id = destination_partner_company.company_id
                                    or partner_company_id = destination_partner_company.id
                                )
                        )
                        then source_company_location.tax_id_no
                        else null
                    end,
                    case when
                        not exists (
                            select from public.company_location
                            where vat_id_no = source_company_location.vat_id_no
                                and (company_id = destination_partner_company.company_id
                                    or partner_company_id = destination_partner_company.id
                                )
                        )
                        then source_company_location.vat_id_no
                        else null
                    end
                )
                returning *
            )
            update public.invoice
            set partner_company_location_id=copied_company_location.id
            from copied_company_location
            where invoice.partner_company_id = destination_partner_company.id -- only merging invoices
                and invoice.partner_company_location_id = source_company_location.id;
        end loop;

        with delete_source_partner_company as (
            delete from public.partner_company where id = source_partner_company.id
            returning 1
        )
        update public.partner_company
        set
            -- assign name only if the destination company is not linked to a global company
            name=(case when destination_partner_company.company_id is null
                then coalesce(partner_company.name, source_partner_company.name)
                else null
            end),
            -- append the source internal name and concat the alternative names from the source
            alternative_names=
                array_cat(
                    -- company
                    coalesce((select
                        case brand_name is null
                            when true then array_cat(array[name], coalesce(alternative_names, '{}'))
                            else array_append(array_cat(array[name], coalesce(alternative_names, '{}')), brand_name)
                        end
                    from public.company
                    where id = source_partner_company.company_id), '{}'),
                    -- partner
                    (case source_partner_company.name is null
                        when true then array_cat(alternative_names, source_partner_company.alternative_names)
                        else array_cat(array_append(alternative_names, source_partner_company.name), source_partner_company.alternative_names)
                    end)
                ),
            source='merged ' || source,
            updated_at=now()
        from delete_source_partner_company -- delete and update in same transaction to avoid constraint clashes
        where partner_company.id = destination_partner_company.id
        returning
            * into destination_partner_company;
    end loop;

    return destination_partner_company;
end
$$ language plpgsql volatile strict;


create function public.fix_own_company_as_partner(
    client_company_id      uuid,
    partner_company_id     uuid,
    merge_partner_location bool = true
) returns public.company_location as $$
declare
    own_main_location       public.company_location;
    problem_partner_company public.partner_company;
    partner_location        public.company_location;
begin
    -- ensures the own company location exists and the row is locked
    select * into own_main_location
    from public.company_location
    where company_location.company_id = fix_own_company_as_partner.client_company_id
        and company_location.main = true
    for update;

    if own_main_location is null then
        raise exception 'Own company % has no main location', fix_own_company_as_partner.client_company_id;
    end if;

    -- ensures the partner company exists and the row is locked
    select * into problem_partner_company
    from public.partner_company
    where partner_company.id = fix_own_company_as_partner.partner_company_id
    for update;

    if problem_partner_company is null then
        raise exception 'Partner company % does not exist', fix_own_company_as_partner.partner_company_id;
    end if;

    -- merge partner location data into own company location
    if merge_partner_location then
        for partner_location in (select * from public.company_location as l where l.partner_company_id = fix_own_company_as_partner.partner_company_id) loop
            update public.company_location
            set
                street=coalesce(l.street, partner_location.street),
                city=coalesce(l.city, partner_location.city),
                zip=coalesce(l.zip, partner_location.zip),
                phone=coalesce(l.phone, partner_location.phone),
                email=coalesce(l.email, partner_location.email),
                website=coalesce(l.website, partner_location.website),
                registration_no=coalesce(l.registration_no, partner_location.registration_no),
                tax_id_no=coalesce(l.tax_id_no, partner_location.tax_id_no),
                vat_id_no=coalesce(l.vat_id_no, partner_location.vat_id_no),
                updated_at=now()
            from public.company_location as l
            where l.id = own_main_location.id;
        end loop;

        select * into own_main_location
        from public.company_location as l
        where l.id = own_main_location.id;
    end if;

    return own_main_location;
end
$$ language plpgsql volatile strict;
