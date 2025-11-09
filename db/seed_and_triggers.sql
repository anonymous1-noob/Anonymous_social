-- seed_and_triggers.sql
-- Contains sample seed data and triggers/functions to auto-update counts

-- Sample users (note: gen_random_uuid requires pgcrypto or pgcrypto extension; alternatively use uuid_generate_v4)
INSERT INTO public.users (id, username, email, display_name, role, status, created_at)
VALUES
  (uuid_generate_v4(), 'johndoe', 'john@example.com', 'John Doe', 'user', 'active', NOW()),
  (uuid_generate_v4(), 'janedoe', 'jane@example.com', 'Jane Doe', 'moderator', 'active', NOW()),
  (uuid_generate_v4(), 'adminuser', 'admin@example.com', 'Admin User', 'admin', 'active', NOW());

-- Sample categories
INSERT INTO public.categories (type, name, description, city, state, country, created_by, created_at)
VALUES
  ('company', 'TechCorp', 'Software company discussions', 'Bangalore', 'Karnataka', 'India', (SELECT id FROM public.users WHERE username='johndoe' LIMIT 1), NOW()),
  ('college', 'IIT Delhi', 'Engineering student group', 'Delhi', 'Delhi', 'India', (SELECT id FROM public.users WHERE username='janedoe' LIMIT 1), NOW());

-- Sample user-category associations
INSERT INTO public.user_category (user_id, category_id, role_in_category, joined_at)
SELECT u.id, c.id, 'member', NOW()
FROM public.users u, public.categories c
LIMIT 4;

-- Sample posts
INSERT INTO public.posts (id, user_id, category_id, content, anonymous, created_at)
VALUES
  (uuid_generate_v4(), (SELECT id FROM public.users WHERE username='johndoe' LIMIT 1), (SELECT id FROM public.categories WHERE name='TechCorp' LIMIT 1), 'Excited about our new product launch this week!', FALSE, NOW()),
  (uuid_generate_v4(), (SELECT id FROM public.users WHERE username='janedoe' LIMIT 1), (SELECT id FROM public.categories WHERE name='IIT Delhi' LIMIT 1), 'Exam season is here — stay strong everyone!', TRUE, NOW());

-- Sample comments
INSERT INTO public.comments (id, post_id, user_id, content, created_at)
VALUES
  (uuid_generate_v4(), (SELECT id FROM public.posts WHERE content LIKE '%product launch%' LIMIT 1), (SELECT id FROM public.users WHERE username='janedoe' LIMIT 1), 'Congrats, that\'s awesome news!', NOW()),
  (uuid_generate_v4(), (SELECT id FROM public.posts WHERE content LIKE '%Exam season%' LIMIT 1), (SELECT id FROM public.users WHERE username='johndoe' LIMIT 1), 'Good luck to everyone!', NOW());

-- ====================================
-- TRIGGERS & FUNCTIONS
-- ====================================

-- Function: update_post_like_count
CREATE OR REPLACE FUNCTION update_post_like_count()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.posts SET like_count = COALESCE(like_count, 0) + 1 WHERE id = NEW.post_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.posts SET like_count = GREATEST(COALESCE(like_count, 1) - 1, 0) WHERE id = OLD.post_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER post_like_trigger
AFTER INSERT OR DELETE ON public.post_likes
FOR EACH ROW EXECUTE FUNCTION update_post_like_count();

-- Function: update_post_comment_count
CREATE OR REPLACE FUNCTION update_post_comment_count()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.posts SET comment_count = COALESCE(comment_count, 0) + 1 WHERE id = NEW.post_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.posts SET comment_count = GREATEST(COALESCE(comment_count, 1) - 1, 0) WHERE id = OLD.post_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER post_comment_trigger
AFTER INSERT OR DELETE ON public.comments
FOR EACH ROW EXECUTE FUNCTION update_post_comment_count();

-- Function: update_comment_like_count
CREATE OR REPLACE FUNCTION update_comment_like_count()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.comments SET like_count = COALESCE(like_count, 0) + 1 WHERE id = NEW.comment_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.comments SET like_count = GREATEST(COALESCE(like_count, 1) - 1, 0) WHERE id = OLD.comment_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER comment_like_trigger
AFTER INSERT OR DELETE ON public.comment_likes
FOR EACH ROW EXECUTE FUNCTION update_comment_like_count();

-- Function: update_comment_reply_count
CREATE OR REPLACE FUNCTION update_comment_reply_count()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' AND NEW.parent_comment_id IS NOT NULL THEN
    UPDATE public.comments SET reply_count = COALESCE(reply_count, 0) + 1 WHERE id = NEW.parent_comment_id;
  ELSIF TG_OP = 'DELETE' AND OLD.parent_comment_id IS NOT NULL THEN
    UPDATE public.comments SET reply_count = GREATEST(COALESCE(reply_count, 1) - 1, 0) WHERE id = OLD.parent_comment_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER comment_reply_trigger
AFTER INSERT OR DELETE ON public.comments
FOR EACH ROW EXECUTE FUNCTION update_comment_reply_count();
