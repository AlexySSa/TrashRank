create table public.trash_alerts(
 id uuid primary key default gen_random_uuid(), house_id uuid not null references public.houses(id),
 admin_id uuid not null, assignee_id uuid not null, assignee_name text not null,
 created_at timestamptz not null default now(),
 foreign key(house_id,admin_id) references public.members(house_id,id),
 foreign key(house_id,assignee_id) references public.members(house_id,id)
);
create index trash_alerts_house_time on public.trash_alerts(house_id,created_at desc);
alter table public.trash_alerts enable row level security;
revoke all on public.trash_alerts from public,anon,authenticated;
grant select on public.trash_alerts to authenticated;
grant all on public.trash_alerts to service_role;
create policy alert_read on public.trash_alerts for select to authenticated using(house_id=public.my_house());
create table public.trash_alert_reads(alert_id uuid not null references public.trash_alerts(id) on delete cascade, member_id uuid not null references public.members(id), read_at timestamptz not null default now(), primary key(alert_id,member_id));
alter table public.trash_alert_reads enable row level security;
revoke all on public.trash_alert_reads from public,anon,authenticated;
grant select,insert on public.trash_alert_reads to authenticated;
grant all on public.trash_alert_reads to service_role;
create policy alert_reads_select on public.trash_alert_reads for select to authenticated using(member_id=(select auth.uid()) and exists(select 1 from public.trash_alerts a where a.id=alert_id and a.house_id=public.my_house()));
create policy alert_reads_insert on public.trash_alert_reads for insert to authenticated with check(member_id=(select auth.uid()) and exists(select 1 from public.trash_alerts a where a.id=alert_id and a.house_id=public.my_house()));
create table public.trash_push_subscriptions(endpoint text primary key check(length(endpoint)<=2048), member_id uuid not null references public.members(id) on delete cascade, p256dh text not null check(length(p256dh)<=128), auth text not null check(length(auth)<=64), updated_at timestamptz not null default now());
create index trash_push_member on public.trash_push_subscriptions(member_id);
alter table public.trash_push_subscriptions enable row level security;
revoke all on public.trash_push_subscriptions from public,anon,authenticated;
grant all on public.trash_push_subscriptions to service_role;
create table public.trash_push_keys(id integer primary key check(id=1),public_key text not null,private_key text not null);
alter table public.trash_push_keys enable row level security;
revoke all on public.trash_push_keys from public,anon,authenticated;
grant all on public.trash_push_keys to service_role;
create function public.create_trash_alert(p_admin uuid,p_assignee uuid) returns public.trash_alerts language plpgsql security invoker set search_path='' as $$
declare h uuid; n text; result public.trash_alerts;
begin
 select house_id into h from public.members where id=p_admin and active and role='admin';
 if h is null then raise exception 'Solo el administrador puede enviar avisos'; end if;
 perform pg_advisory_xact_lock(hashtextextended(h::text,731));
 select name into n from public.members where id=p_assignee and house_id=h and active;
 if n is null then raise exception 'Responsable inválido'; end if;
 if exists(select 1 from public.trash_alerts a where a.house_id=h and not exists(select 1 from public.contributions c where c.house_id=h and c.created_at>=a.created_at)) then raise exception 'Ya hay un aviso pendiente. Se cerrará al registrar la basura.'; end if;
 if exists(select 1 from public.trash_alerts a where a.house_id=h and a.created_at>now()-interval '60 seconds') then raise exception 'Espera un minuto antes de enviar otro aviso'; end if;
 insert into public.trash_alerts(house_id,admin_id,assignee_id,assignee_name) values(h,p_admin,p_assignee,n) returning * into result;
 return result;
end $$;
revoke execute on function public.create_trash_alert(uuid,uuid) from public,anon,authenticated;
grant execute on function public.create_trash_alert(uuid,uuid) to service_role;
alter publication supabase_realtime add table public.trash_alerts,public.trash_alert_reads;
