# Request Access Email Flow

## Purpose
Capture landing-page access requests, notify Futurlens, and send the requester
an app access link without tying this flow to future authentication.

## Files
- SQL table: [create_access_requests.sql](../sql/create_access_requests.sql)
- Edge Function: [request-access](../supabase/functions/request-access/index.ts)
- Landing page: [index.html](../suburb-app/index.html)

## Supabase Setup
Run the SQL file in numbered blocks:

```sql
-- sql/create_access_requests.sql
```

Deploy the Edge Function:

```bash
supabase functions deploy request-access
```

Set required secrets:

```bash
supabase secrets set RESEND_API_KEY=re_xxxxx
supabase secrets set ACCESS_NOTIFY_EMAIL=you@example.com
supabase secrets set ACCESS_FROM_EMAIL="Futurlens <hello@yourdomain.com>"
supabase secrets set APP_ACCESS_URL=https://your-site.example/app.html
```

Optional:

```bash
supabase secrets set ACCESS_REPLY_TO=you@example.com
```

## Notes
- `public.access_requests` is standalone and does not reference `auth.users`.
- RLS is enabled and no browser insert policy is required.
- The Edge Function writes with the service-role key and calls Resend.
- Supabase normally provides `SUPABASE_SERVICE_ROLE_KEY` to Edge Functions.
  This function also supports `FUTURLENS_SUPABASE_SERVICE_ROLE_KEY` as a
  fallback secret if needed.
- `ACCESS_FROM_EMAIL` should use a Resend-verified sending domain before this
  goes live.
- The landing page only calls the Edge Function; it never sees Resend or
  service-role secrets.
