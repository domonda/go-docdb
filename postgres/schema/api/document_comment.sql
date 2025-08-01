create view api.document_comment with (security_barrier) as
    select
        document_comment.id,
        document_id,
        commented_by,
        message,
        document_comment.created_at
    from public.document_comment
        inner join api.document on document.id = document_comment.document_id;

grant select on table api.document_comment to domonda_api;

comment on column api.document_comment.document_id is '@notNull';
comment on column api.document_comment.commented_by is '@notNull';
comment on column api.document_comment.message is '@notNull';
comment on column api.document_comment.created_at is '@notNull';
comment on view api.document_comment is $$
@primaryKey id
@foreignKey (document_id) references api.document (id)
@foreignKey (commented_by) references api.user (id)

A `DocumentComment` representing a comment left on a `Document`.$$;

create type api.document_comment_message_part as (
    normal text, -- just normal text, without any formatting
    bold   text,
    italic text,

    document_id uuid,
    user_id     uuid
);

comment on type api.document_comment_message_part is $$
@foreignKey (document_id) references api.document (id)
@foreignKey (user_id) references api.user (id)$$;

create function api.document_comment_message_parts(
    document_comment api.document_comment
) returns setof api.document_comment_message_part as $$
    select
        value->>0 as normal,
        value->>'b' as bold,
        value->>'i' as italic,
        (value->>'document')::uuid as document_id,
        (value->>'user')::uuid as user_id
    from jsonb_array_elements(document_comment.message)
$$ language sql immutable strict;

create function api.document_comment_text_message(
    document_comment api.document_comment
) returns text as $$
    select string_agg(
        coalesce(
            part.normal,
            part.bold,
            part.italic,
            (select api.user_full_name("user") from api."user" where "user".id = part.user_id),
            (select api.document_derived_title(document) from api.document where document.id = part.document_id),
            '?'
        ),
        ''
    )
    from api.document_comment_message_parts(document_comment) as part
$$ language sql stable strict
security definer; -- in order to use public.user (the api.user doesn't have the full list of accessible users)
comment on function api.document_comment_text_message is '@notNull';

----

create view api.document_comment_seen with (security_barrier) as
    select
        document_comment_id,
        seen_by,
        document_comment_seen.created_at
    from public.document_comment_seen
        inner join api.document_comment on document_comment.id = document_comment_seen.document_comment_id;

grant select on table api.document_comment_seen to domonda_api;

comment on column api.document_comment_seen.created_at is '@notNull';
comment on view api.document_comment_seen is $$
@primaryKey document_comment_id,seen_by
@foreignKey (document_comment_id) references api.document_comment (id)
@foreignKey (seen_by) references api.user (id)

A `DocumentCommentSeen` representing all users that have seen/viewed a `DocumentComment`.$$;

----

create view api.document_comment_like with (security_barrier) as
    select
        document_comment_id,
        liked_by,
        document_comment_like.created_at
    from public.document_comment_like
        inner join api.document_comment on document_comment.id = document_comment_like.document_comment_id;

grant select on table api.document_comment_like to domonda_api;

comment on column api.document_comment_like.created_at is '@notNull';
comment on view api.document_comment_like is $$
@primaryKey document_comment_id,liked_by
@foreignKey (document_comment_id) references api.document_comment (id)
@foreignKey (liked_by) references api.user (id)

A `DocumentCommentSeen` representing all users that have liked a `DocumentComment`.$$;
