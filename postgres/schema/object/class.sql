create table object.class (
    name trimmed_text primary key,

    -- NULL means the class is not bound to a specific client company
    client_company_id uuid references public.client_company(company_id) on delete cascade,

    created_at timestamptz not null default now()
);

grant select on object.class to domonda_user;
grant select on object.class to domonda_wg_user;


----

create view public.object_class with (security_barrier) as 
    select
        name,
        client_company_id
    from object.class
    join public.client_company -- for row level security
        on client_company.company_id = class.client_company_id; -- TODO what if class.client_company_id is null?

grant select on table public.object_class to domonda_user, domonda_wg_user;

comment on column public.object_class.name is '@notNull';
comment on column public.object_class.client_company_id is '@notNull';
comment on view public.object_class is $$
@primaryKey name
@foreignKey (client_company_id) references public.client_company (company_id)
$$;


----

create table object.class_prop (
    id uuid primary key default uuid_generate_v4(),

    class_name trimmed_text not null references object.class(name) on delete restrict,
    name       trimmed_text not null,
    constraint unique_prop_name_in_class unique(class_name, name),

    "type" object.prop_type not null,

    -- If true then for non-array types exactly one value
    -- row is assumed else there can be zero or one row.
    -- For array types one row per array index is assumed
    -- or missing array indices if required is false.
    required boolean not null default false,

    -- Option values for the special 'TEXT_OPTION' type
    options text[] check(array_length(options, 1) > 0),
    constraint options_available check((object.prop_type_has_options("type")) = (options is not null)),

    description trimmed_text,

    -- Specifies the order of props for display in
    -- the user interface or mapping to structs
    pos serial not null, -- For ordering in UI
    constraint unique_pos_in_class unique(class_name, pos),

    created_at timestamptz not null default now()
);

grant all on object.class_prop to domonda_user;
grant select on object.class_prop to domonda_wg_user;

create index class_prop_class_name_idx on object.class_prop ("class_name");
create index class_prop_name_idx on object.class_prop ("name");
create index class_prop_type_idx on object.class_prop ("type");

----

create function object.class_prop_names(c object.class) returns text[]
language sql stable strict as $$
    select array_agg(name order by pos)
    from object.class_prop
    where class_name = c.name
$$;

-- create function object.class_prop_check_option_index(c object.class, option_index int)
--   returns void
-- language sql plpgsql as
-- $$
-- begin
--   if option_index is null then
--       raise exception ''
--   end if;
-- end
-- $$;