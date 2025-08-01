create function work.rights_id_comment_on_documents_only() returns uuid
language sql immutable parallel safe as
$$
    select '5a429301-3eb4-4f25-9e55-5e93407b9f18'::uuid;
$$;

insert into work.rights (
    id,
    name,
    can_comment_on_documents,
    can_change_documents,
    created_by
) values (
    work.rights_id_comment_on_documents_only(),
    'Comment on documents only',
    true, -- can_comment_on_documents
    false, -- can_change_documents
    public.unknown_user_id() -- TODO: different user from Unknown?
);

create function work.rights_id_change_documents() returns uuid
language sql immutable parallel safe as
$$
    select 'bbc18bde-bcc5-45c5-98ff-d0a0ccf4ac3d'::uuid;
$$;

insert into work.rights (
    id,
    name,
    can_comment_on_documents,
    can_change_documents,
    created_by
) values (
    work.rights_id_change_documents(),
    'Change documents',
    true, -- can_comment_on_documents
    true, -- can_change_documents
    public.unknown_user_id() -- TODO: different user from Unknown?
);
