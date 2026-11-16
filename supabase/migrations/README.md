# Migration boundary

No application migration is applied in Phase 01. This directory is intentionally
tracked with this policy document rather than an empty or misleading SQL migration.

Future migrations use UTC timestamps: `YYYYMMDDHHMMSS_description.sql`.
Every exposed table must enable RLS and define reviewed grants and policies in
the same migration that creates it. Test denied access before allowing production
traffic. Never assume RLS is enabled merely because the client uses a publishable key.

Do not push to the existing project until the schema and policies are approved.
