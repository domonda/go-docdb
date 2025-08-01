CREATE FUNCTION rule.trigger() RETURNS trigger AS
$$
DECLARE
    init_current_user_id    text = current_setting('current.user_id', true);
    init_current_user_type  text = current_setting('current.user_type', true);
    -- trigger table --
    trigger_table text := (TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME);
    -- trigger --
    triggs rule.action_reaction_trigger[] = '{}';
    -- related client company --
    client_company_id uuid;
    -- actions/reactions --
    actions_reactions rule.action_reaction[];
    action_reaction   rule.action_reaction;
    action            rule.action;
    should_exit       boolean := false;
    -- conditionals checks --
    -- document_category
    document_category_ok   boolean;
    curr_document_category public.document_category;
    -- invoice
    invoice_ok   boolean;
    curr_invoice public.invoice;
    next_invoice public.invoice;
    -- document
    document_ok         boolean;
    document_macro_ok   boolean;
    curr_document       public.document;
    next_document       public.document;
BEGIN
    if private.current_setting_flag('current.disable_rule_trigger')
    then
        -- for example: when cloning a company, dont trigger rules again
        return null;
    end if;

    -- extract rows and populate records
    CASE trigger_table
        WHEN 'public.document' THEN

            -- document
            curr_document := NEW;

            -- document_category
            SELECT
                * INTO curr_document_category
            FROM public.document_category WHERE id = curr_document.category_id;

            -- invoice
            SELECT
                * INTO curr_invoice
            FROM public.invoice WHERE document_id = curr_document.id;

        WHEN 'public.invoice' THEN

            -- invoice
            curr_invoice := NEW;

            -- document
            SELECT
                * INTO curr_document
            FROM public.document WHERE id = curr_invoice.document_id;

            -- document_category
            SELECT
                * INTO curr_document_category
            FROM public.document_category WHERE id = curr_document.category_id;

        WHEN 'public.document_approval' THEN

            -- document
            select
                d.* into curr_document
            from public.document as d
                inner join public.document_approval_request as drr on drr.document_id = d.id
            where drr.id = NEW.request_id;

            -- document_category
            select
                * into curr_document_category
            from public.document_category where id = curr_document.category_id;

            -- invoice
            select
                * into curr_invoice
            from public.invoice where document_id = curr_document.id;

        WHEN 'rule.document_ready' THEN

            -- bail out if the document is not ready
            IF NOT NEW.is_ready THEN
                RETURN null;
            END IF;

            -- document
            select
                * into curr_document
            from public.document
            where id = NEW.document_id;

            -- document_category
            select
                * into curr_document_category
            from public.document_category where id = curr_document.category_id;

            -- invoice
            select
                * into curr_invoice
            from public.invoice where document_id = curr_document.id;

        WHEN 'public.invoice_cost_center' THEN

            -- document
            select * into curr_document
            from public.document
            where id = NEW.document_id;

            -- document_category
            select
                * into curr_document_category
            from public.document_category where id = curr_document.category_id;

            -- invoice
            select
                * into curr_invoice
            from public.invoice where document_id = curr_document.id;

        WHEN 'public.invoice_accounting_item' THEN

            -- document
            select * into curr_document
            from public.document
            where id = NEW.invoice_document_id;

            -- document_category
            select
                * into curr_document_category
            from public.document_category where id = curr_document.category_id;

            -- invoice
            select
                * into curr_invoice
            from public.invoice where document_id = curr_document.id;

        WHEN
          'public.document_bank_transaction',
          'public.document_credit_card_transaction',
          'public.document_cash_transaction'
        THEN

            -- document
            select * into curr_document
            from public.document
            where id = NEW.document_id;

            -- document_category
            select
                * into curr_document_category
            from public.document_category where id = curr_document.category_id;

            -- invoice
            select
                * into curr_invoice
            from public.invoice where document_id = curr_document.id;

        WHEN 'public.document_real_estate_object' THEN

            -- document
            select * into curr_document
            from public.document
            where id = NEW.document_id;

            -- document_category
            select
                * into curr_document_category
            from public.document_category where id = curr_document.category_id;

            -- invoice
            select
                * into curr_invoice
            from public.invoice where document_id = curr_document.id;

        WHEN 'public.document_tag' THEN

            -- document
            select * into curr_document
            from public.document
            where id = NEW.document_id;

            -- document_category
            select
                * into curr_document_category
            from public.document_category where id = curr_document.category_id;

            -- invoice
            select
                * into curr_invoice
            from public.invoice where document_id = curr_document.id;

        WHEN 'public.bank_payment' THEN

            -- document
            select * into curr_document
            from public.document
            where id = NEW.document_id;

            -- document_category
            select
                * into curr_document_category
            from public.document_category where id = curr_document.category_id;

            -- invoice
            select
                * into curr_invoice
            from public.invoice where document_id = curr_document.id;

        ELSE

            raise exception 'Rule trigger not implemented for % table', trigger_table;

    END CASE;

    -- detect trigger
    CASE
    WHEN TG_NAME = 'rule_relevant_document_update_trigger'
    THEN
        -- we must separate to time access to OLD and NEW
        IF OLD.workflow_step_id IS DISTINCT FROM NEW.workflow_step_id
        THEN
            triggs := array_append(triggs, 'DOCUMENT_WORKFLOW_CHANGED');
        END IF;
        triggs := array_append(triggs, 'DOCUMENT_CHANGED');

    WHEN TG_NAME = 'rule_invoice_update_trigger'
        OR TG_NAME = 'rule_invoice_insert_trigger'
    THEN
        triggs := array_append(triggs, 'DOCUMENT_CHANGED');

    WHEN TG_NAME = 'rule_document_approval_insert_trigger' -- approval fulfilled
    THEN
        IF NEW.next_request_id IS NULL AND NOT NEW.canceled
        THEN
            -- approved
            triggs := array_append(triggs, 'DOCUMENT_APPROVAL');
            IF (select document_approval_request.approver_id is not null
                from public.document_approval_request
                where document_approval_request.id = NEW.request_id)
            THEN
                triggs := array_append(triggs, 'DOCUMENT_APPROVAL_DIRECT');
            ELSIF (select document_approval_request.user_group_id is not null
                from public.document_approval_request
                where document_approval_request.id = NEW.request_id)
            THEN
                triggs := array_append(triggs, 'DOCUMENT_APPROVAL_USER_GROUP');
            ELSE
                triggs := array_append(triggs, 'DOCUMENT_APPROVAL_GROUP');
            END IF;
        ELSIF NEW.next_request_id IS NOT NULL
        THEN
            -- rejected
            triggs := array_append(triggs, 'DOCUMENT_REJECTION');
            IF (select document_approval_request.approver_id is not null
                from public.document_approval_request
                where document_approval_request.id = NEW.request_id)
            THEN
                triggs := array_append(triggs, 'DOCUMENT_REJECTION_DIRECT');
            ELSE
                triggs := array_append(triggs, 'DOCUMENT_REJECTION_GROUP');
            END IF;
        ELSIF NEW.canceled
        THEN
            -- canceled
            if not 'SYSTEM' in (select "type" from public.user where "user".id = NEW.approver_id)
            then
                triggs := array_append(triggs, 'DOCUMENT_APPROVAL_USER_CANCELLATION');
            end if;
            triggs := array_append(triggs, 'DOCUMENT_APPROVAL_CANCELLATION');
        ELSE
            -- should not happen
            raise exception 'Unknown document approval state';
        END IF;

        -- whatever happens in terms of approvals, a state can be reached where all approvals are approved
        -- for example: 2 approval requests, 1 gets approved and the other canceled - canceling the other
        -- approval leaves the document approved
        IF (
            case when public.is_client_company_feature_active(curr_document.client_company_id, 'APPROVED_WITHOUT_VERIFIERS')
            then public.is_document_approved_without_verifiers(curr_document.id)
            else public.is_document_approved(curr_document.id)
            end
        )
        THEN
            triggs := array_append(triggs, 'DOCUMENT_APPROVAL_ALL');
        END IF;

        IF (select
                (
                    -- all direct requests
                    select nullif(count(1), 0) from public.document_approval_request
                    where document_approval_request.document_id = curr_document.id
                    and document_approval_request.approver_id is not null
                    and not exists (select from public.document_approval
                        where document_approval.request_id = document_approval_request.id
                        and document_approval.canceled)
                ) = (
                    -- fulfilled direct requests
                    count(1)
                )
            from public.document_approval
                inner join public.document_approval_request on document_approval_request.id = document_approval.request_id
            where document_approval_request.document_id = curr_document.id
            and document_approval_request.approver_id is not null
            and not document_approval.canceled
        )
        THEN
            triggs := array_append(triggs, 'DOCUMENT_APPROVAL_ALL_DIRECT');
        END IF;

        IF (select
                (
                    -- all user group requests
                    select nullif(count(1), 0) from public.document_approval_request
                    where document_approval_request.document_id = curr_document.id
                    and document_approval_request.user_group_id is not null
                    and not exists (select from public.document_approval
                        where document_approval.request_id = document_approval_request.id
                        and document_approval.canceled)
                ) = (
                    -- fulfilled user group requests
                    count(1)
                )
            from public.document_approval
                inner join public.document_approval_request on document_approval_request.id = document_approval.request_id
            where document_approval_request.document_id = curr_document.id
            and document_approval_request.user_group_id is not null
            and not document_approval.canceled
        )
        THEN
            triggs := array_append(triggs, 'DOCUMENT_APPROVAL_ALL_USER_GROUP');
        END IF;

    WHEN TG_NAME in (
        'rule_document_bank_matched_trigger',
        'rule_document_credit_card_matched_trigger',
        'rule_document_cash_matched_trigger',
        'rule_document_real_estate_object_insert_trigger',
        'rule_document_real_estate_object_update_trigger',
        'rule_document_tag_insert_trigger',
        'rule_bank_payment_insert_or_update_trigger'
    )
    THEN
        triggs := array_append(triggs, 'DOCUMENT_CHANGED');

    WHEN TG_NAME = 'rule_document_became_ready_trigger'
    THEN
        IF (
            -- the category change is done by Go code and involves multiple operations
            -- (like checkout, extraction, etc.) so we cannot directly add a postgres
            -- trigger for it, we need to derive it.
            --
            -- document_ready.is_ready change operations only happen when there are document
            -- changes that need the rules to be disabled. things like extraction and category change
            -- fall into this category. this means that between 2 document_ready.is_ready changes
            -- the document underwent a single opration. it is therefore safe to assume:
            --
            -- if there is a document_log CATEGORY_CHANGED inserted between the last
            -- document_ready.is_ready, and this triggering document_ready (which is_ready because
            -- of the trigger), it was a category change that happened.
            with document_ready_hold as (
                select
                    last_ready.created_at as "from",
                    document_ready.created_at as "to"
                from rule.document_ready
                left join lateral (
                    select last_ready.*
                    from rule.document_ready as last_ready
                    where last_ready.document_id = document_ready.document_id
                    and last_ready.id <> document_ready.id
                    -- sort from newest to oldest and take the first ready one (which is the last ready before this document_ready)
                    and last_ready.created_at <= document_ready.created_at
                    and last_ready.is_ready
                    order by last_ready.created_at desc
                    limit 1
                ) as last_ready on true
                where document_ready.id = NEW.id
            )
            select exists (
                select from public.document_log, document_ready_hold
                where document_log.document_id = NEW.document_id
                and document_log."type" = 'CATEGORY_CHANGED'
                and document_log.created_at >= document_ready_hold."from"
                and document_log.created_at <= document_ready_hold."to"
            )
        ) THEN
            triggs := array_append(triggs, 'DOCUMENT_CATEGORY_CHANGED');
        END IF;

    ELSE
        triggs := '{}';

    END CASE;

    -- bail out if the document is not visual
    IF NOT public.document_is_visual(curr_document)
    THEN
        RETURN null;
    END IF;

    -- bail out if the document is not ready
    IF NOT rule.is_document_ready(curr_document.id)
    THEN
        RETURN null;
    END IF;

    -- populate client_company_id
    client_company_id := curr_document.client_company_id;

    -- find related actions_reactions in order (check function)
    SELECT
        array_agg(ar) INTO actions_reactions
    FROM rule.actions_reactions_by_client_company_id(client_company_id) AS ar
    WHERE NOT ar.disabled;

    -- nothing else to do if there are no relevant actions_reactions
    IF (coalesce(array_length(actions_reactions, 1), 0) = 0)
    THEN

        RETURN null;

    END IF;

    FOREACH action_reaction IN ARRAY actions_reactions LOOP
        should_exit := false;

        -- TODO what happens when triggers are called recursively? (due to rules triggering other rules)
        IF action_reaction."trigger" <> 'ALWAYS'
        AND action_reaction."trigger" <> 'ONCE'
        AND NOT (action_reaction."trigger" = any(triggs))
        THEN
            CONTINUE;
        END IF;

        -- we check the ONCE trigger in each reaction separately, and not
        -- here, because a single action_reaction might have multiple reactions

        -- find action
        SELECT * INTO action FROM rule.action WHERE id = action_reaction.action_id;

        -- check document category conditions
        document_category_ok = rule.document_category_check(
            action,
            curr_document_category
        );

        -- check document conditions
        document_ok = rule.document_check(
            action,
            curr_document
        );

        -- check document macro conditions
        document_macro_ok = rule.document_macro_check(
            action,
            curr_document
        );

        -- check invoice conditions
        invoice_ok = rule.invoice_check(
            action,
            curr_invoice
        );

        -- if all checks are null this means there are no related conditions, therefore continue loop
        IF (
            document_category_ok IS NULL
        ) AND (
            document_ok IS NULL
        ) AND (
            document_macro_ok IS NULL
        ) AND (
            invoice_ok IS NULL
        ) THEN
            CONTINUE;
        END IF;

        -- if all checks passed, do action-reaction
            -- here we cascade to `true` because when the check is `null` it means there are no related conditionals
        IF (
            coalesce(document_category_ok, true)
        ) AND (
            coalesce(document_ok, true)
        ) AND (
            coalesce(document_macro_ok, true)
        ) AND (
            coalesce(invoice_ok, true)
        ) THEN

            -- document action-reaction only if document is available
            IF NOT (curr_document IS NULL) THEN

                -- document distinct action-reaction
                next_document := rule.do_document_action_reaction(action_reaction, curr_document);
                IF curr_document.workflow_step_id IS DISTINCT FROM next_document.workflow_step_id
                THEN

                    -- impersonate system rule user for automatic logs
                    perform set_config('current.user_type', 'SYSTEM', true);
                    perform set_config('current.user_id', 'bde919f0-3e23-4bfa-81f1-abff4f45fb51', true);

                    UPDATE public.document
                        SET
                            workflow_step_id=next_document.workflow_step_id
                    WHERE (id = next_document.id);

                    -- reset user
                    perform set_config('current.user_type', init_current_user_type , true);
                    perform set_config('current.user_id', init_current_user_id, true);

                    -- we queue an exit here because the update statement from above will
                    -- trigger this function again and it will continue the chain until no
                    -- updates are left to be made
                    --
                    -- we dont exit immediately because of reactions with multiple changes
                    -- if you have a setup like:
                    --   IF document is in WF1 -> DO push to WF2 and issue approval
                    should_exit := true;

                END IF;

            END IF;

            -- invoice action-reaction only if invoice is available
            IF NOT (curr_invoice IS NULL) THEN

                -- invoice distinct action-reaction
                next_invoice := rule.do_invoice_action_reaction(action_reaction, curr_invoice);
                IF curr_invoice.currency IS DISTINCT FROM next_invoice.currency
                    or curr_invoice.payment_status IS DISTINCT FROM next_invoice.payment_status
                    or curr_invoice.due_date IS DISTINCT FROM next_invoice.due_date
                    or curr_invoice.discount_percent IS DISTINCT FROM next_invoice.discount_percent
                    or curr_invoice.discount_until IS DISTINCT FROM next_invoice.discount_until
                    or curr_invoice.iban IS DISTINCT FROM next_invoice.iban
                    or curr_invoice.bic IS DISTINCT FROM next_invoice.bic
                THEN

                    -- impersonate system rule user for automatic logs
                    perform set_config('current.user_type', 'SYSTEM', true);
                    perform set_config('current.user_id', 'bde919f0-3e23-4bfa-81f1-abff4f45fb51', true);

                    UPDATE public.invoice
                    SET
                        currency=next_invoice.currency,
                        currency_confirmed_by=next_invoice.currency_confirmed_by,
                        currency_confirmed_at=next_invoice.currency_confirmed_at,
                        payment_status=next_invoice.payment_status,
                        payment_status_confirmed_by=next_invoice.payment_status_confirmed_by,
                        payment_status_confirmed_at=next_invoice.payment_status_confirmed_at,
                        due_date=next_invoice.due_date,
                        due_date_confirmed_by=next_invoice.due_date_confirmed_by,
                        due_date_confirmed_at=next_invoice.due_date_confirmed_at,
                        discount_percent=next_invoice.discount_percent,
                        discount_percent_confirmed_by=next_invoice.discount_percent_confirmed_by,
                        discount_percent_confirmed_at=next_invoice.discount_percent_confirmed_at,
                        discount_until=next_invoice.discount_until,
                        discount_until_confirmed_by=next_invoice.discount_until_confirmed_by,
                        discount_until_confirmed_at=next_invoice.discount_until_confirmed_at,
                        iban=next_invoice.iban,
                        iban_confirmed_by=next_invoice.iban_confirmed_by,
                        iban_confirmed_at=next_invoice.iban_confirmed_at,
                        bic=next_invoice.bic,
                        bic_confirmed_by=next_invoice.bic_confirmed_by,
                        bic_confirmed_at=next_invoice.bic_confirmed_at,
                        updated_at=now()
                    WHERE (document_id = next_invoice.document_id);

                    -- reset user
                    perform set_config('current.user_type', init_current_user_type , true);
                    perform set_config('current.user_id', init_current_user_id, true);

                    -- we queue an exit here because the update statement from above will
                    -- trigger this function again and it will continue the chain until no
                    -- updates are left to be made
                    --
                    -- we dont exit immediately because of reactions with multiple changes
                    -- if you have a setup like:
                    --   IF document is in WF1 -> DO push to WF2 and issue approval
                    should_exit := true;

                END IF;

            END IF;

            -- side-effects

            -- send notification
            IF NOT (next_document IS NULL) THEN

              PERFORM rule.do_send_notification_action_reaction(
                  action_reaction,
                  next_document
              );

            END IF;

            -- cancel document approval requests only if document is available
            -- do it before the approval requests reactions (and macros) to not cancel new approval requests
            IF NOT (next_document IS NULL) THEN

              PERFORM rule.do_cancel_document_approval_request_action_reaction(
                  action_reaction,
                  next_document
              );

            END IF;

            -- document release request only if document is available
            IF NOT (next_document IS NULL) THEN

              PERFORM rule.do_document_approval_request_action_reaction(
                  action_reaction,
                  next_document
              );

            END IF;

            -- tag document only if document is available
            IF NOT (next_document IS NULL) THEN

              PERFORM rule.do_document_tag_action_reaction(
                  action_reaction,
                  next_document
              );

            END IF;

            -- execute the designated document macros, only if the document is available
            -- TODO: what happens after the macro's been executed? should exit? recursive triggers are ok?
            IF NOT (next_document IS NULL) THEN

              PERFORM rule.do_document_macro_action_reaction(
                  action_reaction,
                  next_document
              );

            END IF;

            -- send document workflow changed mail
            IF (
                -- triggered because the document became ready with a workflow set
                trigger_table = 'rule.document_ready'
                AND next_document.workflow_step_id IS NOT NULL
            ) THEN

                PERFORM rule.do_send_mail_document_workflow_changed_action_reaction(
                    action_reaction,
                    next_document
                );

            END IF;

            IF trigger_table = 'public.document' THEN
              -- this if is intentionally nested due to NEW and OLD usage
              IF (
                  -- if the document is freshly inserted with a workflow step
                  (TG_OP = 'INSERT') AND (NEW.workflow_step_id IS NOT NULL)
              ) OR (
                  -- if the document has the workflow step changed
                  (TG_OP = 'UPDATE') AND (OLD.workflow_step_id IS DISTINCT FROM NEW.workflow_step_id)
              ) THEN

                PERFORM rule.do_send_mail_document_workflow_changed_action_reaction(
                    action_reaction,
                    next_document
                );

              END IF;
            END IF;

            -- stop if exit is queued because the trigger will be recursively called again
            IF should_exit THEN
              RETURN null;
            END IF;
        END IF;

    END LOOP;

    RETURN null;
