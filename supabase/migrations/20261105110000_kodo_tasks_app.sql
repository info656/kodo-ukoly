-- Kodo Úkoly: original Zest UI, existing task records, owner-private display metadata.
-- No existing policies or business records are altered; no notifications are sent.
create table public.kodo_task_app_metadata (
 owner_id uuid not null references public.profiles(id),
 entity_key text not null check(length(entity_key)<=80),
 value jsonb not null default '{}' check(jsonb_typeof(value)='object' and octet_length(value::text)<=16000),
 primary key(owner_id,entity_key)
);
alter table public.kodo_task_app_metadata enable row level security;
revoke all on public.kodo_task_app_metadata from public,anon,authenticated;
grant all on public.kodo_task_app_metadata to service_role;

create function private.kodo_tasks_app_guard() returns void language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or private.is_kodo_admin() is distinct from true
 or private.portal_user_is_frozen(auth.uid()) is distinct from false
 or private.portal_session_issue() is not null then
  raise exception 'Přihlaste se administrátorským účtem a dokončete ověření.' using errcode='42501';
 end if;
end $$;
revoke all on function private.kodo_tasks_app_guard() from public,anon,authenticated;

create function private.kodo_tasks_app_version(k text) returns text language plpgsql stable security definer set search_path='' as $$
declare r jsonb; m jsonb;
begin
 select value into m from public.kodo_task_app_metadata where owner_id=auth.uid() and entity_key=k;
 if k='inbox' then r:='{"id":"inbox"}'::jsonb;
 elsif k like 'org:%' then select jsonb_build_object('id',id,'name',legal_name) into r from public.organizations where id=substring(k from 5)::uuid and archived_at is null and type='client';
 elsif k like 'task:%' then select to_jsonb(t) into r from public.client_tasks t where t.id=substring(k from 6)::uuid and t.deleted_at is null and t.submitted_at is not null;
 elsif k like 'inbox:%' then select to_jsonb(t) into r from public.task_inbox t where t.id=substring(k from 7)::uuid and t.deleted_at is null and t.assigned_task_id is null and t.submitted_at is not null;
 end if;
 if r is null then return null;end if;
 return md5(r::text||coalesce(m,'{}'::jsonb)::text);
end $$;
revoke all on function private.kodo_tasks_app_version(text) from public,anon,authenticated;

create function public.kodo_tasks_app_read() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare groups jsonb; items jsonb;
begin
 perform private.kodo_tasks_app_guard();
 select coalesce(jsonb_agg(x.payload order by x.name),'[]') into groups from (
  select o.legal_name as name,jsonb_build_object('key','org:'||o.id,'name',o.legal_name,'meta',coalesce(m.value,'{}'),'version',private.kodo_tasks_app_version('org:'||o.id)) payload
  from public.organizations o left join public.kodo_task_app_metadata m on m.owner_id=auth.uid() and m.entity_key='org:'||o.id
  where o.type='client' and o.archived_at is null and not coalesce((m.value->>'hidden')::boolean,false)
  and (o.portal_access in('tasks','epr_tasks','business_tasks') or m.value is not null or exists(select 1 from public.client_tasks t where t.organization_id=o.id and t.deleted_at is null and t.submitted_at is not null))
 )x;
 groups:=jsonb_build_array(jsonb_build_object('key','inbox','name','Inbox','meta',coalesce((select value from public.kodo_task_app_metadata where owner_id=auth.uid() and entity_key='inbox'),'{}'),'version',private.kodo_tasks_app_version('inbox')))||groups;
 select coalesce(jsonb_agg(x.payload order by x.created_at desc,x.key),'[]') into items from (
  select 'task:'||t.id as key,t.created_at,jsonb_build_object('key','task:'||t.id,'group','org:'||t.organization_id,'title',t.title,'body',t.body,'created_at',t.created_at,'completed_at',t.completed_at,'meta',coalesce(m.value,'{}'),'version',private.kodo_tasks_app_version('task:'||t.id),
   'files',coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'name',f.original_name,'path',f.object_path)) from public.task_files f where f.task_id=t.id and f.ready_at is not null),'[]')) payload
  from public.client_tasks t join public.organizations o on o.id=t.organization_id and o.archived_at is null and o.type='client'
  left join public.kodo_task_app_metadata m on m.owner_id=auth.uid() and m.entity_key='task:'||t.id
  where t.deleted_at is null and t.submitted_at is not null
  union all
  select 'inbox:'||t.id,t.created_at,jsonb_build_object('key','inbox:'||t.id,'group','inbox','title',t.title,'body',t.body,'created_at',t.created_at,'completed_at',t.internal_completed_at,'meta',coalesce(m.value,'{}'),'version',private.kodo_tasks_app_version('inbox:'||t.id),
   'files',coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'name',f.original_name,'path',f.object_path)) from public.task_inbox_files f where f.inbox_id=t.id and f.ready_at is not null),'[]'))
  from public.task_inbox t left join public.kodo_task_app_metadata m on m.owner_id=auth.uid() and m.entity_key='inbox:'||t.id
  where t.deleted_at is null and t.assigned_task_id is null and t.submitted_at is not null
 )x;
 return jsonb_build_object('schema',1,'owner',auth.uid(),'groups',groups,'items',items);
