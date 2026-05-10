-- anonymous_social — Follow requests with approval
-- Run this after the base schema to enable private follow approvals.

CREATE TABLE IF NOT EXISTS public.user_follows (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  follower_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  following_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved')),
  requested_at TIMESTAMP DEFAULT NOW(),
  responded_at TIMESTAMP,
  CHECK (follower_id <> following_id),
  UNIQUE (follower_id, following_id)
);

CREATE INDEX IF NOT EXISTS user_follows_follower_idx
  ON public.user_follows (follower_id, status);

CREATE INDEX IF NOT EXISTS user_follows_following_idx
  ON public.user_follows (following_id, status);
