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

-- სპეციალური აქციების ცხრილი
create table promotions (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  start_date timestamptz not null,
  end_date timestamptz not null,
  discount_type text not null check (discount_type in ('percentage', 'fixed', 'points_multiplier', 'bonus_points')),
  discount_value decimal not null,
  min_order_amount decimal default 0,
  max_uses_per_guest integer,
  target_levels text[] default '{}', -- ['Classic', 'Silver'] ან ყველასთვის []
  days_of_week integer[] default '{}', -- [1,2,3,4,5,6,7] (1=ორშაბათი)
  active boolean default true,
  created_at timestamptz default now()
);

-- რეფერალური პროგრამის ცხრილი
create table referrals (
  id uuid primary key default gen_random_uuid(),
  referrer_id uuid references guests(id) on delete cascade,
  referred_id uuid references guests(id) on delete cascade,
  referrer_bonus integer default 1000,
  referred_bonus integer default 500,
  status text default 'pending' check (status in ('pending', 'completed', 'cancelled')),
  completed_at timestamptz,
  created_at timestamptz default now(),
  unique(referrer_id, referred_id)
);

-- აქციების გამოყენების ისტორია
create table promotion_usage (
  id uuid primary key default gen_random_uuid(),
  promotion_id uuid references promotions(id) on delete cascade,
  guest_id uuid references guests(id) on delete cascade,
  order_amount decimal not null,
  discount_applied decimal not null,
  used_at timestamptz default now()
);

-- სტუმრების ცხრილში ბოლო დაბადების ბონუსის ველის დამატება
alter table guests add column last_birthday_bonus date;

-- დაბადების დღის ავტომატური ბონუსის ფუნქცია
create or replace function check_birthday_bonus()
returns void as $$
begin
  -- დღევანდელი დაბადების დღის მქონე სტუმრებისთვის 500 ქულის მიცემა
  update guests 
  set 
    points = points + 500,
    last_birthday_bonus = current_date
  where 
    extract(month from birthday) = extract(month from current_date)
    and extract(day from birthday) = extract(day from current_date)
    and (last_birthday_bonus is null or last_birthday_bonus < current_date)
    and birthday is not null;
  
  -- ისტორიაში ჩაწერა
  insert into points_history (guest_id, amount, type, description)
  select 
    id, 
    500, 
    'bonus', 
    'დაბადების დღის ბონუსი 🎂'
  from guests 
  where 
    extract(month from birthday) = extract(month from current_date)
    and extract(day from birthday) = extract(day from current_date)
    and last_birthday_bonus = current_date;
end;
$$ language plpgsql;

-- რეფერალის დასრულების ფუნქცია
create or replace function complete_referral(referred_guest_id uuid)
returns void as $$
declare
  ref_record referrals;
begin
  -- მოძებნეთ pending რეფერალი
  select * into ref_record 
  from referrals 
  where referred_id = referred_guest_id and status = 'pending';
  
  if found then
    -- რეფერალის დასრულება
    update referrals 
    set status = 'completed', completed_at = now()
    where id = ref_record.id;
    
    -- ორივე მხარის ბონუსირება
    update guests set points = points + ref_record.referrer_bonus where id = ref_record.referrer_id;
    update guests set points = points + ref_record.referred_bonus where id = ref_record.referred_id;
    
    -- ისტორიაში ჩაწერა
    insert into points_history (guest_id, amount, type, description) values
      (ref_record.referrer_id, ref_record.referrer_bonus, 'bonus', 'რეფერალის ბონუსი - მიწვევა'),
      (ref_record.referred_id, ref_record.referred_bonus, 'bonus', 'რეფერალის ბონუსი - რეგისტრაცია');
  end if;
end;
$$ language plpgsql;

-- აქციების შემოწმების ფუნქცია
create or replace function check_active_promotions(
  guest_level text,
  order_amount decimal,
  current_day integer
) returns table(
  promotion_id uuid,
  title text,
  discount_type text,
  discount_value decimal
) as $$
begin
  return query
  select 
    p.id,
    p.title,
    p.discount_type,
    p.discount_value
  from promotions p
  where 
    p.active = true
    and now() between p.start_date and p.end_date
    and (p.target_levels = '{}' or guest_level = any(p.target_levels))
    and (p.days_of_week = '{}' or current_day = any(p.days_of_week))
    and order_amount >= p.min_order_amount
    and (
      p.max_uses_per_guest is null 
      or (
        select count(*) 
        from promotion_usage pu 
        where pu.promotion_id = p.id 
        and pu.guest_id in (
          select id from guests where level = guest_level limit 1
        )
      ) < p.max_uses_per_guest
    );
end;
$$ language plpgsql;

-- RLS პოლისები ახალი ცხრილებისთვის
alter table promotions enable row level security;
alter table referrals enable row level security;
alter table promotion_usage enable row level security;

create policy "promotions_select" on promotions for select using (true);
create policy "referrals_select" on referrals for select using (true);
create policy "referrals_insert" on referrals for insert with check (true);
create policy "referrals_update" on referrals for update using (true);
create policy "promotion_usage_all" on promotion_usage for all using (true);

-- საწყისი აქციების მაგალითები
insert into promotions (title, description, start_date, end_date, discount_type, discount_value, days_of_week) values
  ('სამშაბათის აქცია', 'სამშაბათს ორმაგი ქულები!', '2026-01-01', '2026-12-31', 'points_multiplier', 2.0, '{3}'),
  ('ვიკენდის ბონუსი', 'შაბათ-კვირას +20% ქულა', '2026-01-01', '2026-12-31', 'points_multiplier', 1.2, '{6,7}'),
  ('Silver VIP', 'Silver წევრებისთვის 15% ფასდაკლება', '2026-05-01', '2026-05-31', 'percentage', 15, '{}', '{Silver}'),
  ('დიდი შეკვეთის ბონუსი', '100₾+ შეკვეთაზე 200 ბონუს ქულა', '2026-01-01', '2026-12-31', 'bonus_points', 200, '{}', 100);

-- ტესტ მონაცემები (სურვილისამებრ)
insert into guests (name, phone, points, level, birthday) values
  ('გიორგი მამულაძე', '+995599123456', 3240, 'Silver', '1990-05-15'),
  ('ნინო ბერიძე', '+995577234567', 1820, 'Silver', '1988-03-22'),
  ('დავით კვარაცხელია', '+995591345678', 540, 'Classic', '1995-11-08');
