-- TODO-db-201218 skip value_added_tax_percentages that expired_at

create function public.suggested_value_added_taxes(
  partner_company_id         uuid,
  document_type              public.document_type,
  booking_type               public.invoice_accounting_item_booking_type,
  value_added_tax_percentage float8 = null
) returns setof public.value_added_tax as $$
declare
  suggested_id uuid;
begin
  -- the database may decide to use CTEs order or not, the results are "random".
  -- only thing the DB guarantees the order for is the *outermost* query.
  -- keeping this in mind, we insert the suggestions in an array and then
  -- return the matching results in order of the array (preserving the order)
  for suggested_id in (
    select
      value_added_tax.id
    from public.accounting_item
      inner join public.value_added_tax on value_added_tax.id = accounting_item.value_added_tax_id
      left join public.value_added_tax_percentage on value_added_tax_percentage.id = accounting_item.value_added_tax_percentage_id
    where accounting_item.partner_company_id = suggested_value_added_taxes.partner_company_id
    and accounting_item.document_type = suggested_value_added_taxes.document_type
    and accounting_item.booking_type = suggested_value_added_taxes.booking_type
    and (suggested_value_added_taxes.value_added_tax_percentage is null
      or value_added_tax_percentage.percentage = suggested_value_added_taxes.value_added_tax_percentage)
    group by value_added_tax.id
    order by count(1) desc
    limit 5)
  loop
    return query (select * from public.value_added_tax where id = suggested_id);
  end loop;
end
$$ language plpgsql stable;
comment on function public.suggested_value_added_taxes is
'The top 5 suggested Value Added Taxes for the given partner, booking type and percentage. Sorted by relevance in descending order.';


create function public.invoice_suggested_value_added_taxes(
  invoice public.invoice
) returns setof public.value_added_tax as $$
  select suggested_value_added_taxes.*
  from
    public.document_category
      inner join public.document on document.category_id = document_category.id
        and document.id = invoice.document_id,
    public.suggested_value_added_taxes(
      invoice.partner_company_id,
      document_category.document_type,
      (case
        when (document_category.document_type = 'INCOMING_INVOICE' and (not invoice.credit_memo))
          or (document_category.document_type = 'OUTGOING_INVOICE' and invoice.credit_memo)
        then 'DEBIT'
        else 'CREDIT'
      end)::public.invoice_accounting_item_booking_type,
      nullif(coalesce(invoice.vat_percentages[1], invoice.vat_percent), 0)
    )
$$ language sql stable strict;
comment on function public.invoice_suggested_value_added_taxes is
'The top 5 suggested VATs for the given invoice. Sorted by relevance in descending order.';


create function public.suggested_general_ledger_accounts(
  partner_company_id             uuid,
  document_type                  public.document_type,
  booking_type                   public.invoice_accounting_item_booking_type,
  value_added_tax_id             uuid = null,
  value_added_tax_percentage_id  uuid = null,
  has_real_estate_object_with_id uuid = null
) returns setof public.general_ledger_account as $$
declare
  suggested_id uuid;
  suggested_ids uuid[] := '{}';
  suggestions_limit int := 5;
