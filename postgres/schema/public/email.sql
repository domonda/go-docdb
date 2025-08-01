create type public.email_source as enum (
    'GMAIL_INBOX'
);

comment on type public.email_source is 'Source of the email';

----

create type public.email_status as enum (
    'CREATED',
    'NOT_ALLOWED',
    'NO_ATTACHMENTS',
    'PARTIAL_IMPORT',
    'FULL_IMPORT',
    'NO_COMPANY',
    'INACTIVE'
);

comment on type public.email_status is 'Status of the email';

----

create type public.email_response as enum (
    'NO_RESPONSE',
    'SENDER_NOTIFTY_ERROR',
    'SENDER_NOTIFIED'
);

comment on type public.email_response is 'Response of the email';

----

create table public.email (
    id          text primary key,
    source      public.email_source not null,
    status      public.email_status not null,
    sender      public.email_addr not null,
    receiver    public.email_addr not null,
    subject     text,
    body        text,
    response    public.email_response not null,
    received_at timestamptz not null,
    updated_at  updated_time not null,
    created_at  created_time not null
);

comment on table public.email is 'Recieved E-Mail message';

grant select on table public.email to domonda_user;

----

create function public.document_source_email(
    document public.document
) returns public.email as $$
    select * from public.email
    where document.source = 'GMAIL/inbox@domonda.com'
    -- the source_id for an email import consists of the email id and the attachment index "<id>[<index>]"
    and email.id = split_part(document.source_id, '[', 1)
$$ language sql stable strict;

create function public.document_source_email_sender_is_client(
    document public.document
) returns boolean as $$
    with document_source_email as (
        select sender from public.document_source_email(document)
    )
    select exists (
        select from public.user, document_source_email
        where (
            "user".client_company_id = document.client_company_id
            or "user".id in (select user_id from control.client_company_user where client_company_user.client_company_id = document.client_company_id)
        )
        and "user".email = document_source_email.sender
    ) or exists (
        select from public.company_location, document_source_email
        where company_location.company_id = document.client_company_id
        and (
            company_location.email = document_source_email.sender
            or public.non_email_provider_domain_name(company_location.email) = public.non_email_provider_domain_name(document_source_email.sender)
        )
    )
$$ language sql stable strict;

comment on function public.document_source_email_sender_is_client is '@notNull';

create function public.document_source_email_partner(
    document public.document
) returns public.partner_company as $$
    with document_source_email as (
        select sender from public.document_source_email(document)
    )
    select partner_company.* from public.partner_company
        inner join public.company_location on (
            company_location.company_id = partner_company.company_id
            or company_location.partner_company_id = partner_company.id
        ), document_source_email
    where partner_company.client_company_id = document.client_company_id
    and (
        company_location.email = document_source_email.sender
        or public.non_email_provider_domain_name(company_location.email) = public.non_email_provider_domain_name(document_source_email.sender)
    )
$$ language sql stable strict;

create function public.document_source_email_sender_is_partner(
    document public.document
) returns boolean as $$
    select not (public.document_source_email_partner(document) is null)
$$ language sql stable strict;

comment on function public.document_source_email_sender_is_partner is '@notNull';
