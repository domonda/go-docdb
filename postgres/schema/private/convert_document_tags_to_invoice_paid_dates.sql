create function private.convert_document_tags_to_invoice_paid_dates(
  client_company_id uuid,
  confirmed_by      text,
  prefix            text,
  format            text
) returns setof uuid as
$$
declare
  now timestamptz := now();
  tag record;
begin

  -- take all tags from client company whose name is like: `{prefix}{date in format}`
  for tag in (
    select
      cct.tag as "tag",
      dt.client_company_tag_id as "client_company_tag_id",
      dt.document_id as "document_id",
      to_date(replace(cct.tag, convert_document_tags_to_invoice_paid_dates.prefix, ''), convert_document_tags_to_invoice_paid_dates.format) as "paid_date"
    from public.document_tag as dt
      inner join public.client_company_tag as cct on (dt.client_company_tag_id = cct.id)
    where (
      cct.client_company_id = convert_document_tags_to_invoice_paid_dates.client_company_id
    ) and (
      cct.tag like convert_document_tags_to_invoice_paid_dates.prefix || '%'
    ) and (
      not (cct.tag like '% (applied)')
    )
  ) loop

    -- update the invoice by setting the `paid_date` extracted part of the tag
    update public.invoice
      set
        paid_date=tag.paid_date,
        paid_date_confirmed_by=convert_document_tags_to_invoice_paid_dates.confirmed_by,
        paid_date_confirmed_at=now,
        updated_at=now
    where document_id = tag.document_id;

    -- update the client company tag name
    update public.client_company_tag
      set
        tag=(tag.tag || ' (applied)')
    where id = tag.client_company_tag_id;

    return next tag.document_id;

  end loop;

end
$$
language plpgsql strict;

---- Example for `Pamono GmbH` ----

-- select * from private.convert_document_tags_to_invoice_paid_dates(
--   '91b766ce-a71d-4e43-9f72-d0d5d34d75d5',
--   'DOCUMENT_TAG_TO_PAID_DATE_CONVERTER(DDMMYYYY)',
--   'PD: ',
--   'DDMMYYYY'
-- );