begin
  -- the database may decide to use CTEs order or not, the results are "random".
  -- only thing the DB guarantees the order for is the *outermost* query.
  -- keeping this in mind, we insert the suggestions in an array and then
  -- return the matching results in order of the array (preserving the order)
  for suggested_id in (
    select
      accounting_item.general_ledger_account_id
    from public.accounting_item
      inner join public.general_ledger_account on general_ledger_account.id = accounting_item.general_ledger_account_id
    where (
      has_real_estate_object_with_id is null
      or public.general_ledger_account_has_real_estate_object_by_id(general_ledger_account, has_real_estate_object_with_id)
    )
    and general_ledger_account.disabled_at is null
    and accounting_item.partner_company_id = suggested_general_ledger_accounts.partner_company_id
    and accounting_item.document_type = suggested_general_ledger_accounts.document_type
    and accounting_item.booking_type = suggested_general_ledger_accounts.booking_type
    group by
      accounting_item.general_ledger_account_id,
      accounting_item.value_added_tax_id,
      accounting_item.value_added_tax_percentage_id
    order by
      accounting_item.value_added_tax_id = suggested_general_ledger_accounts.value_added_tax_id desc nulls last, -- trues first, nulls last
      accounting_item.value_added_tax_percentage_id = suggested_general_ledger_accounts.value_added_tax_percentage_id desc nulls last, -- trues first, nulls last
      count(1) desc) -- amount of links
  loop
    if suggested_id = any(suggested_ids) then
      continue; -- duplicate suggestion
    end if;

    return query (select * from public.general_ledger_account where id = suggested_id);

    suggested_ids := array_append(suggested_ids, suggested_id);
    if array_length(suggested_ids, 1) >= suggestions_limit then
      return;
    end if;
  end loop;
end
$$ language plpgsql stable;
comment on function public.suggested_general_ledger_accounts is
'The top 5 suggested General Ledger Accounts for the given partner and booking type. Sorted by relevance in descending order.';


create function public.invoice_suggested_general_ledger_accounts(
  invoice public.invoice
) returns setof public.general_ledger_account as $$
  (
    -- prefer document_category accounting_items_general_ledger_account_id
    select suggested_general_ledger_account.*
    from public.document_category
      inner join public.document
      on document.category_id = document_category.id
      and document.id = invoice.document_id
      inner join public.general_ledger_account as suggested_general_ledger_account
      on suggested_general_ledger_account.id = document_category.accounting_items_general_ledger_account_id
  ) union all (
    -- otherwise use actual suggestions
    select suggested_general_ledger_accounts.*
    from
      public.document_category
        inner join public.document on document.category_id = document_category.id
          and document.id = invoice.document_id,
      public.suggested_general_ledger_accounts(
        invoice.partner_company_id,
        document_category.document_type,
        (case
          when (document_category.document_type = 'INCOMING_INVOICE' and (not invoice.credit_memo))
            or (document_category.document_type = 'OUTGOING_INVOICE' and invoice.credit_memo)
          then 'DEBIT'
          else 'CREDIT'
        end)::public.invoice_accounting_item_booking_type,
        null,
        null
      )
    where document_category.accounting_items_general_ledger_account_id is not null
  )
$$ language sql stable strict;
comment on function public.invoice_suggested_general_ledger_accounts is
'The top 5 suggested General Ledger Accounts for the given invoice. Sorted by relevance in descending order.';


create function public.suggested_invoice_accounting_item_title(
  partner_company_id uuid,
  invoice_accounting_item public.invoice_accounting_item
) returns text as $$
declare
  suggested_title text;
begin
  select
    accounting_item.title into suggested_title
  from public.accounting_item
  where accounting_item.partner_company_id = suggested_invoice_accounting_item_title.partner_company_id
  and accounting_item.general_ledger_account_id = invoice_accounting_item.general_ledger_account_id
  and accounting_item.booking_type = invoice_accounting_item.booking_type

  -- we filter by VATs only if there are some on the invoice_accounting_item
  and accounting_item.value_added_tax_id is not distinct from invoice_accounting_item.value_added_tax_id
  and (invoice_accounting_item.value_added_tax_percentage_id is null
    or accounting_item.value_added_tax_percentage_id = invoice_accounting_item.value_added_tax_percentage_id)

  order by accounting_item.updated_at desc
  limit 1;

  -- if there's no title to suggest, just use "(auto)"
  if suggested_title is null then
    return '(auto)';
  end if;

  -- if the suggested title does not end with "(auto)", append it
  if suggested_title not like '%(auto)' then
    return suggested_title || ' (auto)';
  end if;

  return suggested_title;
end
$$ language plpgsql stable strict;
comment on function public.suggested_invoice_accounting_item_title is 'Most recently used `title` matching the suggestion, suffixed with " (auto)".';


