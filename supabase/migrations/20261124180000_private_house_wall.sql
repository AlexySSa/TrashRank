create table public.wall_posts (
 id uuid primary key default gen_random_uuid(),
 house_id uuid not null references public.houses(id),
 member_id uuid not null,
 parent_id uuid,
 contribution_id uuid references public.contributions(id) on delete cascade,
 body text not null default '' check(char_length(body)<=2000),
 media_path text,
 media_type text check(media_type in ('image','audio')),
 created_at timestamptz not null default now(),
 unique(house_id,id),
 foreign key(house_id,member_id) references public.members(house_id,id),
 foreign key(house_id,parent_id) references public.wall_posts(house_id,id) on delete cascade,
 check(parent_id is null or contribution_id is null),
 check((media_path is null)=(media_type is null)),
 check(length(trim(body))>0 or media_path is not null),
 check(media_path is null or media_path like house_id::text||'/'||member_id::text||'/%')
);
create index wall_posts_house_time on public.wall_posts(house_id,created_at desc);
create index wall_posts_parent on public.wall_posts(parent_id);
create index wall_posts_contribution on public.wall_posts(contribution_id);
alter table public.wall_posts enable row level security;
revoke all on public.wall_posts from public,anon,authenticated;
grant select,insert,delete on public.wall_posts to authenticated;
create policy wall_read on public.wall_posts for select to authenticated using(house_id=public.my_house());
create policy wall_insert on public.wall_posts for insert to authenticated with check(house_id=public.my_house() and member_id=(select auth.uid()) and (contribution_id is null or exists(select 1 from public.contributions c where c.id=contribution_id and c.house_id=public.my_house())));
create policy wall_delete on public.wall_posts for delete to authenticated using(house_id=public.my_house() and member_id=(select auth.uid()));
alter table public.reactions drop constraint reactions_pkey;
alter table public.reactions drop constraint reactions_emoji_check;
alter table public.reactions add primary key(contribution_id,member_id,emoji);
alter table public.reactions add constraint reactions_emoji_length check(char_length(emoji) between 1 and 32 and emoji !~ '[[:space:]]');
create table public.wall_reactions(
 post_id uuid not null references public.wall_posts(id) on delete cascade,
 member_id uuid not null references public.members(id),
 emoji text not null check(char_length(emoji) between 1 and 32 and emoji !~ '[[:space:]]'),
 created_at timestamptz not null default now(),
 primary key(post_id,member_id,emoji)
);
alter table public.wall_reactions enable row level security;
revoke all on public.wall_reactions from public,anon,authenticated;
grant select,insert,delete on public.wall_reactions to authenticated;
create policy wall_react_read on public.wall_reactions for select to authenticated using(exists(select 1 from public.wall_posts p where p.id=post_id and p.house_id=public.my_house()));
create policy wall_react_insert on public.wall_reactions for insert to authenticated with check(member_id=(select auth.uid()) and exists(select 1 from public.wall_posts p where p.id=post_id and p.house_id=public.my_house()));
create policy wall_react_delete on public.wall_reactions for delete to authenticated using(member_id=(select auth.uid()) and exists(select 1 from public.wall_posts p where p.id=post_id and p.house_id=public.my_house()));
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('wall-media','wall-media',false,5242880,array['image/jpeg','image/png','image/webp','image/gif','audio/webm','audio/ogg','audio/mpeg','audio/mp4','audio/wav','audio/x-wav','audio/aac','audio/x-m4a']);
create policy wall_media_read on storage.objects for select to authenticated using(bucket_id='wall-media' and (storage.foldername(name))[1]=public.my_house()::text);
create policy wall_media_insert on storage.objects for insert to authenticated with check(bucket_id='wall-media' and (storage.foldername(name))[1]=public.my_house()::text and (storage.foldername(name))[2]=(select auth.uid())::text);
create policy wall_media_delete on storage.objects for delete to authenticated using(bucket_id='wall-media' and (storage.foldername(name))[1]=public.my_house()::text and (storage.foldername(name))[2]=(select auth.uid())::text);
alter publication supabase_realtime add table public.wall_posts,public.wall_reactions;