end $$;
revoke all on function public.kodo_tasks_app_read() from public,anon;
grant execute on function public.kodo_tasks_app_read() to authenticated;

create function public.kodo_tasks_app_write(action_value text,key_value text,expected_value text,payload_value jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare k text:=key_value; current_version text; id_value uuid; org uuid; title_value text; body_value text; m jsonb; target_group text; result jsonb; row_task public.client_tasks; row_inbox public.task_inbox; parent_key text; n integer:=0;
begin
 perform private.kodo_tasks_app_guard();
 if payload_value is null or jsonb_typeof(payload_value)<>'object' or octet_length(payload_value::text)>60000 then raise exception 'Neplatný požadavek.';end if;
 if action_value is null or action_value not in('create','put','status','delete','move','group','group_create') then raise exception 'Neplatná operace.';end if;
 if k is null or k !~ '^(inbox|org:[0-9a-f-]{36}|task:[0-9a-f-]{36}|inbox:[0-9a-f-]{36})$' then raise exception 'Neplatný úkol.';end if;
 -- Serialize this entity, including metadata, without changing existing tables.
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
 if k like 'task:%' then perform 1 from public.task_inbox where assigned_task_id=substring(k from 6)::uuid for update;select * into row_task from public.client_tasks where id=substring(k from 6)::uuid for update;
 elsif k like 'inbox:%' then select * into row_inbox from public.task_inbox where id=substring(k from 7)::uuid for update;end if;
 current_version:=private.kodo_tasks_app_version(k);
 if action_value not in('create','group_create') and (current_version is null or expected_value is distinct from current_version) then
  raise exception 'Úkol se mezitím změnil. Obnovte jej a změnu zopakujte.' using errcode='40001';
 end if;
 m:=coalesce(payload_value->'meta',(select value from public.kodo_task_app_metadata where owner_id=auth.uid() and entity_key=k),'{}'::jsonb);
 if jsonb_typeof(m)<>'object' or octet_length(m::text)>16000 then raise exception 'Neplatné nastavení úkolu.';end if;
 target_group:=payload_value->>'group';
 if target_group is not null and target_group<>'inbox' then
  if target_group !~ '^org:[0-9a-f-]{36}$' then raise exception 'Neplatná skupina.';end if;
  org:=substring(target_group from 5)::uuid;
  if not exists(select 1 from public.organizations where id=org and type='client' and archived_at is null) then raise exception 'Klient není dostupný.';end if;
 end if;
 title_value:=btrim(payload_value->>'title');body_value:=btrim(payload_value->>'body');
 if action_value in('create','put') then
  if title_value is null or length(title_value) not between 2 and 200 or length(coalesce(body_value,''))>15000 then raise exception 'Název musí mít 2–200 znaků, popis nejvýše 15 000.';end if;
  if body_value is null or body_value='' then body_value:=title_value;m:=m||jsonb_build_object('empty_body_value',body_value);else m:=m-'empty_body_value';end if;
 end if;
 if action_value='group_create' then
  select id into org from public.organizations where archived_at is null and type='client' and lower(legal_name)=lower(title_value);
  if org is null then raise exception 'Klienta nejprve založte v portálu. Zde použijte jeho přesný název.';end if;
  if (select count(*) from public.organizations where archived_at is null and type='client' and lower(legal_name)=lower(title_value))<>1 then raise exception 'Název klienta není jednoznačný.';end if;
  k:='org:'||org;m:=m||jsonb_build_object('hidden',false);
 elsif action_value='group' then
  if k<>'inbox' and k not like 'org:%' then raise exception 'Neplatná skupina.';end if;
  if k='inbox' and (coalesce((m->>'archive')::boolean,false) or coalesce((m->>'hidden')::boolean,false)) then raise exception 'Inbox zůstává dostupný.';end if;
 elsif action_value='create' then
  if target_group is null then raise exception 'Vyberte skupinu.';end if;
  if current_version is not null then
   -- A retried creation confirms the same saved content, never duplicates it.
   if (k like 'task:%' and (row_task.title is distinct from title_value or row_task.body is distinct from body_value or row_task.organization_id is distinct from org)) or
      (k like 'inbox:%' and (row_inbox.title is distinct from title_value or row_inbox.body is distinct from body_value or row_inbox.source_user_id is distinct from auth.uid())) then raise exception 'Identifikátor už patří jinému úkolu.';end if;
   return jsonb_build_object('key',k,'version',current_version);
  end if;
  if target_group='inbox' and k like 'inbox:%' then perform public.create_internal_task_inbox(substring(k from 7)::uuid,title_value,body_value);
  elsif org is not null and k like 'task:%' then
   perform public.save_client_task(substring(k from 6)::uuid,org,title_value,body_value);
   perform public.submit_client_task(substring(k from 6)::uuid);
  else raise exception 'Skupina neodpovídá úkolu.';end if;
 elsif action_value='put' then
  if k like 'task:%' then update public.client_tasks set title=title_value,body=body_value where id=row_task.id;
  elsif k like 'inbox:%' then perform public.save_task_inbox(row_inbox.id,title_value,body_value);
  else raise exception 'Neplatný úkol.';end if;
 elsif action_value='status' then
  if payload_value->>'status' is null or payload_value->>'status' not in('active','done','cancelled') then raise exception 'Neplatný stav.';end if;
  if k like 'task:%' then update public.client_tasks set completed_at=case when payload_value->>'status'='active' then null else coalesce(completed_at,now()) end,completed_by=case when payload_value->>'status'='active' then null else coalesce(completed_by,auth.uid()) end where id=row_task.id;
  elsif k like 'inbox:%' then if not public.set_task_inbox_done(row_inbox.id,payload_value->>'status'<>'active') then raise exception 'Úkol nelze dokončit, přílohy ještě nejsou připravené.';end if;
  else raise exception 'Neplatný úkol.';end if;
  m:=m||jsonb_build_object('status',payload_value->>'status');
 elsif action_value='delete' then
  if k like 'task:%' then perform public.delete_client_task(row_task.id);
  elsif k like 'inbox:%' then perform public.delete_task_inbox(row_inbox.id);
  else raise exception 'Neplatný úkol.';end if;
  delete from public.kodo_task_app_metadata where owner_id=auth.uid() and entity_key=k;
  return jsonb_build_object('key',k,'deleted',true);
 elsif action_value='move' then
  if target_group is null then raise exception 'Vyberte skupinu.';end if;
  if k like 'inbox:%' and org is not null then
   result:=public.assign_task_inbox(row_inbox.id,org,row_inbox.title,row_inbox.body);
   delete from public.kodo_task_app_metadata where owner_id=auth.uid() and entity_key=k;
   k:='task:'||(result->>'id');
  elsif k like 'task:%' and org is not null then
   update public.client_tasks set organization_id=org where id=row_task.id;
  elsif k like 'task:%' and target_group='inbox' then
   raise exception 'Klientský úkol ponechte u klienta nebo jej přesuňte k jinému. Nové nezatříděné zadání vytvořte v Inboxu.';
  elsif k not like 'inbox:%' then raise exception 'Neplatný přesun.';end if;
 end if;
 parent_key:=m->>'parent';
 if parent_key is not null and (
  (k like 'inbox:%' and parent_key not like 'inbox:%') or
  (k like 'task:%' and (parent_key not like 'task:%' or not exists(select 1 from public.client_tasks a join public.client_tasks b on a.organization_id=b.organization_id where 'task:'||a.id=k and 'task:'||b.id=parent_key)))
 ) then raise exception 'Podúkol musí být ve stejné skupině.';end if;
 while parent_key is not null loop
  n:=n+1;
  if parent_key=k or n>100 or private.kodo_tasks_app_version(parent_key) is null then raise exception 'Neplatná vazba podúkolu.';end if;
  select value->>'parent' into parent_key from public.kodo_task_app_metadata where owner_id=auth.uid() and entity_key=parent_key;
 end loop;
 insert into public.kodo_task_app_metadata(owner_id,entity_key,value) values(auth.uid(),k,m)
 on conflict(owner_id,entity_key) do update set value=excluded.value;
 return jsonb_build_object('key',k,'version',private.kodo_tasks_app_version(k));
end $$;
revoke all on function public.kodo_tasks_app_write(text,text,text,jsonb) from public,anon;
grant execute on function public.kodo_tasks_app_write(text,text,text,jsonb) to authenticated;
