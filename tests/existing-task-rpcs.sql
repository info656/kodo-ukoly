CREATE OR REPLACE FUNCTION public.assign_task_inbox(inbox_id uuid, org_id uuid, title_value text, body_value text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare item public.task_inbox; new_task_id uuid;
begin
 if not private.is_kodo_admin() then raise exception 'Access denied' using errcode='42501'; end if;
 select * into item from public.task_inbox where id=inbox_id for update;
 if not found then raise exception 'Inbox item unavailable'; end if;
 if item.assigned_task_id is not null then return jsonb_build_object('id',item.assigned_task_id,'created',false); end if;
 if not item.attachments_complete or (select count(*) from public.task_inbox_files f where f.inbox_id=item.id)<>item.expected_file_count or exists(select 1 from public.task_inbox_files f where f.inbox_id=item.id and f.ready_at is null) then raise exception 'Attachments not complete'; end if;
 if not private.can_access_task_org(org_id) then raise exception 'Client unavailable'; end if;
 insert into public.client_tasks(organization_id,created_by,title,body,submitted_at)
 values(org_id,auth.uid(),trim(title_value),trim(body_value),now()) returning id into new_task_id;
 insert into public.task_files(task_id,uploaded_by,kind,object_path,original_name,mime_type,size_bytes,ready_at,sha256)
 select new_task_id,auth.uid(),'attachment',object_path,original_name,mime_type,size_bytes,ready_at,sha256 from public.task_inbox_files f where f.inbox_id=item.id;
 update public.task_inbox set title=trim(title_value),body=trim(body_value),assigned_task_id=new_task_id,assigned_by=auth.uid(),assigned_at=now() where id=item.id;
 return jsonb_build_object('id',new_task_id,'created',true);
end; $function$;

CREATE OR REPLACE FUNCTION public.create_internal_task_inbox(inbox_id uuid, title_value text, body_value text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare existing public.task_inbox;
begin
  if auth.uid() is null or private.is_kodo_admin() is distinct from true
     or private.portal_user_is_frozen(auth.uid()) is distinct from false
     or private.portal_session_issue() is not null then
    raise exception 'Access denied' using errcode='42501';
  end if;
  if inbox_id is null or title_value is null or length(btrim(title_value)) not between 2 and 200
     or body_value is null or length(btrim(body_value)) not between 1 and 15000 then
    raise exception 'Invalid internal task';
  end if;
  insert into public.task_inbox(id,message_id,thread_id,sender_email,sender_name,subject,original_body,title,body,
    received_at,expected_file_count,attachments_complete,source_kind,source_user_id,submitted_at,ai_status)
  values(inbox_id,'internal:'||inbox_id::text,'','','Interní úkol',btrim(title_value),btrim(body_value),btrim(title_value),btrim(body_value),
    now(),0,true,'internal',auth.uid(),now(),'manual') on conflict(id) do nothing;
  select * into existing from public.task_inbox where id=inbox_id;
  if not found or existing.source_kind<>'internal' or existing.source_user_id is distinct from auth.uid()
     or existing.title is distinct from btrim(title_value) or existing.body is distinct from btrim(body_value) then
    raise exception 'Internal task request conflict';
  end if;
  return inbox_id;
end $function$;

CREATE OR REPLACE FUNCTION public.delete_client_task(target_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare item public.client_tasks; removed_at timestamptz:=now();
begin
 if not private.is_kodo_admin() then raise exception 'Access denied' using errcode='42501'; end if;
 -- Same lock order as the inbox assignment/delete functions.
 perform 1 from public.task_inbox where assigned_task_id=target_id for update;
 select * into item from public.client_tasks where id=target_id for update;
 if not found or item.deleted_at is not null then return jsonb_build_object('deleted',false,'paths','[]'::jsonb); end if;
 update public.task_inbox set deleted_at=removed_at,deleted_by=auth.uid(),ai_run_id=null where assigned_task_id=target_id and deleted_at is null;
 update public.client_tasks set deleted_at=removed_at,deleted_by=auth.uid() where id=target_id;
 update public.task_files set ready_at=ready_at where task_id=target_id;
 update public.task_inbox_files set ready_at=ready_at where inbox_id in(select id from public.task_inbox where assigned_task_id=target_id);
 insert into private.portal_trash_events(kind,target_id,actor_id,action) values('task',target_id,auth.uid(),'trash');
 return jsonb_build_object('deleted',true,'organizationId',item.organization_id,'paths','[]'::jsonb);
end $function$;

CREATE OR REPLACE FUNCTION public.delete_task_inbox(inbox_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare item public.task_inbox;
begin
 if not private.is_kodo_admin() then raise exception 'Access denied' using errcode='42501'; end if;
 select * into item from public.task_inbox where id=inbox_id for update;
 if not found or item.deleted_at is not null then return jsonb_build_object('deleted',false,'paths','[]'::jsonb); end if;
 if item.assigned_task_id is not null or not item.attachments_complete then raise exception 'Inbox item unavailable'; end if;
 update public.task_inbox set deleted_at=now(),deleted_by=auth.uid(),ai_run_id=null where id=inbox_id;
 update public.task_inbox_files set ready_at=ready_at where task_inbox_files.inbox_id=item.id;
 insert into private.portal_trash_events(kind,target_id,actor_id,action) values('inbox',item.id,auth.uid(),'trash');
 return jsonb_build_object('deleted',true,'paths','[]'::jsonb);
end $function$;

CREATE OR REPLACE FUNCTION public.save_client_task(target_id uuid, org_id uuid, title_value text, body_value text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare existing public.client_tasks%rowtype;
begin
 if (select auth.uid()) is null or not private.can_access_task_org(org_id) then raise exception 'Access denied' using errcode='42501'; end if;
 select * into existing from public.client_tasks where id=target_id for update;
 if found then
  if existing.created_by<>(select auth.uid()) or existing.organization_id<>org_id then raise exception 'Access denied' using errcode='42501'; end if;
  if existing.submitted_at is null then update public.client_tasks set title=trim(title_value),body=trim(body_value) where id=target_id; end if;
 else
  insert into public.client_tasks(id,organization_id,created_by,title,body) values(target_id,org_id,(select auth.uid()),trim(title_value),trim(body_value));
 end if;
 return target_id;
end; $function$;

CREATE OR REPLACE FUNCTION public.save_task_inbox(inbox_id uuid, title_value text, body_value text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if not private.is_kodo_admin() then raise exception 'Access denied' using errcode='42501'; end if;
 update public.task_inbox set title=trim(title_value),body=trim(body_value),ai_status=case when title<>trim(title_value) or body<>trim(body_value) then 'manual' else ai_status end,
 ai_run_id=case when title<>trim(title_value) or body<>trim(body_value) then null else ai_run_id end where id=inbox_id and assigned_task_id is null;
 return found; end $function$;

CREATE OR REPLACE FUNCTION public.set_task_inbox_done(inbox_id uuid, done_value boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or private.is_kodo_admin() is distinct from true
     or private.portal_user_is_frozen(auth.uid()) is distinct from false
     or private.portal_session_issue() is not null then
    raise exception 'Access denied' using errcode='42501';
  end if;
  if inbox_id is null or done_value is null then raise exception 'Invalid request'; end if;
  update public.task_inbox set
    internal_completed_at=case when done_value then coalesce(internal_completed_at,now()) else null end,
    internal_completed_by=case when done_value then coalesce(internal_completed_by,auth.uid()) else null end
  where id=inbox_id and deleted_at is null and submitted_at is not null and assigned_task_id is null and (not done_value or attachments_complete);
  return found;
end $function$;

CREATE OR REPLACE FUNCTION public.submit_client_task(target_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if not private.can_access_task(target_id) or not exists(select 1 from public.client_tasks where id=target_id and created_by=(select auth.uid())) then raise exception 'Access denied' using errcode='42501'; end if;
 update public.client_tasks set submitted_at=now() where id=target_id and submitted_at is null;
 return found;
end; $function$;
