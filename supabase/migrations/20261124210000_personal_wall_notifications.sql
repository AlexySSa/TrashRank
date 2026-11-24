create extension if not exists pg_net;
create schema if not exists trashrank_private;
revoke all on schema trashrank_private from public,anon,authenticated;
create table public.wall_notification_preferences(
 member_id uuid primary key references public.members(id) on delete cascade,
 mode text not null default 'off' check(mode in ('off','own','all'))
);
alter table public.wall_notification_preferences enable row level security;
revoke all on public.wall_notification_preferences from public,anon,authenticated;
grant select,insert,update on public.wall_notification_preferences to authenticated;
grant select on public.wall_notification_preferences to service_role;
create policy wall_pref_read on public.wall_notification_preferences for select to authenticated using(member_id=(select auth.uid()) and public.my_house() is not null);
create policy wall_pref_insert on public.wall_notification_preferences for insert to authenticated with check(member_id=(select auth.uid()) and public.my_house() is not null);
create policy wall_pref_update on public.wall_notification_preferences for update to authenticated using(member_id=(select auth.uid()) and public.my_house() is not null) with check(member_id=(select auth.uid()) and public.my_house() is not null);
create table public.wall_notification_events(
 id uuid primary key default gen_random_uuid(), nonce uuid not null default gen_random_uuid(),
 house_id uuid not null references public.houses(id), actor_id uuid not null references public.members(id),
 owner_id uuid references public.members(id), kind text not null check(kind in ('post','comment','reaction','contribution')),
 target_id uuid not null, created_at timestamptz not null default now(), claimed_at timestamptz
);
create index wall_event_rate_idx on public.wall_notification_events(actor_id,created_at desc);
alter table public.wall_notification_events enable row level security;
revoke all on public.wall_notification_events from public,anon,authenticated;
grant select,update on public.wall_notification_events to service_role;
create table public.wall_notifications(
 id uuid primary key default gen_random_uuid(),event_id uuid not null references public.wall_notification_events(id) on delete cascade,
 house_id uuid not null references public.houses(id),recipient_id uuid not null references public.members(id) on delete cascade,
 actor_name text not null,kind text not null check(kind in ('post','comment','reaction','contribution')),
 is_own boolean not null,created_at timestamptz not null default now(),read_at timestamptz,
 unique(event_id,recipient_id)
);
create index wall_notice_recipient_idx on public.wall_notifications(recipient_id,created_at desc);
alter table public.wall_notifications enable row level security;
revoke all on public.wall_notifications from public,anon,authenticated;
grant select,update(read_at) on public.wall_notifications to authenticated;
grant select on public.wall_notifications to service_role;
create policy wall_notice_read on public.wall_notifications for select to authenticated using(recipient_id=(select auth.uid()) and house_id=public.my_house());
create policy wall_notice_mark on public.wall_notifications for update to authenticated using(recipient_id=(select auth.uid()) and house_id=public.my_house()) with check(recipient_id=(select auth.uid()) and house_id=public.my_house());
create function trashrank_private.wall_notice_on_insert() returns trigger language plpgsql security definer set search_path='' as $$
declare actor uuid; h uuid; owner uuid; target uuid; k text; nm text; e uuid; n uuid; count_recipients integer;
begin
 actor:=new.member_id;
 if actor is distinct from auth.uid() then return new; end if;
 select house_id,name into h,nm from public.members where id=actor and active;
 if h is null then return new; end if;
 if tg_table_name='wall_posts' then
  if new.house_id<>h then return new; end if;
  if new.parent_id is not null then k:='comment';target:=new.parent_id;select member_id into owner from public.wall_posts where id=target and house_id=h;
  elsif new.contribution_id is not null then k:='comment';target:=new.contribution_id;select member_id into owner from public.contributions where id=target and house_id=h;
  else k:='post';target:=new.id; end if;
 elsif tg_table_name='wall_reactions' then
  k:='reaction';target:=new.post_id;select member_id into owner from public.wall_posts where id=target and house_id=h;
 elsif tg_table_name='reactions' then
  k:='reaction';target:=new.contribution_id;select member_id into owner from public.contributions where id=target and house_id=h;
 elsif tg_table_name='contributions' then
  if new.house_id<>h then return new; end if;k:='contribution';target:=new.id;
 else return new; end if;
 if k in ('reaction','comment') and owner is null then return new; end if;
 if not exists(select 1 from public.members m join public.wall_notification_preferences p on p.member_id=m.id where m.house_id=h and m.active and m.id<>actor and (p.mode='all' or (p.mode='own' and m.id=owner))) then return new;end if;
 -- Serialize only notification bookkeeping for the same actor, not the whole house.
 perform pg_advisory_xact_lock(hashtextextended(actor::text,1544));
 if k='reaction' and exists(select 1 from public.wall_notification_events where actor_id=actor and target_id=target and kind=k and created_at>now()-interval '20 seconds') then return new; end if;
 if (select count(*) from public.wall_notification_events where actor_id=actor and created_at>now()-interval '1 minute')>=30 then return new; end if;
 insert into public.wall_notification_events(house_id,actor_id,owner_id,kind,target_id) values(h,actor,owner,k,target) returning id,nonce into e,n;
 insert into public.wall_notifications(event_id,house_id,recipient_id,actor_name,kind,is_own)
 select e,h,m.id,nm,k,coalesce(m.id=owner,false) from public.members m join public.wall_notification_preferences p on p.member_id=m.id
 where m.house_id=h and m.active and m.id<>actor and (p.mode='all' or (p.mode='own' and m.id=owner));
 get diagnostics count_recipients = row_count;
 if count_recipients>0 then
  begin
   perform net.http_post(url:='https://wsrrgoknvobirvktexdy.supabase.co/functions/v1/trash-notifications',body:=jsonb_build_object('action','wall-dispatch','eventId',e,'nonce',n),timeout_milliseconds:=20000);
  exception when others then
   -- An unavailable push transport must never block a valid publication.
   null;
  end;
 end if;
 return new;
end $$;
revoke all on function trashrank_private.wall_notice_on_insert() from public,anon,authenticated;
create trigger wall_notice_post after insert on public.wall_posts for each row execute function trashrank_private.wall_notice_on_insert();
create trigger wall_notice_reaction after insert on public.wall_reactions for each row execute function trashrank_private.wall_notice_on_insert();
create trigger wall_notice_contribution_reaction after insert on public.reactions for each row execute function trashrank_private.wall_notice_on_insert();
create trigger wall_notice_contribution after insert on public.contributions for each row execute function trashrank_private.wall_notice_on_insert();
alter publication supabase_realtime add table public.wall_notifications;
