create table public.reactions (
 contribution_id uuid not null references public.contributions(id) on delete cascade,
 member_id uuid not null references public.members(id),
 emoji text not null check (emoji in ('👏','🔥','💚')),
 created_at timestamptz not null default now(),
 primary key(contribution_id,member_id)
);
alter table public.reactions enable row level security;
revoke all on public.reactions from public,anon,authenticated;
grant select,insert,update,delete on public.reactions to authenticated;
create policy reaction_read on public.reactions for select to authenticated using (exists(select 1 from public.contributions c where c.id=contribution_id and c.house_id=public.my_house()));
create policy reaction_insert on public.reactions for insert to authenticated with check (member_id=(select auth.uid()) and exists(select 1 from public.contributions c where c.id=contribution_id and c.house_id=public.my_house()));
create policy reaction_update on public.reactions for update to authenticated using (member_id=(select auth.uid()) and exists(select 1 from public.contributions c where c.id=contribution_id and c.house_id=public.my_house())) with check (member_id=(select auth.uid()) and exists(select 1 from public.contributions c where c.id=contribution_id and c.house_id=public.my_house()));
create policy reaction_delete on public.reactions for delete to authenticated using (member_id=(select auth.uid()) and exists(select 1 from public.contributions c where c.id=contribution_id and c.house_id=public.my_house()));
alter publication supabase_realtime add table public.reactions;
