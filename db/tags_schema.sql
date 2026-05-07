-- anonymous_social — Production hashtag indexing
-- Apply this after the base schema. It replaces client-side hashtag scans with
-- trigger-maintained tag indexes that are safe to query from the app.

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pg_trgm;

ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN DEFAULT FALSE;
ALTER TABLE public.comments ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN DEFAULT FALSE;

CREATE TABLE IF NOT EXISTS public.tags (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  normalized_name TEXT NOT NULL UNIQUE,
  post_count INT NOT NULL DEFAULT 0 CHECK (post_count >= 0),
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  CHECK (normalized_name ~ '^[a-z0-9_]+$')
);

CREATE TABLE IF NOT EXISTS public.post_tag_mentions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  post_id UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  tag_id UUID NOT NULL REFERENCES public.tags(id) ON DELETE CASCADE,
  source_type TEXT NOT NULL CHECK (source_type IN ('post', 'comment')),
  source_id UUID NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE (source_type, source_id, tag_id)
);

CREATE TABLE IF NOT EXISTS public.post_tags (
  post_id UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  tag_id UUID NOT NULL REFERENCES public.tags(id) ON DELETE CASCADE,
  created_at TIMESTAMP DEFAULT NOW(),
  PRIMARY KEY (post_id, tag_id)
);

