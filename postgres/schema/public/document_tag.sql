create table public.document_tag (
    client_company_tag_id uuid not null references public.client_company_tag(id) on delete cascade,
    document_id           uuid not null references public.document(id)           on delete cascade,
    primary key(client_company_tag_id, document_id),

    -- Position on document (optional)
    page  int,
    pos_x float8,
    pos_y float8,

    -- added_by uuid references public.user(id) on delete set null, -- TODO for audit trail
    
    updated_at updated_time not null,
    created_at created_time not null
);

grant select, insert, update, delete on table public.document_tag to domonda_user;
grant select on public.document_tag to domonda_wg_user;

create index document_tag_client_company_tag_id_idx on public.document_tag (client_company_tag_id);
create index document_tag_document_id_idx on public.document_tag (document_id);

----

create function public.add_document_tag(
    client_company_tag_id uuid,
    document_id           uuid
) returns public.document_tag as
$$
    insert into public.document_tag (
        client_company_tag_id,
        document_id
    ) values (
        add_document_tag.client_company_tag_id,
        add_document_tag.document_id
    )
    returning *
$$
language sql volatile;

comment on function public.add_document_tag is 'Adds a `ClientCompanyTag` to a `Document`. Creates a new entry in `DocumentTag`.';

----

create function public.delete_document_tag(
    client_company_tag_id uuid,
    document_id           uuid
) returns public.document_tag as
$$
    delete from public.document_tag
    where (
        delete_document_tag.client_company_tag_id = document_tag.client_company_tag_id
    ) and (
        delete_document_tag.document_id = document_tag.document_id
    )
    returning *
$$
language sql volatile;

----

-- ? is used ?
create function public.tag_document(
    document_id    uuid,
    client_company_tag_id uuid
) returns public.document_tag as
$$
    insert into public.document_tag (client_company_tag_id, document_id)
        values (tag_document.client_company_tag_id,tag_document.document_id)
        on conflict(client_company_tag_id, document_id)
            do update set client_company_tag_id=tag_document.client_company_tag_id -- This is a dummy update so RETURNING * will work
        returning *
$$
language sql volatile;

comment on function public.tag_document(uuid, uuid) is 'Adds a tag to a document if it was not tagged with it before';

grant execute on function public.tag_document(uuid, uuid) to domonda_user;


----


create function public.move_document_tag(
    client_company_tag_id uuid,
    document_id    uuid,
    -- position on document (optional)
    page  int,
    pos_x float8,
    pos_y float8
) returns public.document_tag as
$$
    update public.document_tag
        set
            page = move_document_tag.page,
            pos_x = move_document_tag.pos_x,
            pos_y = move_document_tag.pos_y,
            updated_at = now()
        where
            (client_company_tag_id = move_document_tag.client_company_tag_id) and (document_id = move_document_tag.document_id)
        returning *
$$
language sql volatile;

comment on function public.move_document_tag(uuid, uuid, int, float8, float8) is 'Change the tag positioning on the document';

grant execute on function public.move_document_tag(uuid, uuid, int, float8, float8) to domonda_user;

----

create function public.remove_document_tag(
    client_company_tag_id uuid,
    document_id    uuid
) returns public.document_tag as
$$
    delete from public.document_tag
        where (client_company_tag_id = remove_document_tag.client_company_tag_id) and (document_id = remove_document_tag.document_id)
        returning *
$$
language sql volatile;

comment on function public.remove_document_tag(uuid, uuid) is 'Removes a tag from a document';

grant execute on function public.remove_document_tag(uuid, uuid) to domonda_user;

----

create function public.add_document_tag_to_documents(
    client_company_tag_id uuid,
    document_ids   text[],
    -- Position on document (optional)
    page  int,
    pos_x float8,
    pos_y float8
) returns public.document_tag as
$$
    insert into
        public.document_tag (
            client_company_tag_id,
            document_id,
            page,
            pos_x,
            pos_y
        )
	        select
	            add_document_tag_to_documents.client_company_tag_id,
	            id::uuid,
	            add_document_tag_to_documents.page,
	            add_document_tag_to_documents.pos_x,
	            add_document_tag_to_documents.pos_y
	        from unnest(add_document_tag_to_documents.document_ids) as id
        returning *
$$
language sql volatile;

comment on function public.add_document_tag_to_documents(uuid, text[], int, float8, float8) is E'@deprecated\nAdds a tag to documents, with optional positioning on the document';

grant execute on function public.add_document_tag_to_documents(uuid, text[], int, float8, float8) to domonda_user;

----

create function public.remove_document_tag_from_documents(
    client_company_tag_id uuid,
    document_ids    text[]
) returns public.document_tag as
$$
    delete from public.document_tag
    where (client_company_tag_id = remove_document_tag_from_documents.client_company_tag_id) and (document_id::text = any(remove_document_tag_from_documents.document_ids))
    returning *
$$
language sql volatile;

comment on function public.remove_document_tag_from_documents(uuid, text[]) is E'@deprecated\nRemoves a tag from documents';

grant execute on function public.remove_document_tag_from_documents(uuid, text[]) to domonda_user;

----

create function public.create_document_tag_for_documents(
    client_company_tag_id uuid,
    document_ids          uuid[]
) returns setof public.document_tag as $$
    insert into public.document_tag (client_company_tag_id, document_id)
    (select create_document_tag_for_documents.client_company_tag_id, document.id
    from public.document
    where document.id = any(document_ids))
    on conflict do nothing
    returning *
$$ language sql volatile strict;

create function public.delete_document_tag_from_documents(
    client_company_tag_id uuid,
    document_ids          uuid[]
) returns setof public.document_tag as $$
    delete from public.document_tag
    where client_company_tag_id = delete_document_tag_from_documents.client_company_tag_id
    and document_id = any(document_ids)
    returning *
$$ language sql volatile strict;