-- In case there is a cent (+-0.01) difference when summing the totals of the provided items:
--   - If all invoice acc. items are of the TOTAL amount type or are "net-only"s, don't do anything. The UI will show the difference and the user has to adjust manually.
--   - Otherwise, change the last acc. item in the array with NET amount type that's not "net-only" and:
--     - Change amount type to TOTAL
--     - Add/subtract 0.01 from the total amount (to offset the difference) and set it as the amount
create function private.adjust_cent_diff_in_invoice_accounting_items(
  invoice_accounting_items public.invoice_accounting_item[],
  invoice_total float8
) returns setof public.invoice_accounting_item as $$
declare
  item public.invoice_accounting_item;
  items_total_sum float8 := 0;
  last_net_amount_not_net_only_item_to_adjust public.invoice_accounting_item;
  diff float8 := 0;
begin
  foreach item in array invoice_accounting_items
  loop
    -- sum up the totals for checking if there's a cent difference
    items_total_sum := items_total_sum + public.invoice_accounting_item_total(item);

    -- store only the last NET amount type, not net-only, accounting item
    if item.amount_type = 'NET'
    and (item.value_added_tax_id is null
      or not (select net_only_amount from public.value_added_tax where value_added_tax.id = item.value_added_tax_id))
    then
      last_net_amount_not_net_only_item_to_adjust = item;
    end if;
  end loop;

  diff := round(invoice_total::numeric, 2) - round(items_total_sum::numeric, 2);
  if abs(diff) <> 0.01
  then
    -- there is no cent difference, or the difference is too big;
    -- or there's a cent difference but no NET amount type, not net-only, accounting item
    last_net_amount_not_net_only_item_to_adjust := null;
  end if;

  -- there's a cent difference, adjust the chosen item and return the rest
  foreach item in array invoice_accounting_items
  loop
    if item.id = last_net_amount_not_net_only_item_to_adjust.id
    then
      item.amount := public.invoice_accounting_item_total(item) + diff;
      item.amount_type = 'TOTAL';

      -- TODO: if we replace the updated by, we wont know the original updater. should we?
      -- item.updated_by = 'a77649b5-ff6d-4e87-a17c-23df3b2cad71'; -- Accounting Suggester
      item.updated_at = now();
    end if;

    return next item;
  end loop;
end
$$ language plpgsql stable strict;


create function private.adjust_cent_diff_in_invoice_accounting_items_on_invoice(
  invoice_document_id uuid
) returns void as $$
  update public.invoice_accounting_item
    set
        -- only amount type, amount and updated_at changes when adjusting
        amount_type=adjusted_invoice_accounting_item.amount_type,
        amount=adjusted_invoice_accounting_item.amount,
        updated_at=adjusted_invoice_accounting_item.updated_at -- will change only if updated
  from private.adjust_cent_diff_in_invoice_accounting_items(
    -- all invoice accounting items
    (select array_agg(invoice_accounting_item order by coalesce(invoice_accounting_item.updated_at, invoice_accounting_item.created_at) asc)
    from public.invoice_accounting_item
    where invoice_accounting_item.invoice_document_id = adjust_cent_diff_in_invoice_accounting_items_on_invoice.invoice_document_id),
    -- invoice total
    (select total
    from public.invoice
    where invoice.document_id = adjust_cent_diff_in_invoice_accounting_items_on_invoice.invoice_document_id)
  ) as adjusted_invoice_accounting_item
  where adjusted_invoice_accounting_item.id = invoice_accounting_item.id;
$$ language sql volatile strict;


-- These items are NOT inserted yet, they are just suggestions.
create function public.suggested_invoice_accounting_items(
  partner_company_id          uuid,
  document_type               public.document_type,
  booking_type                public.invoice_accounting_item_booking_type,
  invoice_total               float8,
  vat_groups                  public.invoice_vat_group[] = null,
  -- control the suggested accounting items
  default_value_added_tax_country country_code = null,
  suggested_general_ledger_account_id uuid = null,
  suggested_title trimmed_text = null
) returns setof public.invoice_accounting_item as $$
declare
  vat_group                   public.invoice_vat_group;
  suggested_vat_id            uuid;
  suggested_vat_percentage_id uuid;
  suggestion                  public.invoice_accounting_item;
  suggestions                 public.invoice_accounting_item[];
