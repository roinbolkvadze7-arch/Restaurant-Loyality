-- სრული ლოიალობის სისტემის მონაცემთა ბაზა
-- გაუშვით Supabase SQL Editor-ში (ერთად მთელი)

-- თუ ცხრილები არსებობს, წაშლით (განახლებისთვის)
DROP TABLE IF EXISTS promotion_usage CASCADE;
DROP TABLE IF EXISTS referrals CASCADE;
DROP TABLE IF EXISTS promotions CASCADE;
DROP TABLE IF EXISTS points_history CASCADE;
DROP TABLE IF EXISTS notifications CASCADE;
DROP TABLE IF EXISTS admins CASCADE;
DROP TABLE IF EXISTS guests CASCADE;

-- სტუმრების ცხრილი
CREATE TABLE guests (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text unique not null,
  email text,
  points integer default 0,
  level text default 'Classic' check (level in ('Classic', 'Silver', 'Gold', 'Platinum')),
  birthday date,
  last_birthday_bonus date,
  created_at timestamptz default now(),
  last_visit timestamptz default now()
);

-- ქულების ისტორიის ცხრილი
CREATE TABLE points_history (
  id uuid primary key default gen_random_uuid(),
  guest_id uuid references guests(id) on delete cascade,
  amount integer not null,
  type text not null check (type in ('earn', 'spend', 'bonus', 'admin')),
  description text,
  created_at timestamptz default now()
);

-- ადმინ მომხმარებლები
CREATE TABLE admins (
  id uuid primary key default gen_random_uuid(),
  email text unique not null,
  name text not null,
  created_at timestamptz default now()
);

-- შეტყობინებების ლოგი
CREATE TABLE notifications (
  id uuid primary key default gen_random_uuid(),
  target text not null,
  message text not null,
  sent_at timestamptz default now()
);

-- სპეციალური აქციების ცხრილი
CREATE TABLE promotions (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  start_date timestamptz not null,
  end_date timestamptz not null,
  discount_type text not null check (discount_type in ('percentage', 'fixed', 'points_multiplier', 'bonus_points')),
  discount_value decimal not null,
  min_order_amount decimal default 0,
  max_uses_per_guest integer,
  target_levels text[] default '{}',
  days_of_week integer[] default '{}',
  active boolean default true,
  created_at timestamptz default now()
);

