-- seed_and_triggers.sql -- FINAL (v10 - Definitive Post Count Fix)
-- This script contains the final, reliable trigger logic for post counts.

-- 1. First, clean up all previous, non-working functions and triggers.
DROP TRIGGER IF EXISTS user_post_count_update_trigger ON public.posts;
DROP FUNCTION IF EXISTS public.recalculate_user_post_count();
DROP FUNCTION IF EXISTS public.handle_post_change_for_count();
DROP FUNCTION IF EXISTS public.create_post_with_count_update(integer, text, boolean);
DROP FUNCTION IF EXISTS public.fix_all_post_counts();

-- 2. Create the NEW, correct trigger function.
-- This function correctly assumes that posts.user_id is the user's auth_id.
CREATE OR REPLACE FUNCTION public.update_user_post_count_on_change()
RETURNS TRIGGER AS $$
DECLARE
  target_auth_id UUID;
BEGIN
  -- On INSERT, the user_id comes from the new row.
  IF (TG_OP = 'INSERT') THEN
    target_auth_id := NEW.user_id;
  -- On DELETE, the user_id comes from the old row.
  ELSIF (TG_OP = 'DELETE') THEN
    target_auth_id := OLD.user_id;
  END IF;

  -- Only proceed if we have a valid user_id.
  IF target_auth_id IS NOT NULL THEN
    -- Recalculate the count using the correct auth_id and update the users table.
    UPDATE public.users
    SET post_count = (
      SELECT COUNT(*) FROM public.posts WHERE user_id = target_auth_id
    )
    WHERE auth_id = target_auth_id;
  END IF;

  RETURN NULL; -- The result is ignored for AFTER triggers.
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Create the NEW, final trigger.
CREATE TRIGGER trg_update_user_post_count
  AFTER INSERT OR DELETE ON public.posts
  FOR EACH ROW
  EXECUTE FUNCTION public.update_user_post_count_on_change();

-- 4. Create the ONE-TIME-FIX function to correct existing data.
CREATE OR REPLACE FUNCTION public.recalculate_all_user_post_counts()
RETURNS text AS $$
DECLARE
  user_record RECORD;
BEGIN
  -- Loop through every user and fix their post count.
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

-- Note: Other RPC functions for likes, comments, etc., are in separate files or assumed to be correct.
