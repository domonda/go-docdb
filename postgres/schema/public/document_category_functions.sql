create function public.add_document_category(
    client_company_id                          uuid,
    document_type                              public.document_type,
    booking_type                               public.booking_type = null,
    booking_category                           text = null,
    description                                text = null,
    email_alias                                public.email_alias = null,
    ignore_booking_type_paid_assumption        boolean = false,
    general_ledger_account_id                  uuid = null,
    accounting_items_general_ledger_account_id uuid = null,
    accounting_items_title                     trimmed_text = null,
    internal_number_mode                       public.document_category_internal_number_mode = null,
    internal_number_min                        bigint = null,
    custom_extraction_service                  public.extraction_service = null,
    sort_index                                 int = null
) returns public.document_category as
$$
    insert into public.document_category (
        id,
        client_company_id,
        document_type,
        booking_type,
        booking_category,
        description,
        email_alias,
        ignore_booking_type_paid_assumption,
        general_ledger_account_id,
        accounting_items_general_ledger_account_id,
        accounting_items_title,
        internal_number_mode,
        internal_number_min,
        custom_extraction_service,
        sort_index
    ) values (
        uuid_generate_v4(),
        add_document_category.client_company_id,
        add_document_category.document_type,
        add_document_category.booking_type,
        add_document_category.booking_category,
        add_document_category.description,
        add_document_category.email_alias,
        add_document_category.ignore_booking_type_paid_assumption,
        add_document_category.general_ledger_account_id,
        add_document_category.accounting_items_general_ledger_account_id,
        add_document_category.accounting_items_title,
        add_document_category.internal_number_mode,
        add_document_category.internal_number_min,
        add_document_category.custom_extraction_service,
        case when add_document_category.sort_index is null then
            coalesce(
                (
                    select dc.sort_index + 100
                    from public.document_category as dc
                    where dc.client_company_id = add_document_category.client_company_id
                    order by dc.sort_index desc
                    limit 1
                ),
                100
            )
        else
            add_document_category.sort_index
        end -- sort_index
    )
    returning *
$$
language sql volatile;

comment on function public.add_document_category is 'Add a `DocumentCategory`.';

---

create function public.update_document_category(
    row_id                                     uuid, -- TODO this should be id instad of row_id
    document_type                              public.document_type,
    booking_type                               public.booking_type = null,
    booking_category                           text = null,
    description                                text = null,
    email_alias                                public.email_alias = null,
    ignore_booking_type_paid_assumption        boolean = false,
    general_ledger_account_id                  uuid = null,
    accounting_items_general_ledger_account_id uuid = null,
    accounting_items_title                     trimmed_text = null,
    internal_number_mode                       public.document_category_internal_number_mode = null,
    internal_number_min                        bigint = null,
    custom_extraction_service                  public.extraction_service = null,
    sort_index                                 int = null
) returns public.document_category as
$$
    update public.document_category
    set
        document_type=update_document_category.document_type,
        booking_type=update_document_category.booking_type,
        booking_category=update_document_category.booking_category,
        description=update_document_category.description,
        email_alias=update_document_category.email_alias,
        ignore_booking_type_paid_assumption=update_document_category.ignore_booking_type_paid_assumption,
        general_ledger_account_id=update_document_category.general_ledger_account_id,
        accounting_items_general_ledger_account_id=update_document_category.accounting_items_general_ledger_account_id,
        accounting_items_title=update_document_category.accounting_items_title,
        internal_number_mode=update_document_category.internal_number_mode,
        internal_number_min=update_document_category.internal_number_min,
        custom_extraction_service=update_document_category.custom_extraction_service,
        sort_index=coalesce(update_document_category.sort_index, document_category.sort_index),
        updated_at=now()
    where
        id = update_document_category.row_id
    returning *
$$
language sql volatile;

comment on function public.update_document_category is 'Update a `DocumentCategory`.';

----

create function public.delete_document_category(
    row_id uuid
) returns public.document_category as
$$
declare
    deleted record;
begin
    delete from public.document_category where (id = delete_document_category.row_id)
    returning * into deleted;

    if deleted is null then
        raise exception using message = 'deleted row violates row-level security policy';
    end if;

    return deleted;
