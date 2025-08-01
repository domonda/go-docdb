create table rule.send_notification_log(
    id uuid primary key default uuid_generate_v4(),

    action_reaction_id uuid not null references rule.action_reaction(id) on delete cascade,
    document_id        uuid not null references public.document(id) on delete cascade,
    notification_id    uuid not null references private.notification(id) on delete cascade,

    updated_at updated_time not null,
    created_at created_time not null
);

grant select on rule.send_notification_log to domonda_user;
grant select on rule.send_notification_log to domonda_wg_user;

create index send_notification_log_action_reaction_id_idx on rule.send_notification_log (action_reaction_id);
create index send_notification_log_document_id_idx on rule.send_notification_log (document_id);
create index send_notification_log_notification_id_idx on rule.send_notification_log (notification_id);
