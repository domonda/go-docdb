create function public.add_client_company(
    company_id                           uuid,
    "status"                             public.client_company_status_type,
    email_alias                          public.email_alias,
    accounting_company_client_company_id uuid,
    tax_reclaimable                      boolean,
    vat_declaration                      public.vat_declaration_frequency,
    processing                           public.processing_frequency,
    "language"                           public.language_code = null,
    branding                             public.branding = null,
    billed_client_company_id             uuid = null,
    import_members                       text[] = '{}',
    accounting_email                     public.email_addr = null,
    accounting_system                    public.accounting_system = null,
    accounting_system_client_no          text = NULL,
    contract_start_date                  date = null,
    contract_note                        non_empty_text = null,
    licensed_documents                   int = null,
    licensed_users                       int = null,
    licensed_banks                       int = null,
    contract_expiry_notification_email   public.email_addr = null,
    pain008_payment_id                   trimmed_text = null,
    blacklist_partner_vat_id_nos         text[] = '{}',
    notes                                non_empty_text = null
) returns public.client_company as $$
declare
    added_client_company record;
begin
    -- null -> owner
    -- true -> super-admin
    if private.current_user_super() is not distinct from false then
        raise exception 'Forbidden';
    end if;

    insert into public.client_company (
        company_id,
        email_alias,
        accounting_company_client_company_id,
        tax_reclaimable,
        vat_declaration,
        processing,
        "language",
        branding,
        billed_client_company_id,
        import_members,
        accounting_email,
        accounting_system,
        accounting_system_client_no,
        contract_start_date,
        contract_note,
        licensed_documents,
        licensed_users,
        licensed_banks,
        contract_expiry_notification_email,
        pain008_payment_id,
        blacklist_partner_vat_id_nos,
        notes
    ) values (
         add_client_company.company_id,
         add_client_company.email_alias,
         add_client_company.accounting_company_client_company_id,
         add_client_company.tax_reclaimable,
         add_client_company.vat_declaration,
         add_client_company.processing,
         add_client_company.language,
         add_client_company.branding,
         add_client_company.billed_client_company_id,
         add_client_company.import_members,
         add_client_company.accounting_email,
         add_client_company.accounting_system,
         add_client_company.accounting_system_client_no,
         add_client_company.contract_start_date,
         add_client_company.contract_note,
         add_client_company.licensed_documents,
         add_client_company.licensed_users,
         add_client_company.licensed_banks,
         add_client_company.contract_expiry_notification_email,
         add_client_company.pain008_payment_id,
         add_client_company.blacklist_partner_vat_id_nos,
         add_client_company.notes
    )
    returning * into added_client_company;

    insert into private.client_company_status (
        client_company_id,
        status
    ) values (
        add_client_company.company_id,
        add_client_company.status
    );

    -- note: this makes the authenticated user who is adding the client an admin
    if ((private.current_user_id() is not null) and (not private.current_user_super())) then
        perform private.control_add_client_company_user(
            curr_user.id,
            added_client_company.company_id,
            'ADMIN'
        );
    end if;

    return added_client_company;
end;
$$
language plpgsql volatile security definer;
comment on function public.add_client_company is 'Make an existing `Company` a `ClientCompany`.';

----

create function public.update_client_company(
    company_id                           uuid,
    "status"                             public.client_company_status_type,
    email_alias                          public.email_alias,
    accounting_company_client_company_id uuid,
    tax_reclaimable                      boolean,
    vat_declaration                      public.vat_declaration_frequency,
    processing                           public.processing_frequency,
    "language"                           public.language_code = null,
    branding                             public.branding = null,
    billed_client_company_id             uuid = null,
    import_members                       text[] = '{}',
    accounting_email                     public.email_addr = null,
    accounting_system                    public.accounting_system = null,
    accounting_system_client_no          text = null,
    contract_start_date                  date = null,
    contract_note                        non_empty_text = null,
    licensed_documents                   int = null,
    licensed_users                       int = null,
    licensed_banks                       int = null,
    contract_expiry_notification_email   public.email_addr = null,
    pain008_payment_id                   trimmed_text = null,
    blacklist_partner_vat_id_nos         text[] = '{}',
    notes                                non_empty_text = null
) returns public.client_company as
$$
declare
    updated_client_company record;
begin
    -- null -> owner
    -- true -> super-admin
    if private.current_user_super() is not distinct from false then
        raise exception 'Forbidden';
    end if;

    -- insert only if the client status differs
    if (
        coalesce(
            (
                select update_client_company.status <> public.client_company_status(client_company) from public.client_company
                where client_company.company_id = update_client_company.company_id
            ),
            true -- we coalesce to true to insert the status if it does not exist
        )
    ) then

        insert into private.client_company_status (
            client_company_id,
            status
        ) values (
            update_client_company.company_id,
            update_client_company.status
        );

    end if;

    update public.client_company
    set
        email_alias=update_client_company.email_alias,
        accounting_company_client_company_id=update_client_company.accounting_company_client_company_id,
        tax_reclaimable=update_client_company.tax_reclaimable,
        vat_declaration=update_client_company.vat_declaration,
        processing=update_client_company.processing,
        "language"=update_client_company.language,
        branding=update_client_company.branding,
        billed_client_company_id=update_client_company.billed_client_company_id,
        import_members=update_client_company.import_members,
        accounting_email=update_client_company.accounting_email,
        accounting_system=update_client_company.accounting_system,
        accounting_system_client_no=update_client_company.accounting_system_client_no,
        contract_start_date=update_client_company.contract_start_date,
        contract_note=update_client_company.contract_note,
        licensed_documents=update_client_company.licensed_documents,
        licensed_users=update_client_company.licensed_users,
        licensed_banks=update_client_company.licensed_banks,
        contract_expiry_notification_email=update_client_company.contract_expiry_notification_email,
        pain008_payment_id=update_client_company.pain008_payment_id,
        blacklist_partner_vat_id_nos=update_client_company.blacklist_partner_vat_id_nos,
        notes=update_client_company.notes,
        updated_at=now()
    where client_company.company_id = update_client_company.company_id
    returning * into updated_client_company;

    return updated_client_company;
end
$$
language plpgsql volatile security definer;
comment on function public.update_client_company is 'Update all `ClientCompany` elements. Available to super users only.';
