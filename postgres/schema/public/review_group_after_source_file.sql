create type public.review_group_status as enum (
  'READY',              -- ready to be worked on
  'EDITING',            -- group is being worked on/reviewed
  'DOCUMENTS_ARRIVING', -- source files are currently processing and will lead to documents arriving in the group
  'IDLING',             -- processing requested, waiting for it to start
  'PROCESSING',         -- currently being processed
  'PROCESSED',          -- processing completed successfuly
  'ERROR'               -- error during processing
);

create function public.review_group_status(
  review_group public.review_group
) returns public.review_group_status as
$$
  select
    case
      when review_group.processing_error is not null
        then 'ERROR'::public.review_group_status
      when review_group.processing_ended_at is not null
        then 'PROCESSED'::public.review_group_status
      when review_group.processing_started_at is not null
        then (
          case review_group.processing_percentage is null
            when true then 'IDLING'::public.review_group_status
            else 'PROCESSING'::public.review_group_status
          end
        )
      when exists(
          select from public.source_file as f
            where f.category = 'DOCUMENT' and f.review_group_id = review_group.id
        )
        then 'DOCUMENTS_ARRIVING'::public.review_group_status
      when review_group.locked_by is not null
        then 'EDITING'::public.review_group_status
      else 'READY'::public.review_group_status
    end
$$
language sql stable strict;

comment on function public.review_group_status is '@notNull';

----

create function public.get_review_group_status(
  review_group_id uuid
) returns public.review_group_status as
$$
  select public.review_group_status(rg) from public.review_group as rg where rg.id = review_group_id
$$
language sql stable strict;

comment on function public.get_review_group_status is '@omit';

----

create function public.review_group_locked_for_current_user(
  review_group public.review_group
) returns boolean as
$$
  with locked_by_current_user as (
    select
      -- we coalesce to null uuid to handle unauthorized users
      review_group.locked_by = coalesce(id, '00000000-0000-0000-0000-000000000000') as locked
    from private.current_user()
  )
  select
    case public.review_group_status(review_group)
      -- never locked when ready
      when 'READY' then false
      -- not locked when current user is editing the group
      when 'EDITING' then coalesce(not locked_by_current_user.locked, false)
      when 'ERROR' then coalesce(not locked_by_current_user.locked, false)
      -- all other cases, is locked
      else true
    end
  from locked_by_current_user
$$
language sql stable strict;

comment on function public.review_group_locked_for_current_user is '@notNull';

