create type public.booking_type as enum (
    'CASH_BOOK',
    'CLEARING_ACCOUNT'
);

comment on type public.booking_type is 'Non standard booking type if not NULL';


create table public.booking_type_email_alias (
    type          public.booking_type primary key,
    german_alias  public.email_alias not null unique,
    english_alias public.email_alias not null unique,

    created_at created_time not null
);

comment on type public.booking_type_email_alias is 'Maps a booking_type to its email aliases in different languages';

grant select on table public.booking_type_email_alias to domonda_user;
