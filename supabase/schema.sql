-- Run once in a new Supabase project. All writes go through controlled RPCs.
create extension if not exists pgcrypto with schema extensions;
create table public.houses(id uuid primary key default gen_random_uuid(), name text not null check(length(name) between 1 and 80), timezone text not null default 'Europe/Berlin', invite_code text not null unique default encode(extensions.gen_random_bytes(12),'hex'), ranking_since timestamptz not null default '-infinity', created_at timestamptz not null default now());
create table public.members(id uuid primary key, house_id uuid not null references public.houses(id), username text not null unique check(username ~ '^[a-z0-9_]{3,24}$'), name text not null check(length(name) between 1 and 80), avatar text, role text not null default 'member' check(role in ('admin','member')), active boolean not null default true, created_at timestamptz not null default now(), unique(house_id,id));
create table public.contributions(id uuid primary key default gen_random_uuid(), house_id uuid not null references public.houses(id), member_id uuid not null, kind text not null default 'general' check(kind in ('general','organica','plastico','papel','vidrio')), created_at timestamptz not null default now(), request_id uuid unique not null default gen_random_uuid(), foreign key(house_id,member_id) references public.members(house_id,id));
create index contributions_house_date on public.contributions(house_id,created_at desc);
create index contributions_member_date on public.contributions(member_id,created_at desc);
alter table public.houses enable row level security;
alter table public.members enable row level security;
alter table public.contributions enable row level security;
revoke all on public.houses,public.members,public.contributions from anon,authenticated;
grant select(id,name,timezone,ranking_since,created_at) on public.houses to authenticated;
grant select on public.members,public.contributions to authenticated;
create function public.my_house() returns uuid language sql stable security definer set search_path='' as $$select house_id from public.members where id=auth.uid() and active$$;
create function public.is_admin() returns boolean language sql stable security definer set search_path='' as $$select coalesce((select role='admin' from public.members where id=auth.uid() and active),false)$$;
create policy house_read on public.houses for select to authenticated using(id=public.my_house());
create policy members_read on public.members for select to authenticated using(house_id=public.my_house());
create policy records_read on public.contributions for select to authenticated using(house_id=public.my_house());
create function public.setup_house(p_name text,p_house text,p_code text) returns uuid language plpgsql security definer set search_path='' as $$
declare h uuid; u uuid:=auth.uid(); uname text;
begin
 if u is null then raise exception 'Inicia sesión'; end if;
 perform pg_advisory_xact_lock(hashtextextended(u::text,0));
 if exists(select 1 from public.members where id=u) then raise exception 'Esta cuenta ya pertenece a una casa'; end if;
 select split_part(email,'@',1) into uname from auth.users where id=u and split_part(email,'@',2)='trashrank.invalid';
 if uname is null then raise exception 'Usuario inválido'; end if;
 if p_code is not null then
  select id into h from public.houses where invite_code=lower(trim(p_code));
  if h is null then raise exception 'Código de invitación inválido'; end if;
  insert into public.members(id,house_id,username,name) values(u,h,uname,trim(p_name));
 else
  insert into public.houses(name) values(trim(p_house)) returning id into h;
  insert into public.members(id,house_id,username,name,role) values(u,h,uname,trim(p_name),'admin');
 end if;
 return h;
