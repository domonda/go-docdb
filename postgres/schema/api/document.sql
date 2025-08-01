CREATE VIEW api.document WITH (security_barrier) AS
    SELECT
        d.id,
        d.title,
        d.category_id,
        d.client_company_id,
        d.base_document_id,
        d.name,
        d.language,
        d.version,
        d.num_pages,
        d.num_attach_pages,
        d.workflow_step_id,
        d.imported_by,
        d.import_date AS imported_at,
        d.rearranged_at,
        d.rearranged_by,
        d.pages_confirmed_at,
        d.pages_confirmed_by,
        d.checkout_user_id,
        d.checkout_reason,
        d.checkout_time,
        d.updated_at,
        d.created_at,
        (
            SELECT array_agg(cct.name order by cct.name)
            FROM public.document_tag AS dt
                INNER JOIN api.client_company_tag AS cct ON (cct.id = dt.client_company_tag_id)
            WHERE dt.document_id = d.id
        ) as tags
    FROM public.document AS d
        INNER JOIN api.document_category AS dc ON (dc.id = d.category_id)
    WHERE (
        NOT d.superseded
    );

GRANT SELECT, UPDATE ON TABLE api.document TO domonda_api;

COMMENT ON COLUMN api.document.category_id IS '@notNull';
COMMENT ON COLUMN api.document.client_company_id IS '@notNull';
COMMENT ON COLUMN api.document.name IS '@notNull';
COMMENT ON COLUMN api.document.language IS '@notNull';
COMMENT ON COLUMN api.document.num_pages IS '@notNull';
COMMENT ON COLUMN api.document.num_attach_pages IS '@notNull';
COMMENT ON COLUMN api.document.imported_at IS '@notNull';
COMMENT ON VIEW api.document IS $$
@primaryKey id
@foreignKey (category_id) references api.document_category (id)
@foreignKey (client_company_id) references api.client_company (company_id)
@foreignKey (base_document_id) references api.document (id)
@foreignKey (workflow_step_id) references api.document_workflow_step (id)
@foreignKey (imported_by) references api.user (id)
@foreignKey (rearranged_by) references api.user (id)
@foreignKey (pages_confirmed_by) references api.user (id)
@foreignKey (checkout_user_id) references api.user (id)
A `Document` which can be any form of document (invoice, delivery note, statement, etc.).$$;

----

create function api.document_payment_status(document api.document)
returns public.document_payment_status as
$$
    select public.document_payment_status(pub_doc)
    from public.document as pub_doc
    where pub_doc.id = document.id
$$
language sql stable strict security definer; -- is ok because the user has to get the document first

comment on function api.document_payment_status is
E'@notNull\nThe `Document`''s payment status taking into account `Invoice` details and matched `MoneyTransaction`s.';


create function api.document_derived_title(document api.document)
returns text as
$$
    select public.document_derived_title(pub_doc)
    from public.document as pub_doc
    where pub_doc.id = document.id
$$
language sql stable security definer; -- is ok because the user has to get the document first
comment on function api.document_derived_title is E'@notNull\nTitle of the `Document` properly derived from its data.';


create function api.document_type(doc api.document)
returns public.document_type as
$$
    select document_type
    from api.document_category
    where id = doc.category_id
$$
language sql stable security definer; -- is ok because the user has to get the document first
comment on function api.document_type is E'@notNull\nType of the `Document`.';


create function api.document_is_recurring(doc api.document)
returns boolean as
$$
    select public.document_has_active_recurrence(pub_doc)
    from public.document as pub_doc
    where pub_doc.id = doc.id
$$
language sql stable security definer; -- is ok because the user has to get the document first
comment on function api.document_is_recurring is E'@notNull\nIndicates if the `Document` is recurring.';


-- create function api.document_real_estate_object_number(doc api.document)
-- returns text as
-- $$
--     select object.get_text_prop_value(o.object_instance_id, 'Objektnummer')
--     from public.document_real_estate_object as o
--     where o.document_id = doc.id
-- $$
-- language sql stable security definer; -- is ok because the user has to get the document first

-- comment on function api.document_real_estate_object_number is E'Number of the real estate object connected with the `Document`.';


----