begin
  if invoice_total <= 0 then
    raise exception 'Invoice total must be positive and greater than zero (0).';
  end if;

  -- if the client cannot reclaim taxes, don't care about VATs at all
  if (select not tax_reclaimable
    from public.client_company
      inner join public.partner_company on partner_company.client_company_id = client_company.company_id
    where partner_company.id = suggested_invoice_accounting_items.partner_company_id)
  then

    if suggested_general_ledger_account_id is not null
    then
      suggestion.general_ledger_account_id = suggested_general_ledger_account_id;
    else
      select
        id into suggestion.general_ledger_account_id
      from public.suggested_general_ledger_accounts(
        partner_company_id,
        document_type,
        booking_type,
        null,
        null
      );
      if suggestion.general_ledger_account_id is null then
        -- general ledger account is required
        return;
      end if;
    end if;

    suggestion.id = uuid_generate_v4();
    suggestion.invoice_document_id = '00000000-0000-0000-0000-000000000000'; -- not known at this point
    suggestion.booking_type = booking_type;
    suggestion.amount_type = 'TOTAL';
    suggestion.amount = invoice_total;
    suggestion.created_by = 'a77649b5-ff6d-4e87-a17c-23df3b2cad71'; -- Accounting Suggester
    suggestion.updated_at = now();
    suggestion.created_at = now();

    suggestion.title := coalesce(suggested_title || ' (auto)', public.suggested_invoice_accounting_item_title(suggested_invoice_accounting_items.partner_company_id, suggestion));

    return next suggestion;
    return;
  end if;

  -- no vat group is available, or if all are 0 (or null) try using a net-only vat or the most commonly used vat but setting the TOTAL amount
  if coalesce(array_length(vat_groups, 1), 0) = 0
  or coalesce(array_length(vat_groups, 1), 0) = (
    select count(*)
    from unnest(vat_groups) as vg
    where (vg->>'vatRate')::float8 = 0
  )
  then
    -- we create the record field by field to avoid column order issues
    suggestion.id = uuid_generate_v4();
    suggestion.invoice_document_id = '00000000-0000-0000-0000-000000000000'; -- not known at this point

    select
      id into suggestion.general_ledger_account_id
    from public.suggested_general_ledger_accounts(
      partner_company_id,
      document_type,
      booking_type,
      suggested_vat_id,
      suggested_vat_percentage_id
    );
    if suggestion.general_ledger_account_id is null then
      -- general ledger account is required

      if suggested_general_ledger_account_id is null
      then
        -- required if there is no preset suggested
        return;
      end if;

      -- otherwise use the suggested preset
      suggestion.general_ledger_account_id = suggested_general_ledger_account_id;
    end if;

    -- most used vat for the suggested general ledger, use it
    with suggested_vat as (
      select
        value_added_tax.id as value_added_tax_id,
        value_added_tax_percentage.id as percentage_id
      from public.accounting_item
        inner join public.value_added_tax on value_added_tax.id = accounting_item.value_added_tax_id
        left join public.value_added_tax_percentage on value_added_tax_percentage.id = accounting_item.value_added_tax_percentage_id
      where accounting_item.partner_company_id = suggested_invoice_accounting_items.partner_company_id
      and accounting_item.general_ledger_account_id = suggestion.general_ledger_account_id
      and accounting_item.booking_type = suggested_invoice_accounting_items.booking_type
      group by
        value_added_tax.id,
        value_added_tax_percentage.id
      order by count(1) desc
      limit 1
    )
    select value_added_tax_id, percentage_id
    into suggested_vat_id, suggested_vat_percentage_id
    from suggested_vat;
    if suggested_vat_id is null then
      -- there is no suggested VAT, check if there are matching acc. items without a VAT and generate a VAT-less acc. item
      if not exists (
        select from public.accounting_item
        where accounting_item.partner_company_id = suggested_invoice_accounting_items.partner_company_id
        and accounting_item.general_ledger_account_id = suggestion.general_ledger_account_id
        and accounting_item.booking_type = suggested_invoice_accounting_items.booking_type
        and accounting_item.value_added_tax_id is null
      ) then

        if suggested_general_ledger_account_id is null
        or suggested_title is null
        then
          -- there are NO matching VAT-less acc. items and there are no presets, nothing to generate
          return;
        end if;

      end if;

      -- there are matching VAT-less acc. items or there are presets both for GLA and the title
    end if;

    suggestion.booking_type = booking_type;
    suggestion.amount_type = 'NET';
    if (select not net_only_amount from public.value_added_tax where id = suggested_vat_id)
    then
      -- there is a VAT and it's not a net_only_amount, set the amount type to TOTAL (because there's no vat groups available)
      suggestion.amount_type = 'TOTAL';
    end if;
    suggestion.amount = invoice_total; -- because the vat is net_only_amount
    suggestion.value_added_tax_id = suggested_vat_id;
    suggestion.value_added_tax_percentage_id = suggested_vat_percentage_id;
    suggestion.created_by = 'a77649b5-ff6d-4e87-a17c-23df3b2cad71'; -- Accounting Suggester
    suggestion.updated_at = now();
    suggestion.created_at = now();

    suggestion.title := coalesce(suggested_title || ' (auto)', public.suggested_invoice_accounting_item_title(suggested_invoice_accounting_items.partner_company_id, suggestion));

    -- overwrite the suggested general ledger id
    -- we do this after using the original suggestion making sure that correct VAT as well as the title will also be suggested
    if suggested_general_ledger_account_id is not null
    then
      suggestion.general_ledger_account_id = suggested_general_ledger_account_id;
    end if;

    return next suggestion;
    return;
  end if;

  -- generate invoice accounting item suggestions for each vat group
  foreach vat_group in array vat_groups loop
    if (vat_group->>'netAmount')::float8 < 0
    or (vat_group->>'vatAmount')::float8 < 0
    then
      -- TODO: handle negative amounts by switching the booking type (can we?)
      continue;
    end if;

    select
      id into suggested_vat_id
    from public.suggested_value_added_taxes(
      partner_company_id,
      document_type,
      booking_type,
      (vat_group->>'vatRate')::float8 -- if tax percent is not in the database, no suggestion will be made
    )
    limit 1;
    if suggested_vat_id is not null then
      select
        id into suggested_vat_percentage_id
      from public.value_added_tax_percentage
      where value_added_tax_id = suggested_vat_id
      and percentage = (vat_group->>'vatRate')::float8;
    else
      suggested_vat_percentage_id := null;
    end if;
    if suggested_vat_percentage_id is null
    and suggested_general_ledger_account_id is not null
    and suggested_title is not null
    and default_value_added_tax_country is not null
    then
      -- both GLA and title presets are available even if there is no percentage,
      -- try using the country defaults for the given percentage
      select
        value_added_tax.id, value_added_tax_percentage.id into suggested_vat_id, suggested_vat_percentage_id
      from
        public.value_added_tax_percentage
          inner join public.value_added_tax on value_added_tax.id = value_added_tax_percentage.value_added_tax_id
      where value_added_tax.country = default_value_added_tax_country
      and (
        -- UST (Output VAT)
        case when document_type = 'OUTGOING_INVOICE'
        then value_added_tax."type" = 'PAYABLE'
        -- VST (Input VAT)
        when document_type = 'INCOMING_INVOICE'
        then value_added_tax."type" = 'RECLAIMABLE'
        -- if the document type is not supported, no suggestions
        else false
        end
      )
      and "percentage" = (vat_group->>'vatRate')::float8
      and value_added_tax.default;
    end if;
    if suggested_vat_percentage_id is null then
      -- no matched tax percentage, percentage is invalid or suggestions are unavailable, and there are no presets
      continue;
    end if;

    -- we create the record field by field to avoid column order issues
    suggestion.id = uuid_generate_v4();
    suggestion.invoice_document_id = '00000000-0000-0000-0000-000000000000'; -- not known at this point

    if suggested_general_ledger_account_id is not null
    then
      suggestion.general_ledger_account_id = suggested_general_ledger_account_id;
    else
      select
        id into suggestion.general_ledger_account_id
      from public.suggested_general_ledger_accounts(
        partner_company_id,
        document_type,
        booking_type,
        suggested_vat_id,
        suggested_vat_percentage_id
      );
      if suggestion.general_ledger_account_id is null then
        -- general ledger account is required
        continue;
      end if;
    end if;

    suggestion.booking_type = booking_type;
    suggestion.amount_type = 'NET'; -- always NET because some VATs can be net only
    if vat_group->>'netAmount' is not null
    then
      suggestion.amount = round((vat_group->>'netAmount')::numeric, 2);
    else
      -- if the net amount is unavailable, try figuring it out
      suggestion.amount = (vat_group->>'vatAmount')::float8 / ((vat_group->>'vatRate')::float8 / 100);
    end if;
    if suggestion.amount is null
    then
      -- no amount, no suggestion
      continue;
    end if;
    suggestion.value_added_tax_id = suggested_vat_id;
    suggestion.value_added_tax_percentage_id = suggested_vat_percentage_id;
    suggestion.created_by = 'a77649b5-ff6d-4e87-a17c-23df3b2cad71'; -- Accounting Suggester
    suggestion.updated_at = now();
    suggestion.created_at = now();

    suggestion.title = coalesce(suggested_title || ' (auto)', public.suggested_invoice_accounting_item_title(suggested_invoice_accounting_items.partner_company_id, suggestion));

    suggestions := array_append(suggestions, suggestion);
  end loop;

  return query (
    select *
    from private.adjust_cent_diff_in_invoice_accounting_items(
      suggestions,
      invoice_total));
