-- Purpose:
-- Store landing-page access requests independently from future authentication.
--
-- Why:
-- The public landing form needs a safe place to record access requests and
-- email-delivery status. This table deliberately does not depend on auth.users,
-- user_profiles, organisations, recommendations, or reports.
--
-- Supabase SQL Editor note:
-- Run one numbered query block at a time.

-- QUERY 1: Create standalone access request table
create table if not exists public.access_requests (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  email text not null,
  normalized_email text not null,
  source text not null default 'landing_page',
  status text not null default 'requested',
  requester_user_agent text,
  requester_ip text,
  notify_email_sent_at timestamptz,
  welcome_email_sent_at timestamptz,
  error_message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint access_requests_status_check
    check (status in ('requested', 'emailed', 'email_failed', 'ignored_spam'))
);

-- QUERY 2: Add operational indexes
create index if not exists access_requests_normalized_email_idx
  on public.access_requests (normalized_email);

create index if not exists access_requests_created_at_idx
  on public.access_requests (created_at desc);

create index if not exists access_requests_status_idx
  on public.access_requests (status);

-- QUERY 3: Enable RLS without public table policies
-- The request-access Edge Function writes with the service-role key. Browser
-- clients should not insert directly into this table.
alter table public.access_requests enable row level security;

-- QUERY 4: Validate table shape
select
  column_name,
  data_type,
  is_nullable
from information_schema.columns
where table_schema = 'public'
  and table_name = 'access_requests'
order by ordinal_position;

-- QUERY 5: Validate RLS is enabled
select
  c.relname as table_name,
  c.relrowsecurity as rls_enabled,
  c.relforcerowsecurity as force_rls
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname = 'access_requests';
