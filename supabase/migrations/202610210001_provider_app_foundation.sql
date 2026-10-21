-- FindVia Provider App: foundational schema proposal
-- IMPORTANT: Review against the existing shared Supabase schema before applying.
-- This is a migration draft; do not run it against production until existing Customer App
-- tables, role values, and payment provider are reconciled.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'customer' check (role in ('customer','provider','management','admin')),
  full_name text,
  phone text,
  email text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.service_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  slug text not null unique,
  is_active boolean not null default true,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.service_areas (
  id uuid primary key default gen_random_uuid(),
  state text not null,
  district text,
  city text not null,
  area_name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (state, city, area_name)
);

create table if not exists public.worker_profiles (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid not null unique references public.profiles(id) on delete cascade,
  provider_code text unique,
  experience_years int not null default 0 check (experience_years >= 0),
  skills text[] not null default '{}',
  about text,
  verification_status text not null default 'pending'
    check (verification_status in ('pending','verified','rejected','suspended')),
  verification_rejection_reason text,
  is_available boolean not null default true,
  response_rate numeric(5,2) not null default 0,
  completion_rate numeric(5,2) not null default 0,
  cancellation_rate numeric(5,2) not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.worker_categories (
  worker_id uuid not null references public.profiles(id) on delete cascade,
  category_id uuid not null references public.service_categories(id),
  created_at timestamptz not null default now(),
  primary key (worker_id, category_id)
);

create table if not exists public.worker_service_areas (
  worker_id uuid not null references public.profiles(id) on delete cascade,
  area_id uuid not null references public.service_areas(id),
  approval_status text not null default 'approved'
    check (approval_status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(),
  primary key (worker_id, area_id)
);

create table if not exists public.worker_documents (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid not null references public.profiles(id) on delete cascade,
  document_type text not null check (document_type in ('identity','address','profile_photo','skill_certificate','other')),
  storage_path text not null,
  review_status text not null default 'pending' check (review_status in ('pending','approved','rejected')),
  rejection_reason text,
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

-- Customer-facing job creation and provider matching share this one table.
-- Exact address, contact details, and customer maximum budget must never be exposed
-- through a provider-facing query before a match.
create table if not exists public.jobs (
  id uuid primary key default gen_random_uuid(),
  job_code text unique,
  customer_id uuid not null references public.profiles(id),
  category_id uuid not null references public.service_categories(id),
  area_id uuid not null references public.service_areas(id),
  title text not null,
  description text not null,
  media_paths text[] not null default '{}',
  preferred_date date,
  preferred_time text,
  additional_notes text,
  customer_max_budget numeric(12,2) check (customer_max_budget is null or customer_max_budget >= 0),
  exact_address text,
  customer_contact text,
  selected_worker_id uuid references public.profiles(id),
  agreed_price numeric(12,2) check (agreed_price is null or agreed_price >= 0),
  commission_rate numeric(5,2) not null default 10 check (commission_rate >= 0 and commission_rate <= 100),
  status text not null default 'open'
    check (status in ('open','matched','in_progress','completion_pending','completed','cancelled','expired','disputed')),
  cancellation_reason text,
  cancelled_by uuid references public.profiles(id),
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.job_responses (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.jobs(id) on delete cascade,
  worker_id uuid not null references public.profiles(id) on delete cascade,
  offer_price numeric(12,2) not null check (offer_price > 0),
  offer_note text,
  status text not null default 'pending' check (status in ('pending','selected','not_selected','expired','withdrawn')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (job_id, worker_id)
);

create table if not exists public.job_completion_otps (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.jobs(id) on delete cascade,
  otp_hash text not null,
  expires_at timestamptz not null,
  attempts int not null default 0,
  used_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.worker_wallets (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid not null unique references public.profiles(id) on delete cascade,
  balance numeric(12,2) not null default 0,
  currency text not null default 'INR' check (currency = 'INR'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
-- Negative balances are intentionally permitted for the proposed outstanding-commission
-- policy. The offer-eligibility threshold must be enforced server-side and configurable.

create table if not exists public.wallet_transactions (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid not null references public.profiles(id),
  transaction_type text not null check (transaction_type in ('recharge','commission','refund','adjustment')),
  amount numeric(12,2) not null check (amount > 0),
  balance_before numeric(12,2) not null,
  balance_after numeric(12,2) not null,
  reference_id uuid,
  description text,
  status text not null default 'pending' check (status in ('pending','successful','failed','reversed')),
  idempotency_key text unique,
  created_at timestamptz not null default now()
);

create table if not exists public.job_commissions (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null unique references public.jobs(id),
  worker_id uuid not null references public.profiles(id),
  agreed_price numeric(12,2) not null,
  commission_rate numeric(5,2) not null,
  commission_amount numeric(12,2) not null,
  provider_net_earning numeric(12,2) not null,
  wallet_transaction_id uuid references public.wallet_transactions(id),
  status text not null default 'charged' check (status in ('charged','outstanding','held','refunded','waived')),
  created_at timestamptz not null default now()
);

create table if not exists public.recharge_requests (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid not null references public.profiles(id),
  amount numeric(12,2) not null check (amount > 0),
  currency text not null default 'INR',
  payment_provider text,
  provider_order_id text unique,
  provider_payment_id text unique,
  status text not null default 'pending' check (status in ('pending','successful','failed','cancelled','refunded')),
  verified_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  category text not null check (category in ('jobs','wallet','account','system')),
  title text not null,
  body text not null,
  data jsonb not null default '{}',
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id),
  job_id uuid references public.jobs(id),
  category text not null check (category in ('customer_problem','job_problem','wallet_problem','payment_problem','account_problem','other')),
  description text not null,
  status text not null default 'open' check (status in ('open','in_review','resolved','rejected')),
  assigned_to uuid references public.profiles(id),
  resolution_note text,
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

create table if not exists public.system_settings (
  key text primary key,
  value jsonb not null,
  updated_by uuid references public.profiles(id),
  updated_at timestamptz not null default now()
);

-- Future blueprint extensions: ratings, reviews, provider_payouts, provider_penalties.
-- Add these after the core job lifecycle, wallet and admin flows have been tested.

create index if not exists jobs_status_area_category_idx on public.jobs(status, area_id, category_id);
create index if not exists jobs_selected_worker_idx on public.jobs(selected_worker_id, status);
create index if not exists job_responses_worker_status_idx on public.job_responses(worker_id, status, created_at desc);
create index if not exists wallet_transactions_worker_created_idx on public.wallet_transactions(worker_id, created_at desc);
create index if not exists notifications_user_created_idx on public.notifications(user_id, created_at desc);
create index if not exists worker_documents_worker_status_idx on public.worker_documents(worker_id, review_status);

-- RLS is enabled now; policies should be added only after checking existing Customer App
-- policies and the exact management-role model. No broad provider SELECT policy is added
-- to jobs because row-level security alone cannot hide budget/address/contact columns.
alter table public.profiles enable row level security;
alter table public.worker_profiles enable row level security;
alter table public.worker_categories enable row level security;
alter table public.worker_service_areas enable row level security;
alter table public.worker_documents enable row level security;
alter table public.jobs enable row level security;
alter table public.job_responses enable row level security;
alter table public.job_completion_otps enable row level security;
alter table public.worker_wallets enable row level security;
alter table public.wallet_transactions enable row level security;
alter table public.job_commissions enable row level security;
alter table public.recharge_requests enable row level security;
alter table public.notifications enable row level security;
alter table public.reports enable row level security;
alter table public.service_categories enable row level security;
alter table public.service_areas enable row level security;
alter table public.system_settings enable row level security;

-- Next migration must add least-privilege policies and SECURITY DEFINER RPCs for:
-- 1) provider-safe available-job cards (without private columns)
-- 2) offer submission + selection lifecycle
-- 3) start/cancel job with ownership and status checks
-- 4) customer OTP issuance + rate-limited OTP verification
-- 5) atomic commission/wallet ledger posting and idempotency
-- 6) payment webhook verification before wallet recharge credit
-- 7) management verification, disputes, settings and reports.
