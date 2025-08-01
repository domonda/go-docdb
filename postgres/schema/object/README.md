# The object schema

The goal of this schema is to provide a dynamic type system
for objects with props (object data fields) that does not
depend on creating new tables for every object class.

This allows new classes to be defined by users of the app
without changing the database schema.

It follows the classic object pattern of defining
an object type as a class and then creating instances
of that class to hold data.

A class is defined by a class name stored in the `object.class`
table and multiple class props stored in `object.class_prop`.

Classes can be specific to client companies if created by an app user
or global for cross-client company functionality.

Instances of a class consist of an instance `id` and a class reference
in the `object.instance` table
and optional rows for prop values in prop type specific tables.

Every prop type has a specific table for values of that type
where every row references an instance and class prop.

This means that there can be 0..n values per instance prop without
the possibility of constraining the number of values per prop.

The variable number of values per prop is used to implement
optional values (0..1) and arrays (0..n).

If there is no row for a required prop value then the zero
or empty value for the prop type has to be assumed which
depending on the type might not always be a valid value.

If an array type prop is required then the array
has to have at least one element.


```sql
create table object.class (
    name trimmed_text primary key
);

create table object.class_prop (
    id uuid primary key default uuid_generate_v4(),

    class_name trimmed_text not null references object.class(name) on delete restrict,
    name       trimmed_text not null,

    type object.prop_type not null,

    -- If true then exactly 1 value row is assumed
    -- else it can be 0 or 1 for non array types
    required boolean not null default false,

    -- Option values for the special 'TEXT_OPTION' type
    options text[] check(array_length(options, 1) > 0),

    description trimmed_text,

    -- Specifies the order of props for display in
    -- the user interface or mapping to structs
    pos int not null check(pos >= 0), 
);
```

An instance is just an `id` plus references
to class and client company:

```sql
create table object.instance (
    id uuid primary key default uuid_generate_v4(),

    client_company_id uuid not null references public.client_company(company_id) on delete cascade,
    class_name trimmed_text not null references object.class(name) on delete restrict,
);
```

Example for prop type specific table.
The optional `array_index` allows for sorting
and finding array elements by index:

```sql
create table object.number_prop (
    id uuid primary key default uuid_generate_v4(),

    instance_id   uuid not null references object.instance(id) on delete cascade,
    class_prop_id uuid not null references object.class_prop(id) on delete restrict,

    array_index int check(array_index >= 0), -- zero based

    value float8 not null,

    ...
);
```