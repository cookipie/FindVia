# FindVia Provider App — Foundation

This folder begins the Provider App as a responsive mobile-first web/PWA prototype. The existing FindVia landing page at the repository root is unchanged.

## Current status

- `index.html`: responsive UI foundation with Home, Jobs, Job Details/Offer, Wallet, Profile, and Notifications screens.
- Prototype interactions use local demo data only.
- Supabase authentication, live data, uploads, payment processing, notifications, and OTP completion are **not connected yet**.
- `../supabase/migrations/202610210001_provider_app_foundation.sql`: proposed shared-schema foundation. It is a draft and must be reconciled with the live Customer App schema before execution.

## Architecture decision

Three separate apps — Customer, Provider, Management — share one central Supabase project:
- Supabase Auth for identity and sessions
- Postgres for profiles, service catalog, jobs, offers, wallet ledger, commission, notifications and reports
- Supabase Storage for provider verification documents and job media
- RLS for user-level access
- server-side Edge Functions / Postgres RPCs for trusted transitions and financial operations

Do not create a second independent database for Provider App.

## Build order

1. Confirm the current Supabase project and inspect existing tables, roles, RLS policies, Storage buckets and deployed functions. Do not run the draft migration before this reconciliation.
2. Finalize shared contracts with Customer App: profiles/roles, service categories/areas, job fields/statuses, offer-selection behavior, customer-private fields and completion OTP lifecycle.
3. Apply additive database migrations with least-privilege RLS. Provider-safe job reads must not return maximum budget, exact address, phone, or other providers' offers before matching.
4. Implement Supabase Auth: signup/login, email verification, password reset, session persistence, logout and account deletion.
5. Implement provider onboarding, categories, service areas, document upload and Management App verification states.
6. Connect Home and Available Jobs to real data. Add safe server-side matching and offer submission.
7. Implement match/selection, private customer details after match, start/cancel transitions and Customer App status updates.
8. Implement customer OTP generation/delivery and rate-limited verification. OTP success must atomically complete the job and post commission + wallet ledger records exactly once.
9. Implement wallet recharge with a payment provider, server-side payment verification/webhooks, idempotency and transaction history. Never credit balance from a client callback alone.
10. Implement earnings/history, notifications, support reports, performance, settings and language scaffolding.
11. Build Management App controls for verification, commission configuration, wallet adjustments, disputes, reports and service catalog.
12. Test security boundaries, duplicate requests, failed payments, OTP retries, cancellation, insufficient wallet, RLS and mobile layouts before release.

## Money rules carried forward

- No FindVia Credits: use an INR real-money commission wallet.
- Provider signup, job viewing, offer submission and being selected are free.
- The initial commission example is 10% of the agreed job price, configurable by Management.
- Commission is recorded only after a successful customer completion OTP.
- Customer pays the provider directly in the initial release; integrated customer service payments and automatic provider payouts are deferred.
- Provider wallet and job earnings are separate accounting views.
- A negative/outstanding commission balance and offer-eligibility threshold still require an explicit admin-configurable rule before production.

## Production gate

Do not collect real money, upload sensitive identity documents, or use real customer data in this prototype. Before production, review the shared schema, configure secrets outside source control, implement policies/functions, select and configure a payment provider, and complete security/testing review.
