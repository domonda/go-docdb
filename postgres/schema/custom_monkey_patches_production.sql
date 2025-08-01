-- this contains a collection of custom sql functions that are not part of the schema
-- but are deployed to the production database for the aim of figuring things out

-- https://app.asana.com/1/201241326692307/project/1138407765982241/task/1210123855182912?focus=true
create function private.custom_monkey_patch_payment_preset_on_delete()
returns trigger as $$
begin
  raise exception 'Deleting this payment preset is not allowed. This action has been reported.';
end
$$ language plpgsql;
create trigger custom_monkey_patch_payment_preset_on_delete_trigger
  before delete on public.partner_company_payment_preset
  for each row
  when (old.partner_company_id = '9ff93e5c-e644-43e6-85d4-a4f20a0a92e2')
  execute function private.custom_monkey_patch_payment_preset_on_delete();
