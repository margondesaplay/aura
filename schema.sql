-- AURA Social: execute todo este arquivo no SQL Editor do Supabase.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Novo usuário' check (char_length(display_name) between 1 and 40),
  bio text not null default '' check (char_length(bio) <= 300),
  updated_at timestamptz not null default now()
);

create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  content text not null check (char_length(content) between 1 and 2000),
  created_at timestamptz not null default now()
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles(id) on delete cascade,
  receiver_id uuid not null references public.profiles(id) on delete cascade,
  content text not null check (char_length(content) between 1 and 2000),
  created_at timestamptz not null default now(),
  constraint no_self_message check (sender_id <> receiver_id)
);

create index if not exists posts_created_at_idx on public.posts(created_at desc);
create index if not exists messages_pair_idx on public.messages(sender_id, receiver_id, created_at);

alter table public.profiles enable row level security;
alter table public.posts enable row level security;
alter table public.messages enable row level security;

-- Perfis públicos para usuários autenticados.
drop policy if exists "Authenticated users can read profiles" on public.profiles;
create policy "Authenticated users can read profiles" on public.profiles for select to authenticated using (true);
drop policy if exists "Users create own profile" on public.profiles;
create policy "Users create own profile" on public.profiles for insert to authenticated with check (auth.uid() = id);
drop policy if exists "Users update own profile" on public.profiles;
create policy "Users update own profile" on public.profiles for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);

-- Feed visível a qualquer usuário autenticado; cada um só altera as próprias publicações.
drop policy if exists "Authenticated users read posts" on public.posts;
create policy "Authenticated users read posts" on public.posts for select to authenticated using (true);
drop policy if exists "Users create own posts" on public.posts;
create policy "Users create own posts" on public.posts for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "Users delete own posts" on public.posts;
create policy "Users delete own posts" on public.posts for delete to authenticated using (auth.uid() = user_id);

-- Somente remetente e destinatário podem consultar a mensagem.
drop policy if exists "Participants read messages" on public.messages;
create policy "Participants read messages" on public.messages for select to authenticated using (auth.uid() = sender_id or auth.uid() = receiver_id);
drop policy if exists "Sender creates own messages" on public.messages;
create policy "Sender creates own messages" on public.messages for insert to authenticated with check (auth.uid() = sender_id and sender_id <> receiver_id);
drop policy if exists "Participants delete messages" on public.messages;
create policy "Participants delete messages" on public.messages for delete to authenticated using (auth.uid() = sender_id or auth.uid() = receiver_id);

-- Criar perfil automaticamente após cadastro.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(nullif(new.raw_user_meta_data->>'display_name',''), split_part(new.email,'@',1)))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

grant usage on schema public to anon, authenticated;
grant select, insert, update on public.profiles to authenticated;
grant select, insert, delete on public.posts to authenticated;
grant select, insert, delete on public.messages to authenticated;
