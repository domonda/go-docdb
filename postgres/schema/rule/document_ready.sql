create table rule.document_ready (
    id uuid primary key default uuid_generate_v4(),

    document_id uuid not null references public.document(id) on delete cascade,

    is_ready boolean not null default false,
    reason   text, -- why did the document become ready or not ready?

    -- the document is now _not ready_ because there was an attempt to set it
    -- as _ready_ but the rules could not be executed because of an exception.
    -- happens when the rules are misconfigured, broken or invalid
    attempted_is_ready_true boolean not null default false,
    constraint document_not_ready_when_attempted_is_ready check (
        case
            when attempted_is_ready_true
            then not is_ready
            else true
        end
    ),

    created_at created_time not null default now()
);

grant select on rule.document_ready to domonda_user;
grant select on rule.document_ready to domonda_wg_user;

create index document_document_id_idx on rule.document_ready (document_id);
create index document_is_ready_idx on rule.document_ready (is_ready);
create index document_attempted_is_ready_true_idx on rule.document_ready (attempted_is_ready_true);

----

create function rule.is_document_ready(id uuid)
returns boolean as
$$
    select coalesce(
        (
            select is_ready from rule.document_ready
            where document_id = is_document_ready.id
            order by created_at desc, is_ready desc -- when multiple ready entries occur in the same time, consider the document ready
            limit 1
        ),
        false
    )
$$ language sql stable strict;

----

create function rule.get_document_ready(id uuid)
returns rule.document_ready as
$$
    select * from rule.document_ready
    where document_id = get_document_ready.id
    order by created_at desc, is_ready desc -- when multiple ready entries occur in the same time, consider the document ready
    limit 1
$$ language sql stable strict;

----

create function rule.safe_set_document_ready(
    document_id uuid,
    is_ready boolean,
    created_at created_time,
    reason text = null
) returns rule.document_ready as $$
declare
    inserted_document_ready rule.document_ready;
begin
    insert into rule.document_ready (document_id, is_ready, reason, created_at)
    values (
        safe_set_document_ready.document_id,
        safe_set_document_ready.is_ready,
        safe_set_document_ready.reason,
        safe_set_document_ready.created_at
    )
    returning * into inserted_document_ready;
    return inserted_document_ready;
exception when others then
    insert into rule.document_ready (document_id, is_ready, reason, attempted_is_ready_true, created_at)
    values (
        safe_set_document_ready.document_id,
        false,
        SQLERRM || E'\n\nAttempted reason:\n' || coalesce(safe_set_document_ready.reason, 'NULL'),
        true,
        safe_set_document_ready.created_at
    )
    returning * into inserted_document_ready;
    return inserted_document_ready;
end
$$ language plpgsql volatile;
