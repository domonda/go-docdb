create type public.document_recurrence_interval as enum (
	'MONTHLY',
    'BIMONTHLY', -- every 2 months
	'QUARTERLY',
    'HALF_YEARLY', -- every 6 months
	'YEARLY'
);

create table public.document_recurrence (
    id uuid primary key default uuid_generate_v4(),

    document_id uuid not null references public.document(id) on delete restrict,

    starts_at       date not null,
    interval        public.document_recurrence_interval not null,
    max_recurrences integer           check(max_recurrences > 0),
    ends_at         date              check(ends_at > starts_at),
    constraint max_recurrences_or_ends_at check(
        ((max_recurrences is null) and (ends_at is null))
        or
        ((max_recurrences is null) <> (ends_at is null))
    ),

    number_regex    text check(length(trim(number_regex)) > 0),
    number_template text check(length(trim(number_template)) > 0),

    -- even if recurrence has an `ends_at`, the document _was_ recurring and therefore
    -- cannot be used for an active status check (we want the info that it was recurring
    -- but not anymore). disabled_at should be used for active status instead
    disabled_at timestamptz,
    disabled_by uuid references public.user(id) on delete restrict, -- TODO: set Unknown user
    constraint disabled_at_and_by check((disabled_at is null) = (disabled_by is null)),

    created_by uuid not null
        default '08a34dc4-6e9a-4d61-b395-d123005e65d3' -- Unknown
        references public.user(id) on delete set default,
    created_at created_time not null
);

grant select, insert, update on table public.document_recurrence to domonda_user;
grant select on table public.document_recurrence to domonda_wg_user;
comment on type public.document_recurrence is 'Information about how a base document should be recurring';

create index document_recurrence_document_id_starts_at_idx
    on public.document_recurrence (document_id, starts_at);

create index document_recurrence_disabled_at_idx
    on public.document_recurrence (disabled_at);

create unique index document_recurrence_only_one_active
    on public.document_recurrence (document_id)
    where disabled_at is null;

----

create table public.document_recurrence_document (
    recurrence_id uuid not null references public.document_recurrence(id) on delete restrict,
    document_id   uuid not null references public.document(id)            on delete cascade,
    primary key(recurrence_id, document_id),

    created_at created_time not null
);

grant select on table public.document_recurrence_document to domonda_user;
grant select on table public.document_recurrence_document to domonda_wg_user;

create index document_recurrence_document_recurrence_id_idx on public.document_recurrence_document (recurrence_id);
create index document_recurrence_document_document_id_idx on public.document_recurrence_document (document_id);

----

create function public.document_recurrence_documents(
    document_recurrence public.document_recurrence
) returns setof public.document as $$
    select *
    from public.document
    where exists(
        select from public.document_recurrence_document as drd
        where drd.recurrence_id = document_recurrence_documents.document_recurrence.id
            and drd.document_id = document.id
    )
    order by created_at
$$ language sql stable strict;

----

create function public.document_recurrence_disabled(
    document_recurrence public.document_recurrence
) returns boolean as $$
    select document_recurrence.disabled_at is not null
$$ language sql immutable strict;
comment on function public.document_recurrence_disabled is '@notNull';

create function public.disable_active_document_recurrences(
    document_id uuid
) returns public.document as $$
declare
    disabled_document public.document;
begin
    update public.document_recurrence
        set
            disabled_at=now(), -- TODO: is now() the right end time?
            disabled_by=private.current_user_id()
    where document_recurrence.document_id = disable_active_document_recurrences.document_id
    and disabled_at is null;

    select * into disabled_document
    from public.document
    where document.id = disable_active_document_recurrences.document_id;

    return disabled_document;
end
$$ language plpgsql volatile strict;

----

create function public.next_recurrence_interval_date(
    base_date           date,
    recurrence_interval public.document_recurrence_interval
) returns date as $$
    select case recurrence_interval
        when 'MONTHLY'     then (base_date + interval '1 month')::date
        when 'BIMONTHLY'   then (base_date + interval '2 months')::date
        when 'QUARTERLY'   then (base_date + interval '3 months')::date
        when 'HALF_YEARLY' then (base_date + interval '6 months')::date
        when 'YEARLY'      then (base_date + interval '1 year')::date
    end
$$ language sql immutable strict;

---

create function public.first_recurrence_date(
    base_date           date,
    recurrence_interval public.document_recurrence_interval
) returns date as $$
    select public.next_recurrence_interval_date(
        date_trunc('month', base_date)::date + (
            least(
                extract(day from base_date)::integer,
                28 -- max is 28th day to fit Feb.
            ) - 1  -- make delta zero based
        ),
        recurrence_interval
    )
