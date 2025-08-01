CREATE FUNCTION private.merge_bank_transactions(
    left_bank_transaction_id  uuid,
    right_bank_transaction_id uuid,
    to_delete                 text
) RETURNS void AS $$
BEGIN
    -- perform merge and deletion
    CASE merge_bank_transactions.to_delete

        -- deleting left
        WHEN 'left' THEN

            -- merge matches on right transaction
            UPDATE public.document_bank_transaction
                SET bank_transaction_id=merge_bank_transactions.right_bank_transaction_id
            WHERE (
                bank_transaction_id = merge_bank_transactions.left_bank_transaction_id
            ) AND (
                -- avoid duplicate entries if the transaction is already matched
                document_id NOT IN (
                    SELECT in_dmt.document_id FROM public.document_bank_transaction AS in_dmt
                    WHERE (
                        in_dmt.bank_transaction_id = merge_bank_transactions.right_bank_transaction_id
                    )
                )
            );

            -- delete left transaction
            DELETE FROM public.bank_transaction WHERE (id = merge_bank_transactions.left_bank_transaction_id);

        -- deleting right
        WHEN 'right' THEN

            -- merge matches on left transaction
            UPDATE public.document_bank_transaction
                SET bank_transaction_id=merge_bank_transactions.left_bank_transaction_id
            WHERE (
                bank_transaction_id = merge_bank_transactions.right_bank_transaction_id
            ) AND (
                -- avoid duplicate entries if the transaction is already matched
                document_id NOT IN (
                    SELECT in_dmt.document_id FROM public.document_bank_transaction AS in_dmt
                    WHERE (
                        in_dmt.bank_transaction_id = merge_bank_transactions.left_bank_transaction_id
                    )
                )
            );

            -- delete right transaction
            DELETE FROM public.bank_transaction WHERE (id = merge_bank_transactions.right_bank_transaction_id);

        ELSE

            RAISE EXCEPTION 'Invalid `to_delete` argument supplied: %', merge_bank_transactions.to_delete;

    END CASE;
END;
$$
LANGUAGE plpgsql VOLATILE;

----

CREATE FUNCTION private.merge_credit_card_transactions(
    left_credit_card_transaction_id  uuid,
    right_credit_card_transaction_id uuid,
    to_delete                 text
) RETURNS void AS $$
BEGIN
    -- perform merge and deletion
    CASE merge_credit_card_transactions.to_delete

        -- deleting left
        WHEN 'left' THEN

            -- merge matches on right transaction
            UPDATE public.document_credit_card_transaction
                SET credit_card_transaction_id=merge_credit_card_transactions.right_credit_card_transaction_id
            WHERE (
                credit_card_transaction_id = merge_credit_card_transactions.left_credit_card_transaction_id
            ) AND (
                -- avoid duplicate entries if the transaction is already matched
                document_id NOT IN (
                    SELECT in_dmt.document_id FROM public.document_credit_card_transaction AS in_dmt
                    WHERE (
                        in_dmt.credit_card_transaction_id = merge_credit_card_transactions.right_credit_card_transaction_id
                    )
                )
            );

            -- delete left transaction
            DELETE FROM public.credit_card_transaction WHERE (id = merge_credit_card_transactions.left_credit_card_transaction_id);

        -- deleting right
        WHEN 'right' THEN

            -- merge matches on left transaction
            UPDATE public.document_credit_card_transaction
                SET credit_card_transaction_id=merge_credit_card_transactions.left_credit_card_transaction_id
            WHERE (
                credit_card_transaction_id = merge_credit_card_transactions.right_credit_card_transaction_id
            ) AND (
                -- avoid duplicate entries if the transaction is already matched
                document_id NOT IN (
                    SELECT in_dmt.document_id FROM public.document_credit_card_transaction AS in_dmt
                    WHERE (
                        in_dmt.credit_card_transaction_id = merge_credit_card_transactions.left_credit_card_transaction_id
                    )
                )
            );

            -- delete right transaction
            DELETE FROM public.credit_card_transaction WHERE (id = merge_credit_card_transactions.right_credit_card_transaction_id);

        ELSE

            RAISE EXCEPTION 'Invalid `to_delete` argument supplied: %', merge_bank_transactions.to_delete;

    END CASE;
END;
$$
LANGUAGE plpgsql VOLATILE;
