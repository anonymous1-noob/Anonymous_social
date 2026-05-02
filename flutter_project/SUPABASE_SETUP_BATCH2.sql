-- Batch 2 recommended schema additions for Anonymous Social (college/school)
--
-- Run in Supabase SQL editor.
-- Adjust types (uuid vs text) depending on your current posts.id type.

-- 1) Campus/user_campus support removed

-- 2) Saved posts
create table if not exists public.saved_posts (
  user_id uuid not null,
  post_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (user_id, post_id)
);

-- 3) Polls
create table if not exists public.polls (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null unique,
  question text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.poll_options (
  id uuid primary key default gen_random_uuid(),
  poll_id uuid not null references public.polls(id) on delete cascade,
  option_text text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.poll_votes (
  id uuid primary key default gen_random_uuid(),
  poll_id uuid not null references public.polls(id) on delete cascade,
  option_id uuid not null references public.poll_options(id) on delete cascade,
  user_id uuid not null,
  created_at timestamptz not null default now(),
  unique (poll_id, user_id)
);

create index if not exists idx_poll_votes_poll_id on public.poll_votes(poll_id);

-- 4) Reports (moderator queue)
create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  target_type text not null, -- 'post' | 'comment'
  target_id uuid not null,
  reason text,
  details text,
  status text not null default 'open', -- open | resolved
  created_at timestamptz not null default now()
);

-- 5) Minimal RLS suggestions (optional):
-- Enable RLS and add policies per your security model.
-- You likely already have RLS enabled.
