create table private.feature (
    id     uuid primary key default uuid_generate_v4(),
    name   text not null unique check (length(name) > 0),
    active bool not null default false,

    updated_at updated_time not null,
    created_at created_time not null
);

grant select on private.feature to domonda_user;
grant select on private.feature to domonda_wg_user;

create index feature_name_idx on private.feature (name);

comment on table private.feature is 'Code features of the application';
comment on column private.feature.name is 'Name used to query from code if the feature is active';
comment on column private.feature.active is 'If the feature is active by default';

----

create function public.feature_exists(
    feature_name text
) returns bool as
$$
    select exists(select from private.feature where name = feature_exists.feature_name);
$$
language sql stable;

comment on function public.feature_exists(text) is 'Returns if a feature exists in the private.feature table';

----

create function public.all_features() returns text[] as
$$
    select array(select name from private.feature);
$$
language sql stable;

comment on function public.all_features() is 'Returns the names of all features, independent of if active or not';
grant execute on function public.all_features() to domonda_user;

----

create function public.is_global_feature_active(
    feature_name text
) returns bool as
$$
    select coalesce(
        (
            select
                feat.active
            from private.feature as feat
            where feat.name = is_global_feature_active.feature_name
        ),
        false
    )
$$
language sql stable;

comment on function public.is_global_feature_active(text) is 'Returns if a global feature is active';
grant execute on function public.is_global_feature_active(text) to domonda_user;

----

create table private.client_company_feature (
    feature_id        uuid references private.feature(id) on delete cascade,
    client_company_id uuid references public.client_company(company_id) on delete cascade,
    primary key(feature_id, client_company_id),

    active bool not null default false,

    updated_at updated_time not null,
    created_at created_time not null
);

grant select on private.client_company_feature to domonda_user;
grant select on private.client_company_feature to domonda_wg_user;

----

create table private.client_company_user_feature (
    feature_id        uuid references private.feature(id) on delete cascade,
    client_company_id uuid references public.client_company(company_id) on delete cascade,
    user_id           uuid references public.user(id) on delete cascade,
    primary key(feature_id, client_company_id, user_id),

    active bool not null default false,

    updated_at updated_time not null,
    created_at created_time not null
);

grant select on private.client_company_user_feature to domonda_user;
grant select on private.client_company_user_feature to domonda_wg_user;

----

create function public.is_company_feature_active(
    feature_name      text,
    client_company_id uuid
) returns bool as
$$
    select coalesce(
        (
            select
                coalesce(
                    comp_feat.active,
                    feat.active
                )
            from private.feature as feat
            left join private.client_company_feature as comp_feat
                on comp_feat.feature_id = feat.id
                    and comp_feat.client_company_id = is_company_feature_active.client_company_id
            where feat.name = is_company_feature_active.feature_name
        ),
        false
    )
$$
language sql stable;

comment on function public.is_company_feature_active(text, uuid) is 'Returns if a feature is active for a given client company';
grant execute on function public.is_company_feature_active(text, uuid) to domonda_user;

----

create function public.is_user_feature_active(
    feature_name      text,
    client_company_id uuid,
    user_id           uuid
) returns bool as
$$
    select coalesce(
        (
            select
                coalesce(
                    comp_user_feat.active,
                    comp_feat.active,
                    feat.active
                )
            from private.feature as feat
            left join private.client_company_feature as comp_feat
                on comp_feat.feature_id = feat.id
                    and comp_feat.client_company_id = is_user_feature_active.client_company_id
            left join private.client_company_user_feature as comp_user_feat
                on comp_user_feat.feature_id = feat.id
                    and comp_user_feat.client_company_id = is_user_feature_active.client_company_id
                    and comp_user_feat.user_id = is_user_feature_active.user_id
            where feat.name = is_user_feature_active.feature_name
        ),
        false
    )
$$
language sql stable;

comment on function public.is_user_feature_active(text, uuid, uuid) is 'Returns if a feature is active for a given client company and user';
grant execute on function public.is_user_feature_active(text, uuid, uuid) to domonda_user;

----

create function public.active_features_for_company_and_user(
    client_company_id uuid,
    user_id           uuid
) returns text[] as
$$
    select array(
        select
            feat.name
        from private.feature as feat
        left join private.client_company_feature as comp_feat
            on comp_feat.feature_id = feat.id
                and comp_feat.client_company_id = active_features_for_company_and_user.client_company_id
        left join private.client_company_user_feature as comp_user_feat
            on comp_user_feat.feature_id = feat.id
                and comp_user_feat.client_company_id = active_features_for_company_and_user.client_company_id
                and comp_user_feat.user_id = active_features_for_company_and_user.user_id
        where coalesce(comp_user_feat.active, comp_feat.active, feat.active) = true
        order by feat.name
    )
$$
language sql stable;

comment on function public.active_features_for_company_and_user(uuid, uuid) is 'Returns an array of feature names that are active for a given company and user';
grant execute on function public.active_features_for_company_and_user(uuid, uuid) to domonda_user;

----

create function private.active_client_company_features(
    client_company_id uuid
) returns text[] as
$$
    select array(
        select
            feat.name
        from private.feature as feat
        left join private.client_company_feature as comp_feat
            on comp_feat.feature_id = feat.id
                and comp_feat.client_company_id = active_client_company_features.client_company_id
        where coalesce(comp_feat.active, feat.active) = true
        order by feat.name
    )