CREATE INDEX IF NOT EXISTS idx_tags_normalized_name ON public.tags (normalized_name);
CREATE INDEX IF NOT EXISTS idx_tags_post_count ON public.tags (post_count DESC, normalized_name ASC);
CREATE INDEX IF NOT EXISTS idx_tags_normalized_name_trgm ON public.tags USING gin (normalized_name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_post_tag_mentions_post_id ON public.post_tag_mentions (post_id);
CREATE INDEX IF NOT EXISTS idx_post_tag_mentions_tag_id ON public.post_tag_mentions (tag_id);
CREATE INDEX IF NOT EXISTS idx_post_tags_tag_id_post_id ON public.post_tags (tag_id, post_id);

ALTER TABLE public.tags ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tags_select_all ON public.tags;
CREATE POLICY tags_select_all ON public.tags
  FOR SELECT USING (true);


CREATE OR REPLACE FUNCTION public.extract_hashtags(input_text TEXT)
RETURNS TEXT[]
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT COALESCE(array_agg(DISTINCT lower(match[1]) ORDER BY lower(match[1])), ARRAY[]::TEXT[])
  FROM regexp_matches(COALESCE(input_text, ''), '(?:^|[^A-Za-z0-9_])#([A-Za-z0-9_]+)', 'g') AS match;
$$;

CREATE OR REPLACE FUNCTION public.upsert_hashtag(tag_name TEXT)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  normalized TEXT := lower(trim(leading '#' from COALESCE(tag_name, '')));
  tag_id UUID;
BEGIN
  IF normalized = '' OR normalized !~ '^[a-z0-9_]+$' THEN
    RAISE EXCEPTION 'Invalid hashtag: %', tag_name;
  END IF;

  INSERT INTO public.tags (name, normalized_name, updated_at)
  VALUES ('#' || normalized, normalized, NOW())
  ON CONFLICT (normalized_name) DO UPDATE
    SET updated_at = NOW()
  RETURNING id INTO tag_id;

  RETURN tag_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.rebuild_post_tags_for_post(target_post_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.post_tags WHERE post_id = target_post_id;

  INSERT INTO public.post_tags (post_id, tag_id)
  SELECT DISTINCT post_id, tag_id
  FROM public.post_tag_mentions
  WHERE post_id = target_post_id
  ON CONFLICT DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_tag_post_counts(target_tag_ids UUID[])
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF target_tag_ids IS NULL OR cardinality(target_tag_ids) = 0 THEN
    RETURN;
  END IF;

  UPDATE public.tags t
  SET post_count = COALESCE(counts.post_count, 0), updated_at = NOW()
  FROM (
    SELECT target.id, COUNT(p.id)::INT AS post_count
    FROM unnest(target_tag_ids) AS target(id)
    LEFT JOIN public.post_tags pt ON pt.tag_id = target.id
    LEFT JOIN public.posts p ON p.id = pt.post_id AND COALESCE(p.is_deleted, false) = false
    GROUP BY target.id
  ) counts
  WHERE counts.id = t.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_post_hashtags(target_post_id UUID, source_content TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  tag TEXT;
  tag_id UUID;
  affected_tag_ids UUID[] := ARRAY[]::UUID[];
BEGIN
  SELECT COALESCE(array_agg(tag_id), ARRAY[]::UUID[]) INTO affected_tag_ids
  FROM public.post_tag_mentions
  WHERE source_type = 'post' AND source_id = target_post_id;

  DELETE FROM public.post_tag_mentions
  WHERE source_type = 'post' AND source_id = target_post_id;

  FOREACH tag IN ARRAY public.extract_hashtags(source_content)
  LOOP
    tag_id := public.upsert_hashtag(tag);
    affected_tag_ids := array_append(affected_tag_ids, tag_id);
    INSERT INTO public.post_tag_mentions (post_id, tag_id, source_type, source_id)
    VALUES (target_post_id, tag_id, 'post', target_post_id)
    ON CONFLICT DO NOTHING;
  END LOOP;

  PERFORM public.rebuild_post_tags_for_post(target_post_id);
  SELECT array_agg(DISTINCT id) INTO affected_tag_ids FROM unnest(affected_tag_ids) AS ids(id);
  PERFORM public.update_tag_post_counts(affected_tag_ids);
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_comment_hashtags(target_comment_id UUID, target_post_id UUID, source_content TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  tag TEXT;
  tag_id UUID;
  affected_post_id UUID;
  affected_tag_ids UUID[] := ARRAY[]::UUID[];
BEGIN
  SELECT post_id INTO affected_post_id
  FROM public.post_tag_mentions
  WHERE source_type = 'comment' AND source_id = target_comment_id
  LIMIT 1;

  SELECT COALESCE(array_agg(tag_id), ARRAY[]::UUID[]) INTO affected_tag_ids
  FROM public.post_tag_mentions
  WHERE source_type = 'comment' AND source_id = target_comment_id;

  affected_post_id := COALESCE(affected_post_id, target_post_id);

  DELETE FROM public.post_tag_mentions
  WHERE source_type = 'comment' AND source_id = target_comment_id;

  FOREACH tag IN ARRAY public.extract_hashtags(source_content)
  LOOP
    tag_id := public.upsert_hashtag(tag);
    affected_tag_ids := array_append(affected_tag_ids, tag_id);
    INSERT INTO public.post_tag_mentions (post_id, tag_id, source_type, source_id)
    VALUES (target_post_id, tag_id, 'comment', target_comment_id)
    ON CONFLICT DO NOTHING;
  END LOOP;

  IF affected_post_id IS NOT NULL THEN
    PERFORM public.rebuild_post_tags_for_post(affected_post_id);
  END IF;
  IF target_post_id IS NOT NULL AND target_post_id <> affected_post_id THEN
    PERFORM public.rebuild_post_tags_for_post(target_post_id);
  END IF;
  SELECT array_agg(DISTINCT id) INTO affected_tag_ids FROM unnest(affected_tag_ids) AS ids(id);
  PERFORM public.update_tag_post_counts(affected_tag_ids);
END;
$$;

CREATE OR REPLACE FUNCTION public.handle_post_hashtags()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  affected_tag_ids UUID[] := ARRAY[]::UUID[];
BEGIN
  IF TG_OP = 'DELETE' THEN
    SELECT COALESCE(array_agg(tag_id), ARRAY[]::UUID[]) INTO affected_tag_ids
    FROM public.post_tag_mentions
    WHERE source_type = 'post' AND source_id = OLD.id;

    DELETE FROM public.post_tag_mentions
    WHERE source_type = 'post' AND source_id = OLD.id;
    PERFORM public.rebuild_post_tags_for_post(OLD.id);
    PERFORM public.update_tag_post_counts(affected_tag_ids);
    RETURN OLD;
  END IF;

  PERFORM public.sync_post_hashtags(NEW.id, NEW.content);

  IF TG_OP = 'UPDATE' AND OLD.is_deleted IS DISTINCT FROM NEW.is_deleted THEN
    PERFORM public.update_tag_post_counts(ARRAY(
      SELECT DISTINCT tag_id FROM public.post_tag_mentions WHERE post_id = NEW.id
    ));
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.handle_comment_hashtags()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  old_post_id UUID;
  affected_tag_ids UUID[] := ARRAY[]::UUID[];
BEGIN
  IF TG_OP = 'DELETE' THEN
    old_post_id := OLD.post_id;
    SELECT COALESCE(array_agg(tag_id), ARRAY[]::UUID[]) INTO affected_tag_ids
    FROM public.post_tag_mentions
    WHERE source_type = 'comment' AND source_id = OLD.id;

    DELETE FROM public.post_tag_mentions
    WHERE source_type = 'comment' AND source_id = OLD.id;
    PERFORM public.rebuild_post_tags_for_post(old_post_id);
    PERFORM public.update_tag_post_counts(affected_tag_ids);
    RETURN OLD;
  END IF;

  PERFORM public.sync_comment_hashtags(
    NEW.id,
    NEW.post_id,
    CASE WHEN COALESCE(NEW.is_deleted, false) THEN '' ELSE NEW.content END
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS posts_hashtags_sync ON public.posts;
CREATE TRIGGER posts_hashtags_sync
AFTER INSERT OR UPDATE OF content, is_deleted ON public.posts
FOR EACH ROW EXECUTE FUNCTION public.handle_post_hashtags();

DROP TRIGGER IF EXISTS comments_hashtags_sync ON public.comments;
CREATE TRIGGER comments_hashtags_sync
AFTER INSERT OR UPDATE OF content, is_deleted ON public.comments
FOR EACH ROW EXECUTE FUNCTION public.handle_comment_hashtags();

CREATE OR REPLACE FUNCTION public.rebuild_all_hashtags()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  post_row RECORD;
  comment_row RECORD;
BEGIN
  TRUNCATE public.post_tag_mentions, public.post_tags RESTART IDENTITY;
  UPDATE public.tags SET post_count = 0, updated_at = NOW();

  FOR post_row IN SELECT id, content FROM public.posts LOOP
    PERFORM public.sync_post_hashtags(post_row.id, post_row.content);
  END LOOP;

  FOR comment_row IN SELECT id, post_id, content FROM public.comments LOOP
    PERFORM public.sync_comment_hashtags(comment_row.id, comment_row.post_id, comment_row.content);
  END LOOP;

  PERFORM public.update_tag_post_counts(ARRAY(SELECT id FROM public.tags));
  DELETE FROM public.tags WHERE post_count = 0;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_posts_for_tag(tag_name TEXT)
RETURNS TABLE (id UUID, content TEXT, created_at TIMESTAMP)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p.id, p.content, p.created_at
  FROM public.tags t
  JOIN public.post_tags pt ON pt.tag_id = t.id
  JOIN public.posts p ON p.id = pt.post_id
  WHERE t.normalized_name = lower(trim(leading '#' from COALESCE(tag_name, '')))
    AND COALESCE(p.is_deleted, false) = false
  ORDER BY p.created_at DESC;
$$;


REVOKE EXECUTE ON FUNCTION public.upsert_hashtag(TEXT) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.rebuild_post_tags_for_post(UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.update_tag_post_counts(UUID[]) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.sync_post_hashtags(UUID, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.sync_comment_hashtags(UUID, UUID, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.handle_post_hashtags() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.handle_comment_hashtags() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.rebuild_all_hashtags() FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.get_posts_for_tag(TEXT) TO anon, authenticated;

-- Run once after applying this migration to backfill tags from existing data:
-- SELECT public.rebuild_all_hashtags();
