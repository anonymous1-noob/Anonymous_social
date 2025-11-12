-- seed_and_triggers.sql -- FINAL (v4)
-- This version completely REMOVES the old trigger system and replaces it with reliable RPC functions.

-- ===================================
-- SEED DATA (for reference, can be commented out if already run)
-- ===================================

-- INSERT INTO public.users ... (rest of seed data is unchanged)

-- =================================================================
-- FINAL, RELIABLE RPC FUNCTIONS (v4)
-- This replaces the old trigger system entirely.
-- =================================================================

-- 1. Function to toggle a like on a POST and update the count
CREATE OR REPLACE FUNCTION public.toggle_post_like(post_id_input UUID)
RETURNS void AS $$
DECLARE
  user_profile_id UUID;
  existing_like_id INT;
BEGIN
  -- Find the public.users.id from the currently authenticated user
  SELECT id INTO user_profile_id FROM public.users WHERE auth_id = auth.uid();

  IF user_profile_id IS NULL THEN
    RAISE EXCEPTION 'User profile not found.';
  END IF;

  -- Check if the user has already liked this post
  SELECT id INTO existing_like_id FROM public.post_likes
  WHERE post_id = post_id_input AND user_id = user_profile_id;

  -- Toggle the like
  IF existing_like_id IS NOT NULL THEN
    -- User has liked it, so delete the like
    DELETE FROM public.post_likes WHERE id = existing_like_id;
  ELSE
    -- User has not liked it, so insert the like
    INSERT INTO public.post_likes (post_id, user_id)
    VALUES (post_id_input, user_profile_id);
  END IF;

  -- Recalculate and update the like_count on the posts table
  UPDATE public.posts
  SET like_count = (SELECT COUNT(*) FROM public.post_likes WHERE post_id = post_id_input)
  WHERE id = post_id_input;

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 2. Function to add a COMMENT to a post and update the count
CREATE OR REPLACE FUNCTION public.add_post_comment(post_id_input UUID, content_input TEXT)
RETURNS void AS $$
DECLARE
  user_profile_id UUID;
BEGIN
  SELECT id INTO user_profile_id FROM public.users WHERE auth_id = auth.uid();

  IF user_profile_id IS NULL THEN
    RAISE EXCEPTION 'User profile not found.';
  END IF;

  -- Insert the new comment
  INSERT INTO public.comments (post_id, user_id, content)
  VALUES (post_id_input, user_profile_id, content_input);

  -- Recalculate and update the comment_count on the posts table
  UPDATE public.posts
  SET comment_count = (SELECT COUNT(*) FROM public.comments WHERE post_id = post_id_input)
  WHERE id = post_id_input;

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

  IF user_profile_id IS NULL THEN
    RAISE EXCEPTION 'User profile not found.';
  END IF;

  SELECT id INTO existing_like_id FROM public.comment_likes
  WHERE comment_id = comment_id_input AND user_id = user_profile_id;

  IF existing_like_id IS NOT NULL THEN
    DELETE FROM public.comment_likes WHERE id = existing_like_id;
  ELSE
    INSERT INTO public.comment_likes (comment_id, user_id)
    VALUES (comment_id_input, user_profile_id);
  END IF;

  UPDATE public.comments
  SET like_count = (SELECT COUNT(*) FROM public.comment_likes WHERE comment_id = comment_id_input)
  WHERE id = comment_id_input;

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop the old, non-functional triggers if they exist
DROP TRIGGER IF EXISTS post_like_count_update_trigger ON public.post_likes;
DROP TRIGGER IF EXISTS post_comment_count_update_trigger ON public.comments;
DROP TRIGGER IF EXISTS comment_like_count_update_trigger ON public.comment_likes;
DROP TRIGGER IF EXISTS comment_reply_count_update_trigger ON public.comments;
