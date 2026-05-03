-- Batch 2 extension: Multi-campus selection + Public posts

-- 1) Users: onboarding flag
alter table if exists public.users
  add column if not exists onboarding_done boolean default false;

-- 2) user_campuses removed.

-- 3) Posts: allow public visibility outside campus
alter table if exists public.posts
  add column if not exists is_public boolean default false;

-- Note:
-- - If campus_id is NULL and is_public = true => global/public post
-- - If campus_id is set and is_public = false => only visible to users who selected that campus
-- - If campus_id is set and is_public = true => visible to everyone (outside campus)
