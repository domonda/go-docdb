create view api.delivery_note with (security_barrier) as
    select
        dn.document_id,
        dn.partner_company_id,
        dn.partner_company_id_confirmed_by,
        dn.partner_company_id_confirmed_at,
        dn.partner_company_location_id,
        dn.partner_company_location_id_confirmed_by,
        dn.partner_company_location_id_confirmed_at,
        dn.note_number,
        dn.note_number_confirmed_by,
        dn.note_number_confirmed_at,
        dn.invoice_number,
        dn.invoice_number_confirmed_by,
        dn.invoice_number_confirmed_at,
        dn.issue_date,
        dn.issue_date_confirmed_by,
        dn.issue_date_confirmed_at,
        dn.delivered_at,
        dn.delivered_at_confirmed_by,
        dn.delivered_at_confirmed_at,
        dn.net_sum,
        dn.net_sum_confirmed_by,
        dn.net_sum_confirmed_at,
        dn.updated_at,
        dn.created_at
    from public.delivery_note as dn
        inner join api.document as d on (d.id = dn.document_id);

grant select, update on table api.delivery_note to domonda_api;

comment on view api.delivery_note is $$
@primaryKey document_id
@foreignKey (document_id) references api.document (id)
@foreignKey (partner_company_id) references api.partner_company (id)
@foreignKey (partner_company_location_id) references api.company_location (id)
A `DeliveryNote`.$$;
