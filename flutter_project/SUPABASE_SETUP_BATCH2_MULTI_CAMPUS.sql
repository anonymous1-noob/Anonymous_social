-- Batch 2 extension: Multi-campus selection + Public posts

-- 1) Users: onboarding flag
alter table if exists public.users
  add column if not exists onboarding_done boolean default false;

-- 2) Join table for multi-campus selection
create table if not exists public.user_campuses (
  auth_id text not null,
  campus_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (auth_id, campus_id)
);

-- If your campuses.id is TEXT instead of UUID, change campus_id type above.

-- Optional FK (comment out if types mismatch)
-- alter table public.user_campuses
--   add constraint user_campuses_campus_fk foreign key (campus_id) references public.campuses(id) on delete cascade;

-- 3) Posts: allow public visibility outside campus
alter table if exists public.posts
  add column if not exists is_public boolean default false;

-- Note:
-- - If campus_id is NULL and is_public = true => global/public post
-- - If campus_id is set and is_public = false => only visible to users who selected that campus
-- - If campus_id is set and is_public = true => visible to everyone (outside campus)
