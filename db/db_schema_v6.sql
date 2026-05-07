-- anonymous_social — Schema v8 (Final, Corrected)
-- This file contains the final schema with multi-category support and media columns.

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

-- 2️⃣ CATEGORIES
CREATE TABLE IF NOT EXISTS public.categories (
  id SERIAL PRIMARY KEY,
  type TEXT NOT NULL CHECK (type IN ('company', 'college', 'region')),
  name TEXT NOT NULL,
  description TEXT,
  created_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

-- 3️⃣ USER_CATEGORY (many-to-many)
CREATE TABLE IF NOT EXISTS public.user_category (
  id SERIAL PRIMARY KEY,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  category_id INT REFERENCES public.categories(id) ON DELETE CASCADE,
  UNIQUE (user_id, category_id)
);

-- 4️⃣ POSTS (CORRECTED: Added media_url and media_path)
CREATE TABLE IF NOT EXISTS public.posts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  content TEXT NOT NULL,
  anonymous BOOLEAN DEFAULT TRUE,
  media_url TEXT, -- Added for post images
  media_path TEXT, -- Added for post images
  like_count INT DEFAULT 0,
  dislike_count INT DEFAULT 0,
  comment_count INT DEFAULT 0,
  impression_count INT DEFAULT 0,
  created_at TIMESTAMP DEFAULT NOW()
);

-- 5️⃣ POST_CATEGORIES (many-to-many join table)
CREATE TABLE IF NOT EXISTS public.post_categories (
  id SERIAL PRIMARY KEY,
  post_id UUID REFERENCES public.posts(id) ON DELETE CASCADE,
  category_id INT REFERENCES public.categories(id) ON DELETE CASCADE,
  UNIQUE (post_id, category_id)
);

-- 6️⃣ POST LIKES
CREATE TABLE IF NOT EXISTS public.post_likes (
  id SERIAL PRIMARY KEY,
  post_id UUID REFERENCES public.posts(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  UNIQUE (post_id, user_id)
);

-- 7️⃣ POST DISLIKES
CREATE TABLE IF NOT EXISTS public.post_dislikes (
  id SERIAL PRIMARY KEY,
  post_id UUID REFERENCES public.posts(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  UNIQUE (post_id, user_id)
);

-- 8️⃣ POST RATINGS
CREATE TABLE IF NOT EXISTS public.post_ratings (
  id SERIAL PRIMARY KEY,
  post_id UUID REFERENCES public.posts(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  rating INT NOT NULL CHECK (rating BETWEEN -5 AND 5),
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE (post_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_post_ratings_post_id ON public.post_ratings(post_id);

-- 9️⃣ COMMENTS
CREATE TABLE IF NOT EXISTS public.comments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  post_id UUID REFERENCES public.posts(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  parent_comment_id UUID REFERENCES public.comments(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  like_count INT DEFAULT 0,
  dislike_count INT DEFAULT 0,
  reply_count INT DEFAULT 0,
  created_at TIMESTAMP DEFAULT NOW()
);

-- 9️⃣ COMMENT LIKES
CREATE TABLE IF NOT EXISTS public.comment_likes (
  id SERIAL PRIMARY KEY,
  comment_id UUID REFERENCES public.comments(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  UNIQUE (comment_id, user_id)
);

-- 🔟 COMMENT DISLIKES
CREATE TABLE IF NOT EXISTS public.comment_dislikes (
  id SERIAL PRIMARY KEY,
  comment_id UUID REFERENCES public.comments(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  UNIQUE (comment_id, user_id)
);