$$ language sql immutable strict;

---

create function public.set_document_recurrence(
    document_id     uuid,
    starts_at       date,
    "interval"      public.document_recurrence_interval,
    max_recurrences integer = null,
    ends_at         date = null
) returns public.document_recurrence as $$
declare
    r public.document_recurrence;
begin
    perform public.disable_active_document_recurrences(set_document_recurrence.document_id);

    insert into public.document_recurrence (
        document_id,
        starts_at,
        interval,
        max_recurrences,
        ends_at,
        created_by
    )
    values (
        set_document_recurrence.document_id,
        set_document_recurrence.starts_at,
        set_document_recurrence.interval,
        set_document_recurrence.max_recurrences,
        set_document_recurrence.ends_at,
        private.current_user_id()
    )
    returning * into r;

    return r;
end
$$ language plpgsql volatile;

----

create function public.document_recurrence_dates(
  rec public.document_recurrence
) returns setof date as $$
declare
  i int;
  d date;
begin
  -- starting date is always the first occurrence
  return next rec.starts_at;

  -- first occurence was above
  i := 1;
  d := rec.starts_at;

  while rec.max_recurrences is null or i < rec.max_recurrences loop
    d := public.next_recurrence_interval_date(d, rec.interval);

    if d is null
    then
      raise exception 'Unsupported recurrence interval %', rec.interval;
    end if;

    if d > rec.ends_at
    then
      -- end date reached
      return;
    end if;

    return next d;

    if d > now()::date
    then
      -- one occurrence after today and then end loop (occurrences limit)
      return;
    end if;

    i = i + 1;
  end loop;
end
$$ language plpgsql immutable strict;

comment on function public.document_recurrence_dates is 'Recurrence dates including the start and optional end date, but never more than one after today';


-- TODO: Denis remove and use public.document_recurrence_dates
create function public.document_recurrence_occurrences(
    document_recurrence public.document_recurrence
) returns setof date as $$
    select public.document_recurrence_dates(document_recurrence_occurrences.document_recurrence)
$$ language sql immutable strict;


create function public.document_recurrence_prev_date(
    document_recurrence public.document_recurrence
) returns date as $$
    select d
    from public.document_recurrence_dates(document_recurrence) as d
    where d <= now()::date
    order by d desc
    limit 1
$$ language sql immutable strict;


-- TODO: Denis remove and use public.document_recurrence_prev_date
create function public.document_recurrence_prev_occurrence(
    document_recurrence public.document_recurrence
) returns date as $$
    select public.document_recurrence_prev_date(document_recurrence_prev_occurrence.document_recurrence)
$$ language sql immutable strict;


create function public.document_recurrence_next_date(
    document_recurrence public.document_recurrence
) returns date as $$
    select d
    from public.document_recurrence_dates(document_recurrence) as d
    where d > now()::date
    limit 1
$$ language sql immutable strict;

-- TODO: Denis remove and use public.document_recurrence_next_date
create function public.document_recurrence_next_occurrence(
    document_recurrence public.document_recurrence
) returns date as $$
    select public.document_recurrence_next_date(document_recurrence_next_occurrence.document_recurrence)
$$ language sql immutable strict;

----

create function public.document_recurrence_ended(
    document_recurrence public.document_recurrence
) returns boolean as $$
    select document_recurrence.disabled_at is not null
        or public.document_recurrence_next_date(document_recurrence) is null
$$ language sql immutable strict;
comment on function public.document_recurrence_ended is E'@notNull\nHas the recurrence ended? Either by being disabled or expired.';

create function public.document_active_recurrence(
    document public.document
) returns public.document_recurrence as $$
    select document_recurrence.* from public.document_recurrence
    where (document_recurrence.document_id = document.id
        or document_recurrence.document_id = document.base_document_id)
    and (document_recurrence.disabled_at is null
        or exists (select from public.document_recurrence_document
            where document_recurrence_document.recurrence_id = document_recurrence.id))
    -- limit 1 is unnecessary because of "document_recurrence_only_one_active" unique index
$$ language sql stable strict;

create function public.document_has_active_recurrence(
    document public.document
) returns boolean as $$
    select exists (
        select document_recurrence.* from public.document_recurrence
        where (document_recurrence.document_id = document.id
            or document_recurrence.document_id = document.base_document_id)
        and (document_recurrence.disabled_at is null
            or exists (select from public.document_recurrence_document
                where document_recurrence_document.recurrence_id = document_recurrence.id))
    )
$$ language sql stable strict;
comment on function public.document_has_active_recurrence is '@notNull';