END
$$
LANGUAGE plpgsql;

COMMENT ON FUNCTION rule.trigger IS '@omit';

----

create trigger rule_relevant_document_update_trigger
    after update on public.document
    for each row
    when (
        (old.category_id is distinct from new.category_id)
            or (old.workflow_step_id is distinct from new.workflow_step_id)
        -- we dont care about the superseded because the "document_ready" after undelete will trigger the rules
        -- OR (OLD.superseded IS DISTINCT FROM NEW.superseded)
    )
    execute procedure rule.trigger();

create trigger rule_invoice_insert_trigger
    after insert on public.invoice
    for each row
    execute procedure rule.trigger();

create trigger rule_invoice_update_trigger
    after update on public.invoice
    for each row
    when (old.* is distinct from new.*)
    execute procedure rule.trigger();

-- TODO-db-200210 what about when an approval request gets deleted making the document released? (because previous requests are fulfilled)
create trigger rule_document_approval_insert_trigger
    after insert on public.document_approval
    for each row
    execute procedure rule.trigger();

create trigger invoice_cost_center_insert_trigger
    after insert on public.invoice_cost_center
    for each row
    execute function rule.trigger();

create trigger invoice_cost_center_update_trigger
    after update on public.invoice_cost_center
    for each row
    when (OLD.client_company_cost_center_id is distinct from NEW.client_company_cost_center_id)
    execute function rule.trigger();

