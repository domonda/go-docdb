create function super.dump_user(user_id uuid) returns json as $$
  select json_build_object(
    'id', u.id,
    'enabled', u.enabled,
    'auth0UserId', u.auth0_user_id,
    'token', u.token,
    'clientCompanyId', u.client_company_id,
    'title', u.title,
    'firstName', u.first_name,
    'lastName', u.last_name,
    'email', u.email,
    'language', u."language",
    'type', u."type",
    'domondaUpdateNotification', u.domonda_update_notification,
    'documentDirectApprovalRequestNotification', u.document_direct_approval_request_notification,
    'documentGroupApprovalRequestNotification', u.document_group_approval_request_notification,
    'createdBy', u.created_by,
    'updatedBy', u.updated_by,
    'createdAt', u.created_at,
    'updatedAt', u.updated_at,
    'clientCompanyUsers', (
      select json_agg(json_build_object(
        'id', ccu.id,
        'clientCompanyId', ccu.client_company_id,
        'roleName', ccu.role_name,
        'documentAccountingTabAccess', ccu.document_accounting_tab_access,
        'approverLimit', ccu.approver_limit,
        'createdAt', ccu.created_at,
        'updatedAt', ccu.updated_at,
        'documentFilter', (
          select json_build_object(
            'hasInvoice', df.has_invoice,
            'hasWorkflowStep', df.has_workflow_step,
            'hasApprovalRequest', df.has_approval_request
          ) from control.document_filter as df where (df.client_company_user_id = ccu.id)
        ),
        'documentCategoryAccesses', (
          select json_agg(json_build_object(
            'id', dca.id,
            'documentCategoryId', dca.document_category_id
          )) from control.document_category_access as dca where (dca.client_company_user_id = ccu.id)
        ),
        'documentWorkflowAccesses', (
          select json_agg(json_build_object(
            'id', dwa.id,
            'documentWorkflowId', dwa.document_workflow_id,
            'documentWorkflowStepAccesses', (
              select json_agg(json_build_object(
                'id', dwsa.id,
                'documentWorkflowStepId', dwsa.document_workflow_step_id
              )) from control.document_workflow_step_access as dwsa where (dwsa.document_workflow_access_id = dwa.id)
            )
          )) from control.document_workflow_access as dwa where (dwa.client_company_user_id = ccu.id)
        )
      )) from control.client_company_user as ccu where (ccu.user_id = u.id)
    )
  )
  from public.user as u where (u.id = dump_user.user_id)
$$ language sql stable strict;
