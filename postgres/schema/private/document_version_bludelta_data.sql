create table private.document_version_bludelta_data (
  document_version_id uuid primary key references docdb.document_version(id) on delete cascade,

  invoice_state            int8,
  is_quality_ok            boolean,

  invoice_no               text,
  invoice_no_score         float8,
  invoice_date             text,
  invoice_date_score       float8,
  currency                 text,
  currency_score           float8,
  total_net_amount         float8,
  total_net_amount_score   float8,
  total_gross_amount       float8,
  total_gross_amount_score float8,
  sender_vat_id            text,
  sender_vat_id_score      float8,
  receiver_vat_id          text,
  receiver_vat_id_score    float8,
  delivery_date            text,
  delivery_date_score      float8,
  sender_name              text,
  sender_name_score        float8,
  receiver_name            text,
  receiver_name_score      float8,

  updated_at updated_time not null,
  created_at created_time not null
);
comment on type private.document_version_bludelta_data is 'BluDelta data for a document version';

grant select on private.document_version_bludelta_data to domonda_user;

----

create function public.document_extracted(doc public.document)
  returns boolean
language sql stable strict as
$$
  -- TODO check other data sources once we have other external extraction services
  select exists (
    select from private.document_version_bludelta_data
      join docdb.document_version on document_version.id = document_version_id
    where document_version.document_id = doc.id
  )
$$;



