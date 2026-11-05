-- Synthetic, isolated Postgres fixture. NEVER run this against a connected project.
create role anon;create role authenticated;create role service_role;
create schema auth;create schema private;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
create function private.is_kodo_admin() returns boolean language sql stable as $$select coalesce(current_setting('test.admin',true),'false')='true'$$;
create function private.portal_user_is_frozen(uuid) returns boolean language sql stable as $$select coalesce(current_setting('test.frozen',true),'false')='true'$$;
create function private.portal_session_issue() returns text language sql stable as $$select nullif(current_setting('test.session_issue',true),'')$$;
create function private.can_access_task_org(uuid) returns boolean language sql stable as $$select private.is_kodo_admin()$$;
create function private.can_access_task(uuid) returns boolean language sql stable as $$select private.is_kodo_admin()$$;
create table profiles(id uuid primary key);
create table organizations(id uuid primary key,legal_name text,type text,archived_at timestamptz,portal_access text);
create table client_tasks(id uuid primary key default gen_random_uuid(),organization_id uuid,created_by uuid,title text check(length(trim(title)) between 2 and 200),body text check(length(trim(body)) between 1 and 15000),created_at timestamptz default now(),submitted_at timestamptz,completed_at timestamptz,completed_by uuid,deleted_at timestamptz,deleted_by uuid);
create table task_inbox(id uuid primary key default gen_random_uuid(),message_id text unique,thread_id text,sender_email text,sender_name text,subject text,original_body text,title text,body text,received_at timestamptz,created_at timestamptz default now(),expected_file_count int default 0,attachments_complete bool default false,assigned_task_id uuid,assigned_by uuid,assigned_at timestamptz,deleted_at timestamptz,deleted_by uuid,source_kind text,source_user_id uuid,submitted_at timestamptz,internal_completed_at timestamptz,internal_completed_by uuid,ai_status text,ai_run_id uuid);
create table task_files(id uuid primary key default gen_random_uuid(),task_id uuid,uploaded_by uuid,kind text,object_path text unique,original_name text,mime_type text,size_bytes bigint,ready_at timestamptz,sha256 text);
create table task_inbox_files(id uuid primary key default gen_random_uuid(),inbox_id uuid,source_key text,object_path text unique,original_name text,mime_type text,size_bytes bigint,ready_at timestamptz,sha256 text);
create table private.portal_trash_events(kind text,target_id uuid,actor_id uuid,action text);
insert into profiles values('11111111-1111-4111-8111-111111111111');
insert into organizations values('22222222-2222-4222-8222-222222222222','Synthetic Client','client',null,'tasks'),('33333333-3333-4333-8333-333333333333','Second Client','client',null,'tasks');
