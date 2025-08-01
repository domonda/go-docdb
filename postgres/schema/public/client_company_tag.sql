create table public.client_company_tag (
    id                uuid primary key,
    client_company_id uuid not null references public.client_company(company_id) on delete cascade,
    tag               text not null check(length(tag) > 0),
    unique(client_company_id, tag),

    created_at created_time not null
);

grant select, insert, update, delete on table public.client_company_tag to domonda_user;
grant select on public.client_company_tag to domonda_wg_user;

----

create function public.create_client_company_tag(
    client_company_id uuid,
    tag               text
) returns public.client_company_tag as
$$
    insert into public.client_company_tag (id, client_company_id, tag)
        values (uuid_generate_v4(), create_client_company_tag.client_company_id, create_client_company_tag.tag)
    returning *
$$
language sql volatile strict;

comment on function public.create_client_company_tag(uuid, text) is 'Creates a new `ClientCompanyTag` for tagging documents.';

----

create function public.update_client_company_tag(
    id  uuid,
    tag text
) returns public.client_company_tag as
$$
    update public.client_company_tag
        set
            tag=trim(update_client_company_tag.tag)
    where id = update_client_company_tag.id
    returning *
$$
language sql volatile strict;

----

create function public.delete_client_company_tag(
    id uuid
) returns public.client_company_tag as
$$
    delete from public.client_company_tag where id = delete_client_company_tag.id returning *
$$
language sql volatile strict;

create function public.delete_client_company_tags(
    ids uuid[]
) returns setof public.client_company_tag as
$$
    delete from public.client_company_tag where id = any(delete_client_company_tags.ids) returning *
$$
language sql volatile strict;

----

create function public.get_or_create_client_company_tag(
    client_company_id uuid,
    tag text
) returns public.client_company_tag as
$$
    insert into public.client_company_tag (id, client_company_id, tag)
        values (uuid_generate_v4(), get_or_create_client_company_tag.client_company_id, get_or_create_client_company_tag.tag)
        on conflict(client_company_id, tag)
            do update set tag=trim(get_or_create_client_company_tag.tag) -- This is a dummy update so RETURNING * will work
        returning *
$$
language sql volatile;

comment on function public.get_or_create_client_company_tag(uuid, text) is 'Gets or creates a new client_company_tag';

----

create function public.merge_client_company_tags(
    client_company_id              uuid,
    tag                            text,
    merging_client_company_tag_ids uuid[]
) returns public.client_company_tag as
$$
declare
    created_tag                   record;
    merging_client_company_tag_id uuid;
begin
    -- create new tag to be merged onto (here we randomly generate a tag name so that we don't have name collisions)
    insert into public.client_company_tag (id, client_company_id, tag)
        values (uuid_generate_v4(), merge_client_company_tags.client_company_id, uuid_generate_v4()::text)
    returning
        * into created_tag;

    -- loop throgh all merging tags
    foreach merging_client_company_tag_id in array merge_client_company_tags.merging_client_company_tag_ids loop

        -- move merging tagged documents to new tag
        update public.document_tag as dt
            set
                client_company_tag_id=created_tag.id
        where (
            dt.client_company_tag_id = merging_client_company_tag_id
        ) and (
            not exists (
                select 1 from public.document_tag
                where (
                    document_id = dt.document_id
                ) and (
                    client_company_tag_id = created_tag.id
                )
            )
        );

        -- delete merging tag
        delete from public.client_company_tag where id = merging_client_company_tag_id;

    end loop;

    -- update the created tag with the requested name
    update public.client_company_tag
        set
            tag=merge_client_company_tags.tag
    where id = created_tag.id
    returning
        * into created_tag;

    return created_tag;
end;
$$
language plpgsql volatile strict;

----

create function public.client_company_tags_by_ids(
    ids uuid[]
) returns setof public.client_company_tag as $$
    select * from public.client_company_tag where id = any(ids)
$$ language sql stable strict;
