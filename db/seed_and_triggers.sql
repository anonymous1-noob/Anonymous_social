-- seed_and_triggers.sql -- FINAL (v5)
-- Adds a function to update user login timestamps.

-- =================================================================
-- FINAL, RELIABLE RPC FUNCTIONS (v5)
-- =================================================================

-- 1. Function to toggle a like on a POST and update the count
CREATE OR REPLACE FUNCTION public.toggle_post_like(post_id_input UUID)
RETURNS void AS $$
DECLARE
  user_profile_id UUID;
  existing_like_id INT;
BEGIN
  SELECT id INTO user_profile_id FROM public.users WHERE auth_id = auth.uid();
  IF user_profile_id IS NULL THEN RAISE EXCEPTION 'User profile not found.'; END IF;

  SELECT id INTO existing_like_id FROM public.post_likes WHERE post_id = post_id_input AND user_id = user_profile_id;

  IF existing_like_id IS NOT NULL THEN
    DELETE FROM public.post_likes WHERE id = existing_like_id;
  ELSE
    INSERT INTO public.post_likes (post_id, user_id) VALUES (post_id_input, user_profile_id);
  END IF;

  UPDATE public.posts SET like_count = (SELECT COUNT(*) FROM public.post_likes WHERE post_id = post_id_input) WHERE id = post_id_input;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 2. Function to add a COMMENT to a post and update the count
CREATE OR REPLACE FUNCTION public.add_post_comment(post_id_input UUID, content_input TEXT)
RETURNS void AS $$
DECLARE
  user_profile_id UUID;
BEGIN
  SELECT id INTO user_profile_id FROM public.users WHERE auth_id = auth.uid();
  IF user_profile_id IS NULL THEN RAISE EXCEPTION 'User profile not found.'; END IF;

  INSERT INTO public.comments (post_id, user_id, content) VALUES (post_id_input, user_profile_id, content_input);

  UPDATE public.posts SET comment_count = (SELECT COUNT(*) FROM public.comments WHERE post_id = post_id_input) WHERE id = post_id_input;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Function to toggle a like on a COMMENT and update the count
CREATE OR REPLACE FUNCTION public.toggle_comment_like(comment_id_input UUID)
RETURNS void AS $$
DECLARE
  user_profile_id UUID;
  existing_like_id INT;
BEGIN
  SELECT id INTO user_profile_id FROM public.users WHERE auth_id = auth.uid();
  IF user_profile_id IS NULL THEN RAISE EXCEPTION 'User profile not found.'; END IF;

  SELECT id INTO existing_like_id FROM public.comment_likes WHERE comment_id = comment_id_input AND user_id = user_profile_id;

  IF existing_like_id IS NOT NULL THEN
    DELETE FROM public.comment_likes WHERE id = existing_like_id;
  ELSE
    INSERT INTO public.comment_likes (comment_id, user_id) VALUES (comment_id_input, user_profile_id);
  END IF;

  UPDATE public.comments SET like_count = (SELECT COUNT(*) FROM public.comment_likes WHERE comment_id = comment_id_input) WHERE id = comment_id_input;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 4. Function to update user login timestamps (NEW).
CREATE OR REPLACE FUNCTION public.update_user_login_timestamps()
RETURNS void AS $$
BEGIN
  UPDATE public.users
  SET 
    first_login = COALESCE(first_login, NOW()),
    last_login = NOW()
  WHERE auth_id = auth.uid();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Drop the old, non-functional triggers if they exist
DROP TRIGGER IF EXISTS post_like_count_update_trigger ON public.post_likes;
DROP TRIGGER IF EXISTS post_comment_count_update_trigger ON public.comments;
DROP TRIGGER IF EXISTS comment_like_count_update_trigger ON public.comment_likes;
DROP TRIGGER IF EXISTS comment_reply_count_update_trigger ON public.comments;