create trigger rule_document_became_ready_trigger
    after insert on rule.document_ready
    for each row
    when (NEW.is_ready)
    execute procedure rule.trigger();

create trigger rule_invoice_accounting_item_insert_trigger
    after insert on public.invoice_accounting_item
    for each row
    execute procedure rule.trigger();

create trigger rule_invoice_accounting_item_update_trigger
    after update on public.invoice_accounting_item
    for each row
    execute procedure rule.trigger();

create trigger rule_document_bank_matched_trigger
    after insert on public.document_bank_transaction
    for each row
    execute procedure rule.trigger();

create trigger rule_document_credit_card_matched_trigger
    after insert on public.document_credit_card_transaction
    for each row
    execute procedure rule.trigger();

create trigger rule_document_cash_matched_trigger
    after insert on public.document_cash_transaction
    for each row
    execute procedure rule.trigger();

create trigger rule_document_real_estate_object_insert_trigger
    after insert on public.document_real_estate_object
    for each row
    execute function rule.trigger();

create trigger rule_document_real_estate_object_update_trigger
    after update on public.document_real_estate_object
    for each row
    when (OLD.object_instance_id is distinct from NEW.object_instance_id)
    execute function rule.trigger();

-- document tags are only inserted and deleted, they shouldn't be updated
create trigger rule_document_tag_insert_trigger
    after insert on public.document_tag
    for each row
    execute function rule.trigger();

-- TODO: add trigger for other transaction types when in use

create trigger rule_bank_payment_insert_or_update_trigger
    after insert or update on public.bank_payment
    for each row
    when (new."status" = 'FINISHED')
    execute function rule.trigger();