end;
$$
language plpgsql volatile strict;

comment on function public.delete_document_category is 'Delete a `DocumentCategory`.';

----

create function public.document_category_german_email_addr(
    cat public.document_category
) returns text as
$$
    select dt.german_alias || '+' || coalesce(bt.german_alias || '+', '') || coalesce(cat.email_alias || '+', '') || cc.email_alias || '@domonda.com'
    from public.client_company as cc
        left join public.document_type_email_alias as dt on dt.type=cat.document_type
        left join public.booking_type_email_alias as bt on bt.type=cat.booking_type
    where cc.company_id=cat.client_company_id;
$$
language sql stable;

comment on function public.document_category_german_email_addr(public.document_category) is 'Returns the German inbox email address for the document category or NULL';
grant execute on function public.document_category_german_email_addr(public.document_category) to domonda_user;

----

create function public.document_category_english_email_addr(
    cat public.document_category
) returns text as
$$
    select dt.english_alias || '+' || coalesce(bt.english_alias || '+', '') || coalesce(cat.email_alias || '+', '') || cc.email_alias || '@domonda.com'
    from public.client_company as cc
        left join public.document_type_email_alias as dt on dt.type=cat.document_type
        left join public.booking_type_email_alias as bt on bt.type=cat.booking_type
    where cc.company_id=cat.client_company_id;
$$
language sql stable;

comment on function public.document_category_english_email_addr(public.document_category) is 'Returns the English inbox email address for the document category or NULL';
grant execute on function public.document_category_english_email_addr(public.document_category) to domonda_user;

----


create function public.get_document_category_german_email_addr(
    cat_id uuid
) returns text as
$$
    select dt.german_alias || '+' || coalesce(bt.german_alias || '+', '') || coalesce(cat.email_alias || '+', '') || cc.email_alias || '@domonda.com'
    from public.document_category as cat
        left join public.client_company as cc on cc.company_id=cat.client_company_id
        left join public.document_type_email_alias as dt on dt.type=cat.document_type
        left join public.booking_type_email_alias as bt on bt.type=cat.booking_type
    where cat.id = cat_id;
$$
language sql stable;

comment on function public.get_document_category_german_email_addr(uuid) is 'Returns the German inbox email address for the document category or NULL';
grant execute on function public.get_document_category_german_email_addr(uuid) to domonda_user;

----

create function public.get_document_category_english_email_addr(
    cat_id uuid
) returns text as
$$
    select dt.english_alias || '+' || coalesce(bt.english_alias || '+', '') || coalesce(cat.email_alias || '+', '') || cc.email_alias || '@domonda.com'
    from public.document_category as cat
        left join public.client_company as cc on cc.company_id=cat.client_company_id
        left join public.document_type_email_alias as dt on dt.type=cat.document_type
        left join public.booking_type_email_alias as bt on bt.type=cat.booking_type
    where cat.id = cat_id;
$$
language sql stable;

comment on function public.get_document_category_english_email_addr(uuid) is 'Returns the English inbox email address for the document category or NULL';
grant execute on function public.get_document_category_english_email_addr(uuid) to domonda_user;

----

create function public.client_company_sorted_document_categories_by_client_company_id(
    cc public.client_company
) returns setof public.document_category as
$$
    select * from public.document_category
    where (
        client_company_id = cc.company_id
    ) and (
        -- hide all document categories where the type ends with file (means document has no pages)
        document_type::text not like '%_FILE'
    )
    order by sort_index, booking_category desc
$$
language sql stable;

comment on function public.client_company_sorted_document_categories_by_client_company_id is 'Returns sorted `DocumentCategories` for the given `ClientCompany`.';

----

create function public.sorted_document_categories_by_client_company_id(
    client_company_id uuid
) returns setof public.document_category as
$$
    select * from public.document_category
    where (
        client_company_id = sorted_document_categories_by_client_company_id.client_company_id
    ) and (
        -- hide all document categories where the type ends with file (means document has no pages)
        document_type::text not like '%_FILE'
    )
    order by sort_index, booking_category desc
$$
language sql stable;

comment on function public.sorted_document_categories_by_client_company_id is 'Returns sorted `DocumentCategories` for the `ClientCompany` with the given id.';
