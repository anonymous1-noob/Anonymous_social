-- USER INTERESTS
create table if not exists user_interests (
  user_id uuid,
  category_id int,
  score float default 0,
  primary key (user_id, category_id)
);

-- POST ENGAGEMENT
create table if not exists post_engagement (
  post_id uuid primary key,
  likes int default 0,
  comments int default 0,
  views int default 0
);

-- USER INTERACTIONS
create table if not exists user_post_interactions (
  id uuid default gen_random_uuid() primary key,
  user_id uuid,
  post_id uuid,
  action text,
  created_at timestamp default now()
);

-- AUTHOR AFFINITY
create table if not exists user_author_affinity (
  user_id uuid,
  author_id uuid,
  score float default 0,
  primary key (user_id, author_id)
);

--------------------------------------------------
-- FUNCTION: PERSONALIZED FEED
--------------------------------------------------
create or replace function get_personalized_feed(p_user_id uuid)
returns table (
  id uuid,
  content text,
  user_id uuid,
  created_at timestamp,
  score float
)
as $$
select 
  p.id,
  p.content,
  p.user_id,
  p.created_at,

  (
    coalesce(ui.score, 0) * 3 +
    coalesce(ua.score, 0) * 2 +
    (coalesce(pe.likes,0) + coalesce(pe.comments,0)*2) * 1.5 -
    extract(epoch from (now() - p.created_at)) / 3600
  ) as score

from posts p

left join user_interests ui
  on ui.user_id = p_user_id and ui.category_id = p.category_id

left join user_author_affinity ua
  on ua.user_id = p_user_id and ua.author_id = p.user_id

left join post_engagement pe
  on pe.post_id = p.id

order by score desc
limit 50;
$$ language sql;

--------------------------------------------------
-- UPDATE USER INTEREST
--------------------------------------------------
create or replace function update_user_interest(
  p_user_id uuid,
  p_category_id int
)
returns void as $$
begin
  insert into user_interests(user_id, category_id, score)
  values (p_user_id, p_category_id, 1)
  on conflict (user_id, category_id)
  do update set score = user_interests.score + 1;
end;
$$ language plpgsql;

--------------------------------------------------
-- LIKE INCREMENT
--------------------------------------------------
create or replace function increment_like(p_post_id uuid)
returns void as $$
begin
  insert into post_engagement(post_id, likes)
  values (p_post_id, 1)
  on conflict (post_id)
  do update set likes = post_engagement.likes + 1;
end;
$$ language plpgsql;