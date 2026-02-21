-- seed_and_triggers.sql -- v12 (Multi-Category Support)
-- This script adds a new RPC function to handle creating posts with multiple categories.

-- 1. Create the NEW RPC function for creating posts with multiple categories.
-- This function is the new, correct way to create posts.
CREATE OR REPLACE FUNCTION public.create_post_with_categories(
  p_content TEXT,
  p_anonymous BOOLEAN,
  p_category_ids INT[]
)
RETURNS UUID AS $$
DECLARE
  new_post_id UUID;
  user_auth_id UUID;
BEGIN
  -- Get the current user's authentication ID.
  user_auth_id := auth.uid();
  IF user_auth_id IS NULL THEN RAISE EXCEPTION 'User not found.'; END IF;

  -- First, insert the new post into the posts table.
  INSERT INTO public.posts (user_id, content, anonymous)
  VALUES (user_auth_id, p_content, p_anonymous)
  RETURNING id INTO new_post_id;

  -- Then, if any category IDs were provided, link them in the join table.
  IF array_length(p_category_ids, 1) > 0 THEN
    INSERT INTO public.post_categories (post_id, category_id)
    SELECT new_post_id, category_id
    FROM unnest(p_category_ids) AS category_id;
  END IF;
  
  -- The existing trigger 'trg_update_user_post_count' will handle updating the post count automatically.
  
  -- Return the ID of the newly created post.
  RETURN new_post_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 2. Keep the existing, working trigger for post counts.
CREATE OR REPLACE FUNCTION public.update_user_post_count_on_change()
RETURNS TRIGGER AS $$
DECLARE
  target_auth_id UUID;
BEGIN
  IF (TG_OP = 'INSERT') THEN
    target_auth_id := NEW.user_id;
  ELSIF (TG_OP = 'DELETE') THEN
    target_auth_id := OLD.user_id;
  END IF;

  IF target_auth_id IS NOT NULL THEN
    UPDATE public.users
    SET post_count = (
      SELECT COUNT(*) FROM public.posts WHERE user_id = target_auth_id
    )
    WHERE auth_id = target_auth_id;
  END IF;

  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Ensure the trigger is still in place.
DROP TRIGGER IF EXISTS trg_update_user_post_count ON public.posts;
CREATE TRIGGER trg_update_user_post_count
  AFTER INSERT OR DELETE ON public.posts
  FOR EACH ROW
  EXECUTE FUNCTION public.update_user_post_count_on_change();

-- 3. The one-time-fix function for recalculating counts (can be kept for maintenance).
CREATE OR REPLACE FUNCTION public.recalculate_all_user_post_counts()
RETURNS text AS $$
DECLARE
  user_record RECORD;
BEGIN
  FOR user_record IN SELECT auth_id FROM public.users LOOP
    UPDATE public.users
    SET post_count = (
      SELECT COUNT(*) FROM public.posts WHERE user_id = user_record.auth_id
    )
    WHERE auth_id = user_record.auth_id;
  END LOOP;
  RETURN 'All user post counts have been recalculated.';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
