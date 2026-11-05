# Kodo Úkoly

- Pava authorized the Zest fork on 2026-11-05. Keep Zest's existing screens, theme, layout and task interactions. The application name is **Kodo Úkoly**.
- Online only. Existing Kodo Supabase `client_tasks` and `task_inbox` remain authoritative. Clients are groups; Inbox is a separate system group. Local Isar is a rendering cache, never a queue for offline writes.
- Accept shared HTTP(S) links/text into Inbox, with explicit user action. Keep existing attachments view/download only; do not add file uploads.
- Use real user authentication, MFA and existing server session guards. Never embed a service-role key, manufacture JWT claims, copy another app's session or weaken RLS.
- Tests use synthetic fixtures. Do not modify real customer tasks or send notifications/emails for testing.
- Preserve MIT notices. Keep `.local/`, credentials, build products and customer data out of Git.
- Keep one installed app at `/Users/pava/Applications/Kodo Úkoly.app`. Staging/build products must not remain as additional indexed applications after installation.
