create view api.document_category_object_instance with (security_barrier) as
    select 
        dcoi.document_category_id,
        dcoi.object_instance_id,
        dcoi.created_by,
        dcoi.created_at
    from public.document_category_object_instance as dcoi
        join api.document_category as dc on (dc.id = dcoi.document_category_id)
        join api.client_company as cc on (cc.company_id = dc.client_company_id);

grant select on table api.document_category_object_instance to domonda_api;

comment on column api.document_category_object_instance.document_category_id is '@notNull';
comment on column api.document_category_object_instance.object_instance_id is '@notNull';
comment on column api.document_category_object_instance.created_by is '@notNull';
comment on column api.document_category_object_instance.created_at is '@notNull';
comment on view api.document_category_object_instance is $$
@primaryKey document_category_id,object_instance_id
@foreignKey (document_category_id) references api.document_category (id)
@foreignKey (object_instance_id) references api.object_instance (id)
Connects a document category to an object instance.$$;

----

create function api.document_category_object_instance(doc api.document) returns api.object_instance
language sql stable strict as
$$
    select o.*
    from api.object_instance as o
        join api.document_category_object_instance as co
            on co.object_instance_id = o.id
    where co.document_category_id = doc.category_id
$$;
