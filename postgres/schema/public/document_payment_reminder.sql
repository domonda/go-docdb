create table public.document_payment_reminder (
  id uuid primary key default uuid_generate_v4(),

  document_id uuid not null references public.document(id) on delete cascade,
  user_id     uuid not null
    default public.unknown_user_id()
    references public.user(id) on delete set default,

  receiver public.email_addr not null,
  subject  non_empty_text not null,
  message  non_empty_text not null,

  cc_me           boolean not null default false,
  attach_document boolean not null default false,

  created_at created_time not null
);

create index document_payment_reminder_document_id_idx on public.document_payment_reminder (document_id);
create index document_payment_reminder_user_id_idx on public.document_payment_reminder (user_id);

grant select, insert, update, delete on public.document_payment_reminder to domonda_user;
grant select on public.document_payment_reminder to domonda_wg_user;

----

create function public.document_latest_payment_reminder(
  document public.document
) returns public.document_payment_reminder as $$
  select * from public.document_payment_reminder
  where document_payment_reminder.document_id = document.id
  order by created_at desc
  limit 1
$$ language sql stable strict;

----

create function public.create_document_payment_reminder(
  document_id     uuid,
  user_id         uuid,
  receiver        public.email_addr,
  subject         non_empty_text,
  message         non_empty_text,
  cc_me           boolean = false,
  attach_document boolean = false
) returns public.document_payment_reminder as $$
  insert into public.document_payment_reminder (
    document_id,
    user_id,
    receiver,
    subject,
    message,
    cc_me,
    attach_document
  ) values (
    create_document_payment_reminder.document_id,
    create_document_payment_reminder.user_id,
    create_document_payment_reminder.receiver,
    create_document_payment_reminder.subject,
    create_document_payment_reminder.message,
    create_document_payment_reminder.cc_me,
    create_document_payment_reminder.attach_document
  )
  returning *
$$ language sql volatile;
