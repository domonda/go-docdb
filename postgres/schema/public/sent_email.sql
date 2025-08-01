create table public.sent_email (
    id uuid primary key default uuid_generate_v4(),

    message_id text not null check(length(trim(message_id)) > 0), -- RFC 822 Message-ID header
    gmail_id   text not null check(length(trim(gmail_id)) > 0),   -- Gmail API internal ID
    sender     text not null,   -- TODO user public.email_addr when its regex can handle + addresses
    recipients text[] not null, -- TODO user public.email_addr when its regex can handle + addresses
    reason     text check(length(trim(reason)) > 0),

    in_reply_to_message_id text check(length(trim(in_reply_to_message_id)) > 0),
    in_reply_to_gmail_id   text check(length(trim(in_reply_to_gmail_id)) > 0),
    check((in_reply_to_message_id is null) = (in_reply_to_gmail_id is null)),

    sent_at timestamptz not null default now()
);

create unique index sent_email_message_id_unique on public.sent_email(message_id);
create unique index sent_email_gmail_id_unique   on public.sent_email(gmail_id);