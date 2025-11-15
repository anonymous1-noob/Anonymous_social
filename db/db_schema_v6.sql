-- anonymous_social — Schema v6 (Final)
-- This file contains the final, clean schema for the database.
-- Paste this into Supabase SQL Editor and run if you need to recreate the tables.

-- 1️⃣ USERS
CREATE TABLE IF NOT EXISTS public.users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  auth_id UUID UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  username TEXT UNIQUE NOT NULL,
  email TEXT UNIQUE,
  display_name TEXT,
  avatar_url TEXT,
  role TEXT DEFAULT 'user' CHECK (role IN ('user', 'moderator', 'admin')), 
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'deactivated')),
  first_login TIMESTAMP,
  last_login TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_users_auth_id ON public.users(auth_id);
CREATE INDEX IF NOT EXISTS idx_users_username ON public.users(username);

-- 2️⃣ CATEGORIES
CREATE TABLE IF NOT EXISTS public.categories (
  id SERIAL PRIMARY KEY,
  type TEXT NOT NULL CHECK (type IN ('company', 'college', 'region')),
  name TEXT NOT NULL,
  description TEXT,
  city TEXT,
  state TEXT,
  country TEXT,
  latitude DECIMAL(9,6),
  longitude DECIMAL(9,6),
  created_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

-- 3️⃣ USER_CATEGORY (many-to-many)
CREATE TABLE IF NOT EXISTS public.user_category (
  id SERIAL PRIMARY KEY,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  category_id INT REFERENCES public.categories(id) ON DELETE CASCADE,
  role_in_category TEXT,
  joined_at TIMESTAMP DEFAULT NOW(),
  UNIQUE (user_id, category_id)
);

-- 4️⃣ POSTS
CREATE TABLE IF NOT EXISTS public.posts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  category_id INT REFERENCES public.categories(id) ON DELETE SET NULL,
  content TEXT NOT NULL,
  anonymous BOOLEAN DEFAULT TRUE,
  role_details TEXT,
  like_count INT DEFAULT 0,
  comment_count INT DEFAULT 0,
  impression_count INT DEFAULT 0,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_posts_category ON public.posts(category_id);
CREATE INDEX IF NOT EXISTS idx_posts_created_at ON public.posts(created_at DESC);

-- 5️⃣ POST LIKES
CREATE TABLE IF NOT EXISTS public.post_likes (
  id SERIAL PRIMARY KEY,
  post_id UUID REFERENCES public.posts(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE (post_id, user_id)
);

-- 6️⃣ COMMENTS (supports nesting)
CREATE TABLE IF NOT EXISTS public.comments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  post_id UUID REFERENCES public.posts(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  parent_comment_id UUID REFERENCES public.comments(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  like_count INT DEFAULT 0,
  reply_count INT DEFAULT 0,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_comments_post_id ON public.comments(post_id);
CREATE INDEX IF NOT EXISTS idx_comments_parent_id ON public.comments(parent_comment_id);

-- 7️⃣ COMMENT LIKES
CREATE TABLE IF NOT EXISTS public.comment_likes (
  id SERIAL PRIMARY KEY,
  comment_id UUID REFERENCES public.comments(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE (comment_id, user_id)
);

-- 🔒 RLS Policies should be defined in the Supabase Dashboard or a separate policy file.
-- It is recommended to enable RLS for all tables and define specific policies.

-- Example of a correct RLS policy for posts:
-- ALTER TABLE public.posts ENABLE ROW LEVEL SECURITY;
-- CREATE POLICY "Public can view all posts." ON public.posts FOR SELECT USING (true);
-- CREATE POLICY "Users can insert their own posts." ON public.posts FOR INSERT WITH CHECK (auth.uid() IN (SELECT auth_id FROM public.users WHERE id = user_id));
-- CREATE POLICY "Users can update their own posts." ON public.posts FOR UPDATE USING (auth.uid() IN (SELECT auth_id FROM public.users WHERE id = user_id));
