-- seed_and_triggers.sql -- FINAL (v6)
-- Adds dislike functionality for comments.

-- =================================================================
-- RPC FUNCTIONS (v6)
-- =================================================================

-- 1. Function to toggle a LIKE on a POST.
CREATE OR REPLACE FUNCTION public.toggle_post_like(post_id_input UUID)
RETURNS void AS $$
DECLARE
  user_profile_id UUID;
BEGIN
  SELECT id INTO user_profile_id FROM public.users WHERE auth_id = auth.uid();
  IF user_profile_id IS NULL THEN RAISE EXCEPTION 'User profile not found.'; END IF;
  DELETE FROM public.post_dislikes WHERE post_id = post_id_input AND user_id = user_profile_id;
  IF EXISTS (SELECT 1 FROM public.post_likes WHERE post_id = post_id_input AND user_id = user_profile_id) THEN
    DELETE FROM public.post_likes WHERE post_id = post_id_input AND user_id = user_profile_id;
  ELSE
    INSERT INTO public.post_likes (post_id, user_id) VALUES (post_id_input, user_profile_id);
  END IF;
  UPDATE public.posts
  SET
    like_count = (SELECT COUNT(*) FROM public.post_likes WHERE post_id = post_id_input),
    dislike_count = (SELECT COUNT(*) FROM public.post_dislikes WHERE post_id = post_id_input)
  WHERE id = post_id_input;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 2. Function to toggle a DISLIKE on a POST.
CREATE OR REPLACE FUNCTION public.toggle_post_dislike(post_id_input UUID)
RETURNS void AS $$
DECLARE
  user_profile_id UUID;
BEGIN
  SELECT id INTO user_profile_id FROM public.users WHERE auth_id = auth.uid();
  IF user_profile_id IS NULL THEN RAISE EXCEPTION 'User profile not found.'; END IF;
  DELETE FROM public.post_likes WHERE post_id = post_id_input AND user_id = user_profile_id;
  IF EXISTS (SELECT 1 FROM public.post_dislikes WHERE post_id = post_id_input AND user_id = user_profile_id) THEN
    DELETE FROM public.post_dislikes WHERE post_id = post_id_input AND user_id = user_profile_id;
  ELSE
    INSERT INTO public.post_dislikes (post_id, user_id) VALUES (post_id_input, user_profile_id);
  END IF;
  UPDATE public.posts
  SET
    like_count = (SELECT COUNT(*) FROM public.post_likes WHERE post_id = post_id_input),
    dislike_count = (SELECT COUNT(*) FROM public.post_dislikes WHERE post_id = post_id_input)
  WHERE id = post_id_input;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 3. Function to add a COMMENT to a post.
CREATE OR REPLACE FUNCTION public.add_post_comment(post_id_input UUID, content_input TEXT)
RETURNS void AS $$
DECLARE
  user_profile_id UUID;
BEGIN
  SELECT id INTO user_profile_id FROM public.users WHERE auth_id = auth.uid();
  IF user_profile_id IS NULL THEN RAISE EXCEPTION 'User profile not found.'; END IF;
  INSERT INTO public.comments (post_id, user_id, content) VALUES (post_id_input, user_profile_id, content_input);
  UPDATE public.posts
  SET comment_count = (SELECT COUNT(*) FROM public.comments WHERE post_id = post_id_input)
  WHERE id = post_id_input;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 4. Function to toggle a LIKE on a COMMENT.
CREATE OR REPLACE FUNCTION public.toggle_comment_like(comment_id_input UUID)
RETURNS void AS $$
DECLARE
  user_profile_id UUID;
BEGIN
  SELECT id INTO user_profile_id FROM public.users WHERE auth_id = auth.uid();
  IF user_profile_id IS NULL THEN RAISE EXCEPTION 'User profile not found.'; END IF;
  DELETE FROM public.comment_dislikes WHERE comment_id = comment_id_input AND user_id = user_profile_id;
  IF EXISTS (SELECT 1 FROM public.comment_likes WHERE comment_id = comment_id_input AND user_id = user_profile_id) THEN
    DELETE FROM public.comment_likes WHERE comment_id = comment_id_input AND user_id = user_profile_id;
  ELSE
    INSERT INTO public.comment_likes (comment_id, user_id) VALUES (comment_id_input, user_profile_id);
  END IF;
  UPDATE public.comments
  SET
    like_count = (SELECT COUNT(*) FROM public.comment_likes WHERE comment_id = comment_id_input),
    dislike_count = (SELECT COUNT(*) FROM public.comment_dislikes WHERE comment_id = comment_id_input)
  WHERE id = comment_id_input;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 5. Function to toggle a DISLIKE on a COMMENT (New).
CREATE OR REPLACE FUNCTION public.toggle_comment_dislike(comment_id_input UUID)
RETURNS void AS $$
DECLARE
  user_profile_id UUID;
BEGIN
  SELECT id INTO user_profile_id FROM public.users WHERE auth_id = auth.uid();
  IF user_profile_id IS NULL THEN RAISE EXCEPTION 'User profile not found.'; END IF;
  DELETE FROM public.comment_likes WHERE comment_id = comment_id_input AND user_id = user_profile_id;
  IF EXISTS (SELECT 1 FROM public.comment_dislikes WHERE comment_id = comment_id_input AND user_id = user_profile_id) THEN
    DELETE FROM public.comment_dislikes WHERE comment_id = comment_id_input AND user_id = user_profile_id;
  ELSE
    INSERT INTO public.comment_dislikes (comment_id, user_id) VALUES (comment_id_input, user_profile_id);
  END IF;
  UPDATE public.comments
  SET
    like_count = (SELECT COUNT(*) FROM public.comment_likes WHERE comment_id = comment_id_input),
    dislike_count = (SELECT COUNT(*) FROM public.comment_dislikes WHERE comment_id = comment_id_input)
  WHERE id = comment_id_input;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Drop old, unused triggers
DROP TRIGGER IF EXISTS post_like_count_update_trigger ON public.post_likes;
DROP TRIGGER IF EXISTS post_comment_count_update_trigger ON public.comments;
DROP TRIGGER IF EXISTS comment_like_count_update_trigger ON public.comment_likes;
DROP TRIGGER IF EXISTS comment_reply_count_update_trigger ON public.comments;