end$$;
create function public.record_trash(p_kind text,p_request uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare h uuid:=public.my_house(); u uuid:=auth.uid(); r uuid;
begin
 if h is null then raise exception 'No tienes una casa activa'; end if;
 perform pg_advisory_xact_lock(hashtextextended(u::text,0));
 select id into r from public.contributions where request_id=p_request and member_id=u;
 if r is not null then return r; end if;
 if exists(select 1 from public.contributions where member_id=u and created_at>now()-interval '60 seconds') then raise exception 'Ya registraste una contribución hace menos de un minuto'; end if;
 insert into public.contributions(house_id,member_id,kind,request_id) values(h,u,p_kind,p_request) returning id into r;
 return r;
end$$;
create function public.update_profile(p_name text,p_avatar text) returns void language plpgsql security definer set search_path='' as $$
begin
 if public.my_house() is null then raise exception 'Sin acceso'; end if;
 if p_avatar is not null and p_avatar not like public.my_house()::text||'/'||auth.uid()::text||'/%' then raise exception 'Foto inválida'; end if;
 update public.members set name=trim(p_name),avatar=p_avatar where id=auth.uid() and active;
end$$;
create function public.admin_house(p_action text,p_name text default null,p_timezone text default null) returns text language plpgsql security definer set search_path='' as $$
declare h uuid:=public.my_house(); c text;
begin
 if not public.is_admin() then raise exception 'Sin permiso'; end if;
 case p_action
 when 'code' then select invite_code into c from public.houses where id=h;
 when 'rotate' then update public.houses set invite_code=encode(extensions.gen_random_bytes(12),'hex') where id=h returning invite_code into c;
 when 'reset' then update public.houses set ranking_since=now() where id=h;
 when 'edit' then
  if not exists(select 1 from pg_catalog.pg_timezone_names where name=p_timezone) then raise exception 'Zona horaria inválida'; end if;
  update public.houses set name=trim(p_name),timezone=p_timezone where id=h;
 else raise exception 'Acción inválida'; end case;
 return c;
end$$;
create function public.admin_member(p_id uuid,p_name text,p_remove boolean default false) returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception 'Sin permiso'; end if;
 if p_remove and p_id=auth.uid() then raise exception 'No puedes eliminar al administrador'; end if;
 update public.members set name=case when p_remove then name else trim(p_name) end,active=case when p_remove then false else active end where id=p_id and house_id=public.my_house() and active;
 if not found then raise exception 'Miembro no encontrado'; end if;
end$$;
create function public.admin_record(p_id uuid,p_delete boolean,p_kind text default null,p_date timestamptz default null,p_member uuid default null) returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception 'Sin permiso'; end if;
 if p_delete then delete from public.contributions where id=p_id and house_id=public.my_house();
 else update public.contributions set kind=p_kind,created_at=p_date,member_id=p_member where id=p_id and house_id=public.my_house(); end if;
 if not found then raise exception 'Registro no encontrado'; end if;
end$$;
create function public.server_add_member(p_admin uuid,p_id uuid,p_username text,p_name text) returns void language plpgsql security definer set search_path='' as $$
declare h uuid;
begin
 select house_id into h from public.members where id=p_admin and active and role='admin' for update;
 if h is null then raise exception 'Sin permiso'; end if;
 insert into public.members(id,house_id,username,name) values(p_id,h,p_username,trim(p_name));
end$$;
revoke execute on function public.my_house(),public.is_admin(),public.setup_house(text,text,text),public.record_trash(text,uuid),public.update_profile(text,text),public.admin_house(text,text,text),public.admin_member(uuid,text,boolean),public.admin_record(uuid,boolean,text,timestamptz,uuid),public.server_add_member(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.my_house(),public.is_admin(),public.setup_house(text,text,text),public.record_trash(text,uuid),public.update_profile(text,text),public.admin_house(text,text,text),public.admin_member(uuid,text,boolean),public.admin_record(uuid,boolean,text,timestamptz,uuid) to authenticated;
grant execute on function public.server_add_member(uuid,uuid,text,text) to service_role;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('avatars','avatars',false,2097152,array['image/jpeg','image/png','image/webp']);
create policy avatar_read on storage.objects for select to authenticated using(bucket_id='avatars' and (storage.foldername(name))[1]=public.my_house()::text);
create policy avatar_insert on storage.objects for insert to authenticated with check(bucket_id='avatars' and (storage.foldername(name))[1]=public.my_house()::text and (storage.foldername(name))[2]=auth.uid()::text);
create policy avatar_delete on storage.objects for delete to authenticated using(bucket_id='avatars' and (storage.foldername(name))[1]=public.my_house()::text and (storage.foldername(name))[2]=auth.uid()::text);
alter publication supabase_realtime add table public.members,public.contributions;