-- რეფერალური პროგრამის ცხრილი
CREATE TABLE referrals (
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
CREATE TABLE promotion_usage (
  id uuid primary key default gen_random_uuid(),
  promotion_id uuid references promotions(id) on delete cascade,
  guest_id uuid references guests(id) on delete cascade,
  order_amount decimal not null,
  discount_applied decimal not null,
  used_at timestamptz default now()
);

-- ავტომატური დონის განახლება
CREATE OR REPLACE FUNCTION update_guest_level()
RETURNS trigger AS $$
BEGIN
  IF new.points >= 10000 THEN
    new.level := 'Platinum';
  ELSIF new.points >= 5000 THEN
    new.level := 'Gold';
  ELSIF new.points >= 1000 THEN
    new.level := 'Silver';
  ELSE
    new.level := 'Classic';
  END IF;
  RETURN new;
END;
$$ LANGUAGE plpgsql;

-- trigger: ქულების შეცვლისას დონე ავტომატურად განახლდება
CREATE TRIGGER guest_level_trigger
  BEFORE UPDATE OF points ON guests
  FOR EACH ROW EXECUTE FUNCTION update_guest_level();

-- დაბადების დღის ავტომატური ბონუსის ფუნქცია
CREATE OR REPLACE FUNCTION check_birthday_bonus()
RETURNS void AS $$
BEGIN
  UPDATE guests 
  SET 
    points = points + 500,
    last_birthday_bonus = current_date
  WHERE 
    extract(month from birthday) = extract(month from current_date)
    AND extract(day from birthday) = extract(day from current_date)
    AND (last_birthday_bonus is null or last_birthday_bonus < current_date)
    AND birthday is not null;
  
  INSERT INTO points_history (guest_id, amount, type, description)
  SELECT 
    id, 
    500, 
    'bonus', 
    'დაბადების დღის ბონუსი 🎂'
  FROM guests 
  WHERE 
    extract(month from birthday) = extract(month from current_date)
    AND extract(day from birthday) = extract(day from current_date)
    AND last_birthday_bonus = current_date;
END;
$$ LANGUAGE plpgsql;

-- რეფერალის დასრულების ფუნქცია
CREATE OR REPLACE FUNCTION complete_referral(referred_guest_id uuid)
RETURNS void AS $$
DECLARE
  ref_record referrals;
BEGIN
  SELECT * INTO ref_record 
  FROM referrals 
  WHERE referred_id = referred_guest_id AND status = 'pending';
  
  IF found THEN
    UPDATE referrals 
    SET status = 'completed', completed_at = now()
    WHERE id = ref_record.id;
    
    UPDATE guests SET points = points + ref_record.referrer_bonus WHERE id = ref_record.referrer_id;
    UPDATE guests SET points = points + ref_record.referred_bonus WHERE id = ref_record.referred_id;
    
    INSERT INTO points_history (guest_id, amount, type, description) VALUES
      (ref_record.referrer_id, ref_record.referrer_bonus, 'bonus', 'რეფერალის ბონუსი - მიწვევა'),
      (ref_record.referred_id, ref_record.referred_bonus, 'bonus', 'რეფერალის ბონუსი - რეგისტრაცია');
  END IF;
END;
$$ LANGUAGE plpgsql;

-- Row Level Security
ALTER TABLE guests ENABLE ROW LEVEL SECURITY;
ALTER TABLE points_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE admins ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE promotions ENABLE ROW LEVEL SECURITY;
ALTER TABLE referrals ENABLE ROW LEVEL SECURITY;
ALTER TABLE promotion_usage ENABLE ROW LEVEL SECURITY;

-- სტუმარი ხედავს მხოლოდ თავის მონაცემებს
CREATE POLICY "guests_select_own" ON guests FOR SELECT USING (true);
CREATE POLICY "guests_insert" ON guests FOR INSERT WITH CHECK (true);
CREATE POLICY "guests_update_own" ON guests FOR UPDATE USING (true);

CREATE POLICY "history_select" ON points_history FOR SELECT USING (true);
CREATE POLICY "history_insert" ON points_history FOR INSERT WITH CHECK (true);

CREATE POLICY "admins_select" ON admins FOR SELECT USING (true);
CREATE POLICY "notifications_all" ON notifications FOR ALL USING (true);

CREATE POLICY "promotions_select" ON promotions FOR SELECT USING (true);
CREATE POLICY "referrals_select" ON referrals FOR SELECT USING (true);
CREATE POLICY "referrals_insert" ON referrals FOR INSERT WITH CHECK (true);
CREATE POLICY "referrals_update" ON referrals FOR UPDATE USING (true);
CREATE POLICY "promotion_usage_all" ON promotion_usage FOR ALL USING (true);

-- საწყისი ადმინი
INSERT INTO admins (email, name) VALUES ('admin@myrestaurant.ge', 'მთავარი ადმინი');

-- საწყისი აქციები
INSERT INTO promotions (title, description, start_date, end_date, discount_type, discount_value, days_of_week, target_levels, min_order_amount) VALUES
  ('სამშაბათის აქცია', 'სამშაბათს ორმაგი ქულები!', '2026-01-01', '2026-12-31', 'points_multiplier', 2.0, '{3}', '{}', 0),
  ('ვიკენდის ბონუსი', 'შაბათ-კვირას +20% ქულა', '2026-01-01', '2026-12-31', 'points_multiplier', 1.2, '{6,7}', '{}', 0),
  ('Silver VIP', 'Silver წევრებისთვის 15% ფასდაკლება', '2026-05-01', '2026-05-31', 'percentage', 15, '{}', '{Silver}', 0),
  ('დიდი შეკვეთის ბონუსი', '100₾+ შეკვეთაზე 200 ბონუს ქულა', '2026-01-01', '2026-12-31', 'bonus_points', 200, '{}', '{}', 100);

-- ტესტ მონაცემები
INSERT INTO guests (name, phone, points, level, birthday) VALUES
  ('გიორგი მამულაძე', '+995599123456', 3240, 'Silver', '1990-05-15'),
  ('ნინო ბერიძე', '+995577234567', 1820, 'Silver', '1988-03-22'),
  ('დავით კვარაცხელია', '+995591345678', 540, 'Classic', '1995-11-08');