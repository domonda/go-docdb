create function private.gen_company_name_variations(comp_name text) returns setof text
language plpgsql immutable strict as $$
declare
    pos integer;
    comp_name_var text;
    has_space boolean;
begin
    -- TODO remove Umlaute

    return next comp_name;

    has_space := position(' ' in comp_name) > 0;
    if has_space then
        return next replace(comp_name, ' ', '');
    end if;

    pos := position(' & ' in comp_name);
    if pos > 0 then
        comp_name_var := overlay(comp_name placing ' ' from pos for 3);
        return next comp_name_var;

        if has_space then
            return next replace(comp_name_var, ' ', '');
        end if;
    end if;

    pos := position('Co.' in comp_name);
    if pos > 0 then
        comp_name_var := overlay(comp_name placing 'Co' from pos for 3);
        return next comp_name_var;

        if has_space then
            return next replace(comp_name_var, ' ', '');
        end if;
    end if;

    return;
end
$$;

---

create function private.gen_address_variations(addr text) returns setof text
language plpgsql immutable strict as $$
declare
    pos integer;
    addr_var text;
    has_space boolean;
begin
    -- TODO remove Umlaute

    return next addr;

    has_space := position(' ' in addr) > 0;
    if has_space then
        return next replace(addr, ' ', '');
    end if;

    pos := position('tr.' in addr);
    if pos > 0 then
        addr_var := overlay(addr placing 'traße' from pos for 3);
        return next addr_var;

        if has_space then
            return next replace(addr_var, ' ', '');
        end if;
    end if;

    pos := position('str. ' in addr);
    if pos > 0 then
        return next overlay(addr placing 'str ' from pos for 5);
        return next overlay(addr placing 'str' from pos for 5);
    end if;

    pos := position('traße' in addr);
    if pos > 0 then
        addr_var := overlay(addr placing 'tr.' from pos for 5);
        return next addr_var;

        if has_space then
            return next replace(addr_var, ' ', '');
        end if;

        addr_var := overlay(addr placing 'tr' from pos for 5);
        return next addr_var;

        if has_space then
            return next replace(addr_var, ' ', '');
        end if;
    end if;

    pos := position('g.' in addr);
    if pos > 0 then
        addr_var := overlay(addr placing 'gasse' from pos for 2);
        return next addr_var;

        if has_space then
            return next replace(addr_var, ' ', '');
        end if;

        pos := position('g. ' in addr);
        if pos > 0 then
            return next overlay(addr placing 'g ' from pos for 3);
            return next overlay(addr placing 'g' from pos for 3);
        end if;
    end if;

    pos := position('G.' in addr);
    if pos > 0 then
        addr_var := overlay(addr placing 'Gasse' from pos for 2);
        return next addr_var;

        if has_space then
            return next replace(addr_var, ' ', '');
        end if;
    end if;

    pos := position('asse' in addr);
    if pos > 0 then
        addr_var := overlay(addr placing '.' from pos for 4);
        return next addr_var;

        if has_space then
            return next replace(addr_var, ' ', '');
        end if;
    end if;

    pos := position(' - ' in addr);
    if pos > 0 then
        return next overlay(addr placing ' ' from pos for 3);
    else
        pos := position('-' in addr);
        if pos > 0 then
            return next overlay(addr placing ' ' from pos for 1);
            return next overlay(addr placing ' - ' from pos for 1);
        end if;
    end if;

    pos := position(' + ' in addr);
    if pos > 0 then
        return next overlay(addr placing ' ' from pos for 3);
    else
        pos := position('+' in addr);
        if pos > 0 then
            return next overlay(addr placing ' ' from pos for 1);
            return next overlay(addr placing ' + ' from pos for 1);
        end if;
    end if;

    pos := position(' / ' in addr);
    if pos > 0 then
        return next overlay(addr placing ' ' from pos for 3);
    else
        pos := position('/' in addr);
        if pos > 0 then
            return next overlay(addr placing ' ' from pos for 1);
            return next overlay(addr placing ' / ' from pos for 1);
        end if;
    end if;

    return;
end
$$;

---