end;
$$ language plpgsql stable;
comment on function public.suggested_invoice_accounting_items is
'Suggested complete Invoice Accounting Items for the given argument details. BEWARE: These items are NOT inserted yet, they are just suggestions.';

create function public.generate_invoice_accounting_items(
  invoice_document_id         uuid,
  vat_groups                  public.invoice_vat_group[] = null,
  created_at                  timestamptz = now()
) returns setof public.invoice_accounting_item as $$
declare
  document_client_company_id uuid;
  category_document_type public.document_type;
  invoice_partner_location_country country_code;
  default_value_added_tax_country country_code;
  suggested_general_ledger_account_id uuid;
  suggested_title trimmed_text;
begin
  if exists (select from public.invoice_accounting_item
    where invoice_accounting_item.invoice_document_id = generate_invoice_accounting_items.invoice_document_id)
  then
    raise exception 'Invoice already has accounting items.';
  end if;
  if (select not public.has_client_company_an_accounting_system(document.client_company_id)
    from public.document
    where document.id = invoice_document_id)
  then
    raise exception 'Invoice''s client has no accounting system.';
  end if;

  -- skip generating if necessary values are not confirmed
  if (
    select
      total_confirmed_by is null
      and net_confirmed_by is null
    from public.invoice
    where invoice.document_id = invoice_document_id
  )
  then
    return;
  end if;

  -- control the generated accounting items
  select
    document_category.client_company_id,
    document_category.document_type,
    company_location.country,
    document_category.accounting_items_general_ledger_account_id,
    document_category.accounting_items_title
  into
    document_client_company_id,
    category_document_type,
    invoice_partner_location_country,
    suggested_general_ledger_account_id,
    suggested_title
  from
    public.invoice
      inner join (public.document
        inner join public.document_category on document_category.id = document.category_id)
      on document.id = invoice.document_id
      left join public.company_location on company_location.id = invoice.partner_company_location_id
  where invoice.document_id = generate_invoice_accounting_items.invoice_document_id;
  if public.is_company_feature_active('EU_OSS', document_client_company_id)
  and category_document_type = 'OUTGOING_INVOICE'
  then
    -- EU OSS is active, this client supports the VAT One Stop Shop and should therefore
    -- use the VAT country of the invoice partner on OUTGOING INVOICES and the related branch details
    -- see more https://app.asana.com/1/201241326692307/project/1138407765982241/task/1210197186024878?focus=true
    --
    -- even if there is no country selected on the invoice partner, we still want to arrive here in order
    -- to skip the "else" part below because we always want to use the branch details or generate nothing
    select
      general_ledger_account_id,
      invoice_accounting_item_title
    into
      suggested_general_ledger_account_id,
      suggested_title
    from public.client_company_oss_branch
    where client_company_oss_branch.client_company_id = document_client_company_id
    and client_company_oss_branch.country = invoice_partner_location_country;

    -- use the invoice partner's country as the default VAT country in case suggestions are not available
    default_value_added_tax_country = invoice_partner_location_country;
  else
    -- EU OSS is not active, use the main company location's country to determine the default VAT country
    select company_location.country into default_value_added_tax_country
    from public.client_company
      inner join public.company_location on company_location.company_id = client_company.company_id
    where client_company.company_id = document_client_company_id
    and company_location.main;
  end if;

  -- insert suggestions
  insert into public.invoice_accounting_item (
      id,
      invoice_document_id,
      general_ledger_account_id,
      title,
      booking_type,
      amount_type,
      amount,
      value_added_tax_id,
      value_added_tax_percentage_id,
      created_by,
      updated_at,
      created_at
    )
    select
      acc_item.id,
      invoice.document_id,
      acc_item.general_ledger_account_id,
      acc_item.title,
      acc_item.booking_type,
      acc_item.amount_type,
      acc_item.amount,
      acc_item.value_added_tax_id,
      acc_item.value_added_tax_percentage_id,
      acc_item.created_by,
      acc_item.updated_at,
      acc_item.created_at
    from
      public.invoice
        inner join (public.document
          inner join public.document_category on document_category.id = document.category_id)
        on document.id = invoice.document_id,
      public.suggested_invoice_accounting_items(
        partner_company_id=>invoice.partner_company_id,
        document_type=>category_document_type,
        booking_type=>(case
          when (document_category.document_type = 'INCOMING_INVOICE' and (not invoice.credit_memo))
            or (document_category.document_type = 'OUTGOING_INVOICE' and invoice.credit_memo)
          then 'DEBIT'
          else 'CREDIT'
        end)::public.invoice_accounting_item_booking_type,
        invoice_total=>invoice.total,
        vat_groups=>vat_groups,
        default_value_added_tax_country=>default_value_added_tax_country,
        suggested_general_ledger_account_id=>suggested_general_ledger_account_id,
        suggested_title=>suggested_title
      ) as acc_item
    where invoice.document_id = generate_invoice_accounting_items.invoice_document_id;

  -- if the remaining amount is zero, update the invoice's net
  if (select public.invoice_accounting_items_remaining_amount_is_zero(invoice)
  from public.invoice
  where invoice.document_id = generate_invoice_accounting_items.invoice_document_id)
  then
    update public.invoice set
      net=(select abs(private.signed_invoice_accounting_items_net_sum(array_agg(invoice_accounting_item)))
        from public.invoice_accounting_item
        where invoice_accounting_item.invoice_document_id = invoice.document_id),
      net_confirmed_by='a77649b5-ff6d-4e87-a17c-23df3b2cad71', -- Accounting Suggester
      net_confirmed_at=now(),
      updated_at=now()
    where invoice.document_id = generate_invoice_accounting_items.invoice_document_id;
  end if;

  return query
    select * from public.invoice_accounting_item
    where invoice_accounting_item.invoice_document_id = generate_invoice_accounting_items.invoice_document_id;
end;
$$ language plpgsql volatile;
