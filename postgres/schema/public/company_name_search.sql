create table private.company_name_blacklist (
    "name" text primary key check(trim("name") = "name" and upper("name") = "name")
);

insert into private.company_name_blacklist ("name")
values
    ('GMBH'),
    ('GESMBH'),
    ('GES.M.B.H.'),
    ('MBH'),
    ('M.B.H.'),
    ('BESCHRÄNKTER HAFTUNG'),
    ('CO KG'),
    ('CO. KG'),
    ('CO. KG.'),
    ('CO.KG.'),
    ('GMBH & CO. OHG'),
    ('GMBH & CO. KG'),
    ('CO KOMMANDITGESELLSCHAFT'),
    ('S.R.O.'),
    ('SRO.'),
    ('S R. O.'),
    ('SP. Z O.O.'),
    ('SP. Z. O.O.'),
    ('SP.Z.O.O.'),
    ('A.S.'),
    ('KFT'),
    ('KFT.'),
    ('KG'),
    ('KOMMANDITGESELLSCHAFT'),
    ('NFG. KG.'),
    ('AG'),
    ('AG.'),
    ('AKTIENGES'),
    ('E.U.'),
    ('LTD'),
    ('LTD.'),
    ('LLP'),
    ('LIMITED'),
    ('LLC'),
    ('LLC.'),
    ('INC'),
    ('INC.'),
    ('E.V.'),
    ('OG'),
    ('OG.'),
    ('KONTO'),
    ('HERRN'),
    ('HERR'),
    ('FRAU'),
    ('BANK')
;

----

create function private.substring_pattern(
    search text
) returns text as
$$
    -- See https://www.postgresql.org/docs/current/functions-matching.html#FUNCTIONS-LIKE
    select '%' ||
        replace(
            replace(
                replace(
                    trim(search),
                    '\', '/' -- replace LIKE escape character '\' with something else
                ),
                '_', '\_' -- escape LIKE wildcard character '_'
            ),
            '%', '\%' -- escape LIKE wildcard character '%'
        )
    || '%'
$$
language sql immutable strict;

----

create function private.fuzzy_company_name_match(
    search_name       text,
    legal_name        text,
    brand_name        text = null,
    alternative_names text[] = null
) returns boolean as
$$
declare
    alt_name text;
begin
    -- Don't ever match too short search_name or numbers 
    search_name := trim(search_name);
    if length(search_name) < 3 or search_name ~ '^[-+.,\d\s]+$' then
        return false;
    end if;

    -- Don't match blacklisted words
    if exists (select from private.company_name_blacklist where "name" = upper(search_name)) then
        return false;
    end if;

    -- Match if legal_name is a case insensitive contained in search_name
    legal_name := trim(legal_name);
    if (legal_name = search_name)
        or (length(legal_name) > 4 and search_name ilike private.substring_pattern(legal_name))
    then
        return true;
    end if;

    if brand_name is not null then
         -- Match if brand_name is exactly search_name or is long enough and contained in search_name
        brand_name := trim(brand_name);
        if (brand_name = search_name)
            or (length(brand_name) > 4 and search_name like private.substring_pattern(brand_name))
        then
            return true;
        end if;
    end if;

    if alternative_names is not null then
        foreach alt_name in array alternative_names loop
            -- Match if alt_name is exactly search_name or is long enough and contained in search_name
            alt_name := trim(alt_name);
            if (alt_name = search_name)
                or (length(alt_name) > 4 and search_name like private.substring_pattern(alt_name))
            then
                return true;
            end if;
        end loop;
    end if;

    return false;
end
$$
language plpgsql immutable;

----

create function public.company_has_fuzzy_name(
    company public.company,
    "name"  text
) returns boolean as
$$
    select private.fuzzy_company_name_match(
        company_has_fuzzy_name.name,
        company_has_fuzzy_name.company.name,
        company_has_fuzzy_name.company.brand_name,
        company_has_fuzzy_name.company.alternative_names
    )
$$
language sql immutable strict;

comment on function public.company_has_fuzzy_name is e'@notNull\nReturns if the company has the passed name, brand-name or alternative name using fuzzy string comparison';