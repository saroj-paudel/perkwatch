-- Perkwatch initial schema. Final for the MVP (see docs/00-DECISIONS.md D12).
-- Run in the Supabase SQL editor or with `supabase db push`.

-- ---------- Types ----------
create type public.perk_type as enum ('credit', 'trial', 'license', 'verification', 'offer', 'other');
create type public.perk_status as enum ('eligible', 'claimed', 'active', 'used', 'archived');

-- ---------- Helpers ----------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------- Perks ----------
create table public.perks (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null default auth.uid() references auth.users (id) on delete cascade,
  platform       text not null check (char_length(platform) between 1 and 80),
  type           public.perk_type not null default 'credit',
  status         public.perk_status not null default 'active',
  amount         numeric(14, 2) check (amount is null or amount >= 0),
  currency       text check (currency is null or currency ~ '^[A-Z]{3}$'),
  claim_by       date,
  expires_at     date,
  expiry_note    text check (expiry_note is null or char_length(expiry_note) <= 500),
  restrictions   text check (restrictions is null or char_length(restrictions) <= 2000),
  notes          text check (notes is null or char_length(notes) <= 2000),
  ai_confidence  text check (ai_confidence is null or ai_confidence in ('high', 'medium', 'low')),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create index perks_user_expires_idx on public.perks (user_id, expires_at);
create index perks_user_status_idx on public.perks (user_id, status);

create trigger perks_set_updated_at
  before update on public.perks
  for each row execute function public.set_updated_at();

-- ---------- Notification settings (one row per user) ----------
create table public.notification_settings (
  user_id                   uuid primary key references auth.users (id) on delete cascade,
  telegram_enabled          boolean not null default true,
  telegram_chat_id          bigint,
  telegram_link_code        text,
  telegram_link_expires_at  timestamptz,
  thresholds                int[] not null default '{30,14,7,3,1}'
                            check (array_length(thresholds, 1) between 1 and 10),
  timezone                  text not null default 'UTC',
  updated_at                timestamptz not null default now()
);

create unique index notification_settings_chat_idx
  on public.notification_settings (telegram_chat_id) where telegram_chat_id is not null;
create unique index notification_settings_code_idx
  on public.notification_settings (telegram_link_code) where telegram_link_code is not null;

create trigger notification_settings_set_updated_at
  before update on public.notification_settings
  for each row execute function public.set_updated_at();

-- Create the settings row automatically for each new auth user.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.notification_settings (user_id) values (new.id) on conflict do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- Notifications (one row per perk, kind, threshold, channel) ----------
create table public.notifications (
  id          uuid primary key default gen_random_uuid(),
  perk_id     uuid not null references public.perks (id) on delete cascade,
  user_id     uuid not null references auth.users (id) on delete cascade,
  kind        text not null check (kind in ('expiry', 'claim')),
  threshold   int not null check (threshold >= 0),
  channel     text not null default 'telegram' check (channel in ('telegram')),
  status      text not null default 'pending' check (status in ('pending', 'sent', 'failed')),
  attempts    int not null default 0,
  error       text,
  created_at  timestamptz not null default now(),
  sent_at     timestamptz,
  unique (perk_id, kind, threshold, channel)
);

create index notifications_user_status_idx on public.notifications (user_id, status);

-- When a perk's dates or status change, reminders must be recomputed from scratch.
create or replace function public.reset_notifications_on_perk_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.expires_at is distinct from old.expires_at
     or new.claim_by is distinct from old.claim_by
     or new.status is distinct from old.status then
    delete from public.notifications where perk_id = new.id;
  end if;
  return new;
end;
$$;

create trigger perks_reset_notifications
  after update on public.perks
  for each row execute function public.reset_notifications_on_perk_change();

-- ---------- AI usage (daily rate limit) ----------
create table public.ai_usage (
  user_id  uuid not null references auth.users (id) on delete cascade,
  used_on  date not null default current_date,
  calls    int not null default 0,
  primary key (user_id, used_on)
);

-- Atomically count a call. Returns false when the daily limit is already reached.
create or replace function public.increment_ai_usage(p_user uuid, p_limit int)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_calls int;
begin
  insert into public.ai_usage (user_id, used_on, calls)
  values (p_user, current_date, 1)
  on conflict (user_id, used_on)
  do update set calls = public.ai_usage.calls + 1
  returning calls into v_calls;

  return v_calls <= p_limit;
end;
$$;

-- Only the server (service role) may call this function.
revoke all on function public.increment_ai_usage(uuid, int) from public, anon, authenticated;
grant execute on function public.increment_ai_usage(uuid, int) to service_role;

-- ---------- Row-level security ----------
alter table public.perks enable row level security;
alter table public.notification_settings enable row level security;
alter table public.notifications enable row level security;
alter table public.ai_usage enable row level security;

create policy perks_owner_all on public.perks
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy settings_owner_select on public.notification_settings
  for select using (auth.uid() = user_id);
create policy settings_owner_insert on public.notification_settings
  for insert with check (auth.uid() = user_id);
create policy settings_owner_update on public.notification_settings
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Notifications: owner can read. Writes happen only through the service role.
create policy notifications_owner_select on public.notifications
  for select using (auth.uid() = user_id);

-- ai_usage: no policies on purpose. Only the service role (which bypasses RLS) touches it.
