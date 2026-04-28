-- Reference: Docs/recommendation_pdf_report_workflow.md
-- Purpose: MVP Supabase Storage bucket for generated recommendation report PDFs.
--
-- SECURITY NOTE:
-- The current static MVP uses the anon key without a full authenticated user flow.
-- These policies are intentionally permissive enough for MVP testing.
-- Tighten before using with real customer-sensitive reports.

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'recommendation-reports',
  'recommendation-reports',
  true,
  10485760,
  array['application/pdf']
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "MVP public read recommendation reports" on storage.objects;
create policy "MVP public read recommendation reports"
on storage.objects
for select
using (bucket_id = 'recommendation-reports');

drop policy if exists "MVP anon upload recommendation reports" on storage.objects;
create policy "MVP anon upload recommendation reports"
on storage.objects
for insert
with check (
  bucket_id = 'recommendation-reports'
  and lower((storage.foldername(name))[1]) = 'reports'
);

drop policy if exists "MVP anon update recommendation reports" on storage.objects;
create policy "MVP anon update recommendation reports"
on storage.objects
for update
using (
  bucket_id = 'recommendation-reports'
  and lower((storage.foldername(name))[1]) = 'reports'
)
with check (
  bucket_id = 'recommendation-reports'
  and lower((storage.foldername(name))[1]) = 'reports'
);
