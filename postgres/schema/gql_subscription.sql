create function private.gql_subscription() returns trigger as $$
declare
  v_process_new bool = (TG_OP = 'INSERT' OR TG_OP = 'UPDATE');
  v_process_old bool = (TG_OP = 'UPDATE' OR TG_OP = 'DELETE');
  v_event text = TG_ARGV[0];
  v_topic_template text = TG_ARGV[1];
  v_attributes_offset int = 2; -- first 2 arguments are reserved
  v_attributes_count int = TG_NARGS - v_attributes_offset;
  v_attributes_i int = 0;
  v_attribute text;
  v_record record;
  v_sub text;
  v_subs text[];
  v_topic text;
  v_i int = 0;
  v_last_topic text;
begin
  -- On UPDATE sometimes topic may be changed for NEW record,
  -- so we need notify to both topics NEW and OLD.
  for v_i in 0..1 loop
    if (v_i = 0) and v_process_new is true then
      v_record = new;
    elsif (v_i = 1) and v_process_old is true then
      v_record = old;
    else
      continue;
    end if;

    v_topic = v_topic_template;
    if v_attributes_count > 0 then
      for v_attributes_i in 0..v_attributes_count loop
        v_attribute = TG_ARGV[v_attributes_i + v_attributes_offset];
        if v_attribute is not null then
          execute 'select $1.' || quote_ident(v_attribute)
            using v_record
            into v_sub;
          if v_sub is not null then
            v_topic = replace(v_topic, '$' || v_attributes_i + 1, v_sub);
            v_subs = array_append(v_subs, v_sub);
          end if;
        end if;
      end loop;
    end if;

    if v_topic is distinct from v_last_topic then
      -- This if statement prevents us from triggering the same notification twice
      v_last_topic = v_topic;
      perform pg_notify(v_topic, json_build_object(
        'event', v_event,
        'subjects', v_subs
      )::text);
    end if;
  end loop;
  return v_record;
end;
$$ language plpgsql volatile set search_path from current;
