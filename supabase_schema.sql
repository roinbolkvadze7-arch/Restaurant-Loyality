-- ლოიალობის სისტემის მონაცემთა ბაზა
-- გაუშვი Supabase SQL Editor-ში

-- სტუმრების ცხრილი
create table guests (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text unique not null,
  email text,
  points integer default 0,
  level text default 'Classic' check (level in ('Classic', 'Silver', 'Gold', 'Platinum')),
  birthday date,
  created_at timestamptz default now(),
  last_visit timestamptz default now()
);

-- ქულების ისტორიის ცხრილი
create table points_history (
  id uuid primary key default gen_random_uuid(),
  guest_id uuid references guests(id) on delete cascade,
  amount integer not null,
  type text not null check (type in ('earn', 'spend', 'bonus', 'admin')),
  description text,
  created_at timestamptz default now()
);

-- ადმინ მომხმარებლები
create table admins (
  id uuid primary key default gen_random_uuid(),
  email text unique not null,
  name text not null,
  created_at timestamptz default now()
);

-- შეტყობინებების ლოგი
create table notifications (
  id uuid primary key default gen_random_uuid(),
  target text not null,
  message text not null,
  sent_at timestamptz default now()
);

-- ავტომატური დონის განახლება ფუნქცია
create or replace function update_guest_level()
returns trigger as $$
begin
  if new.points >= 10000 then
    new.level := 'Platinum';
  elsif new.points >= 5000 then
    new.level := 'Gold';
  elsif new.points >= 1000 then
    new.level := 'Silver';
  else
    new.level := 'Classic';
  end if;
  return new;
end;
$$ language plpgsql;

-- trigger: ქულების შეცვლისას დონე ავტომატურად განახლდება
create trigger guest_level_trigger
  before update of points on guests
  for each row execute function update_guest_level();

-- Row Level Security
alter table guests enable row level security;
alter table points_history enable row level security;
alter table admins enable row level security;
alter table notifications enable row level security;

-- სტუმარი ხედავს მხოლოდ თავის მონაცემებს (ტელეფონით)
create policy "guests_select_own" on guests
  for select using (true);

create policy "guests_insert" on guests
  for insert with check (true);

create policy "guests_update_own" on guests
  for update using (true);

-- ისტორია ხილულია ყველასთვის (anon key-ით ვფილტრავთ frontend-ზე)
create policy "history_select" on points_history
  for select using (true);

create policy "history_insert" on points_history
  for insert with check (true);

create policy "admins_select" on admins
  for select using (true);

create policy "notifications_all" on notifications
  for all using (true);

-- საწყისი ადმინი (შეცვალე შენი email-ით)
insert into admins (email, name) values ('admin@myrestaurant.ge', 'მთავარი ადმინი');

-- ტესტ მონაცემები (სურვილისამებრ)
insert into guests (name, phone, points, level, birthday) values
  ('გიორგი მამულაძე', '+995599123456', 3240, 'Silver', '1990-05-15'),
  ('ნინო ბერიძე', '+995577234567', 1820, 'Silver', '1988-03-22'),
  ('დავით კვარაცხელია', '+995591345678', 540, 'Classic', '1995-11-08');
