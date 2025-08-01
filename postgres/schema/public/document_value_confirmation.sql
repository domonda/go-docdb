-- Not used right now

-- create table public.document_value_confirmation (
--     id uuid primary key default uuid_generate_v4(),

--     document_id  uuid not null references public.document(id) on delete cascade,
--     value_name   text not null check(length(value_name) > 0),
--     confirmed_by uuid not null
--         default '08a34dc4-6e9a-4d61-b395-d123005e65d3' -- system-user ID for unknown user
--         references public.user(id) on delete set default,
--     confirmed_at timestamptz not null default now(),
--     confidence   float8
-- );

-- grant select, insert, update on table public.document_value_confirmation to domonda_user;

-- create index document_value_confirmation_document_id_value_name_idx on public.document_value_confirmation(document_id, value_name);

-- comment on type public.document_value_confirmation is 'Confirmations of named document values';