$$
language sql stable;

----

create type public.client_company_feature as (
    id     uuid,
    name   text,
    active bool
);

comment on column public.client_company_feature.id is E'@notNull\n@name id';
comment on column public.client_company_feature.name is '@notNull';
comment on column public.client_company_feature.active is '@notNull';

----

create function public.feature_by_client_company_and_name(
    client_company_id uuid,
    name              text
) returns public.client_company_feature as
$$
    select
        f.id as id,
        f.name as name,
        coalesce(ccuf.active, ccf.active, f.active) as active
    from private.feature as f
        left join private.client_company_feature as ccf on (ccf.feature_id = f.id) and (ccf.client_company_id = feature_by_client_company_and_name.client_company_id)
        left join private.client_company_user_feature as ccuf on (ccuf.feature_id = f.id) and (ccuf.client_company_id = feature_by_client_company_and_name.client_company_id) and (ccuf.user_id = (select id from private.current_user()))
    where f.name = feature_by_client_company_and_name.name
$$
language sql stable strict;

create function public.client_company_feature_by_name(
    client_company public.client_company,
    name           text
) returns public.client_company_feature as
$$
    select public.feature_by_client_company_and_name(
        client_company_feature_by_name.client_company.company_id,
        client_company_feature_by_name.name
    )
$$
language sql stable strict;

----

create function public.is_client_company_feature_active(
    client_company_id uuid,
    name              text
) returns boolean as
$$
    select coalesce(
        (
            select active from public.feature_by_client_company_and_name(
                is_client_company_feature_active.client_company_id,
                is_client_company_feature_active.name
            )
        ),
        false
    )
$$
language sql stable strict;

comment on function public.is_client_company_feature_active is '@notNull';

----

create function public.client_company_is_feature_active(
    client_company public.client_company,
    name           text
) returns boolean as
$$
    select public.is_client_company_feature_active(
        client_company_is_feature_active.client_company.company_id,
        client_company_is_feature_active.name
    )
$$
language sql stable strict;

comment on function public.client_company_is_feature_active is '@notNull';

----

create function public.feature_id_by_name(
    "name" text
) returns uuid as
$$
    select id from private.feature where "name" = feature_id_by_name."name"
$$
language sql stable strict;

----

create function public.set_client_company_feature_active(
    feature_id        uuid,
    client_company_id uuid,
    active            bool
) returns public.client_company as
$$
declare
  client_company record;
begin
    -- only super-admins can set features
    if not private.current_user_super() then
        raise exception 'Unauthorized';
    end if;

    insert into private.client_company_feature (
        feature_id,
        client_company_id,
        active
    ) values (
        set_client_company_feature_active.feature_id,
        set_client_company_feature_active.client_company_id,
        set_client_company_feature_active.active
    )
    on conflict on constraint client_company_feature_pkey do update
        set
            active=set_client_company_feature_active.active,
            updated_at=now();

    select
      * into client_company
    from public.client_company where company_id = set_client_company_feature_active.client_company_id;

    return client_company;
end
$$
language plpgsql volatile strict security definer;

----

create function public.invoice_can_dunn(
    invoice public.invoice
) returns boolean as
$$
    select
        (
            public.is_company_feature_active('DUNNING_SERVICE', d.client_company_id)
        ) and (
            dc.document_type = 'OUTGOING_INVOICE'
        )
    from public.document as d
        inner join public.document_category as dc on dc.id = d.category_id
    where d.id = invoice.document_id
$$
language sql stable;

----

create table private.user_feature (
    feature_id uuid references private.feature(id) on delete cascade,
    user_id    uuid references public.user(id) on delete cascade,
    primary key(feature_id, user_id),

    active bool not null default false,

    updated_at updated_time not null,
    created_at created_time not null
);

grant select on private.user_feature to domonda_user;
grant select on private.user_feature to domonda_wg_user;

----

create function public.user_is_feature_active(
    "user" public.user,
    name   text
) returns boolean as
$$
    select coalesce(
        (select user_feature.active
        from private.user_feature
            inner join private.feature
            on feature.id = user_feature.feature_id
        where user_feature.user_id = "user".id
        and feature.name = user_is_feature_active.name),
        public.is_company_feature_active(user_is_feature_active.name, "user".client_company_id)
    )
$$
language sql stable strict;

comment on function public.user_is_feature_active is '@notNull';

----

create function public.set_user_feature_active(
    feature_id uuid,
    user_id    uuid,
    active     bool
) returns public.user as
$$
declare
  user record;
begin
    -- only super-admins can set features
    if not private.current_user_super() then
        raise exception 'Unauthorized';
    end if;

    insert into private.user_feature (
        feature_id,
        user_id,
        active
    ) values (
        set_user_feature_active.feature_id,
        set_user_feature_active.user_id,
        set_user_feature_active.active
    )
    on conflict on constraint user_feature_pkey do update
        set
            active=set_user_feature_active.active,
            updated_at=now();

    select
      * into user
    from public.user where id = set_user_feature_active.user_id;

    return user;
end
$$
language plpgsql volatile strict security definer;