CREATE FUNCTION api.filter_open_items(
    -- core
    search_text       text = NULL,
    open_items_type   public.open_items_type = NULL,
    order_by          public.filter_open_items_order_by = NULL,
    -- category
    document_category_ids uuid[] = NULL,
    -- partner
    partner_company_ids uuid[] = NULL,
    -- amount
    min_total float8 = NULL,
    max_total float8 = NULL,
    -- date
    date_filter_type public.filter_documents_date_filter_type = NULL,
    from_date        date = NULL,
    until_date       date = NULL,
    -- tags
    tag_ids uuid[] = NULL,
    -- cost centers
    cost_center_ids uuid[] = NULL,
    -- workflows
    workflow_ids      uuid[] = NULL,
    workflow_step_ids uuid[] = NULL,
    -- pain001
    has_pain001_payment boolean = NULL
) RETURNS SETOF api.document AS
$$
    SELECT
        d.id,
        d.title,
        d.category_id,
        d.client_company_id,
        d.base_document_id,
        d.name,
        d.language,
        d.version,
        d.num_pages,
        d.num_attach_pages,
        d.workflow_step_id,
        d.imported_by,
        d.import_date AS imported_at,
        d.rearranged_at,
        d.rearranged_by,
        d.pages_confirmed_at,
        d.pages_confirmed_by,
        d.checkout_user_id,
        d.checkout_reason,
        d.checkout_time,
        d.updated_at,
        d.created_at,
        (
            SELECT array_agg(cct.name order by cct.name)
            FROM public.document_tag AS dt
                INNER JOIN api.client_company_tag AS cct ON (cct.id = dt.client_company_tag_id)
            WHERE dt.document_id = d.id
        ) as tags
    FROM private.filter_open_items(
        (SELECT api.current_client_company_id()),
        filter_open_items.search_text,
        filter_open_items.open_items_type,
        filter_open_items.order_by,
        filter_open_items.document_category_ids,
        filter_open_items.partner_company_ids,
        filter_open_items.min_total,
        filter_open_items.max_total,
        filter_open_items.date_filter_type,
        filter_open_items.from_date,
        filter_open_items.until_date,
        filter_open_items.tag_ids,
        filter_open_items.cost_center_ids,
        filter_open_items.workflow_ids,
        filter_open_items.workflow_step_ids,
        filter_open_items.has_pain001_payment
    ) as d
$$
LANGUAGE SQL STABLE SECURITY DEFINER;

COMMENT ON FUNCTION api.filter_open_items IS E'@deprecated Consider using `Query.filterDocuments` instead.\nFilter `Document`s which are open.';

----

CREATE FUNCTION api.filter_open_items_statistics(
    -- core
    search_text       text = NULL,
    open_items_type   public.open_items_type = NULL,
    order_by          public.filter_open_items_order_by = NULL,
    -- category
    document_category_ids uuid[] = NULL,
    -- partner
    partner_company_ids uuid[] = NULL,
    -- amount
    min_total float8 = NULL,
    max_total float8 = NULL,
    -- date
    date_filter_type public.filter_documents_date_filter_type = NULL,
    from_date        date = NULL,
    until_date       date = NULL,
    -- tags
    tag_ids uuid[] = NULL,
    -- cost centers
    cost_center_ids uuid[] = NULL,
    -- workflows
    workflow_ids      uuid[] = NULL,
    workflow_step_ids uuid[] = NULL,
    -- pain001
    has_pain001_payment boolean = NULL
) RETURNS public.open_items_statistics AS
$$
    SELECT * FROM public.filter_open_items_statistics(
        (SELECT api.current_client_company_id()),
        search_text,
        open_items_type,
        order_by,
        document_category_ids,
        partner_company_ids,
        min_total,
        max_total,
        date_filter_type,
        from_date,
        until_date,
        tag_ids,
        cost_center_ids,
        workflow_ids,
        workflow_step_ids,
        has_pain001_payment
    )
$$
LANGUAGE SQL STABLE SECURITY DEFINER;

COMMENT ON FUNCTION api.filter_open_items_statistics IS E'@notNull\nStatistics regarding the filtered `Documents` which are open.';

----

create view api.deleted_document with (security_barrier) as
    select
        d.id,
        d.title,
        d.category_id,
        d.client_company_id,
        d.base_document_id,
        d.name,
        d.language,
        d.version,
        d.num_pages,
        d.num_attach_pages,
        d.imported_by,
        d.import_date as imported_at,
        d.updated_at,
        d.created_at
    from public.document as d
        inner join api.document_category as dc on (dc.id = d.category_id)
    where d.superseded;

grant select on table api.deleted_document to domonda_api;

comment on column api.deleted_document.category_id is '@notNull';
comment on column api.deleted_document.client_company_id is '@notNull';
comment on column api.deleted_document.name is '@notNull';
comment on column api.deleted_document.language is '@notNull';
comment on column api.deleted_document.num_pages is '@notNull';
comment on column api.deleted_document.num_attach_pages is '@notNull';
comment on column api.deleted_document.imported_at is '@notNull';
COMMENT ON VIEW api.deleted_document is $$
@primaryKey id
@foreignKey (category_id) references api.document_category (id)
@foreignKey (client_company_id) references api.client_company (company_id)
@foreignKey (base_document_id) references api.document (id)
@foreignKey (imported_by) references api.user (id)
A `DeletedDocument` is marked as deleted but can be restored.$$;

----

create function api.document_extracted(doc api.document)
  returns boolean
language sql stable strict security definer as
$$
    select public.document_extracted(document)
    from public.document
    where document.id = doc.id
$$;
comment on function api.document_extracted is E'@notNull\nIndicates if the `Document` has been extracted.';