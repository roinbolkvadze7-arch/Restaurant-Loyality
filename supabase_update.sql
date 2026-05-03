-- განახლების სქრიპტი (არსებული ცხრილებისთვის)
-- გაუშვით ეს Supabase SQL Editor-ში

-- სტუმრების ცხრილში ახალი ველის დამატება (თუ არ არსებობს)
DO $$ 
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'guests' AND column_name = 'last_birthday_bonus') THEN
    ALTER TABLE guests ADD COLUMN last_birthday_bonus date;
  END IF;
END $$;

-- სპეციალური აქციების ცხრილი (ახალი)
CREATE TABLE IF NOT EXISTS promotions (
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

-- რეფერალური პროგრამის ცხრილი (ახალი)
CREATE TABLE IF NOT EXISTS referrals (
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

-- აქციების გამოყენების ისტორია (ახალი)
CREATE TABLE IF NOT EXISTS promotion_usage (
  id uuid primary key default gen_random_uuid(),
  promotion_id uuid references promotions(id) on delete cascade,
  guest_id uuid references guests(id) on delete cascade,
  order_amount decimal not null,
  discount_applied decimal not null,
  used_at timestamptz default now()
);

-- დაბადების დღის ავტომატური ბონუსის ფუნქცია
CREATE OR REPLACE FUNCTION check_birthday_bonus()
RETURNS void AS $$
BEGIN
  -- დღევანდელი დაბადების დღის მქონე სტუმრებისთვის 500 ქულის მიცემა
  UPDATE guests 
  SET 
    points = points + 500,
    last_birthday_bonus = current_date
  WHERE 
    extract(month from birthday) = extract(month from current_date)
    AND extract(day from birthday) = extract(day from current_date)
    AND (last_birthday_bonus is null or last_birthday_bonus < current_date)
    AND birthday is not null;
  
  -- ისტორიაში ჩაწერა
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
  -- მოძებნეთ pending რეფერალი
  SELECT * INTO ref_record 
  FROM referrals 
  WHERE referred_id = referred_guest_id AND status = 'pending';
  
  IF found THEN
    -- რეფერალის დასრულება
    UPDATE referrals 
    SET status = 'completed', completed_at = now()
    WHERE id = ref_record.id;
    
    -- ორივე მხარის ბონუსირება
    UPDATE guests SET points = points + ref_record.referrer_bonus WHERE id = ref_record.referrer_id;
    UPDATE guests SET points = points + ref_record.referred_bonus WHERE id = ref_record.referred_id;
    
    -- ისტორიაში ჩაწერა
    INSERT INTO points_history (guest_id, amount, type, description) VALUES
      (ref_record.referrer_id, ref_record.referrer_bonus, 'bonus', 'რეფერალის ბონუსი - მიწვევა'),
      (ref_record.referred_id, ref_record.referred_bonus, 'bonus', 'რეფერალის ბონუსი - რეგისტრაცია');
  END IF;
END;
$$ LANGUAGE plpgsql;

-- აქციების შემოწმების ფუნქცია
CREATE OR REPLACE FUNCTION check_active_promotions(
  guest_level text,
  order_amount decimal,
  current_day integer
) RETURNS table(
  promotion_id uuid,
  title text,
  discount_type text,
  discount_value decimal
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    p.id,
    p.title,
    p.discount_type,
    p.discount_value
  FROM promotions p
  WHERE 
    p.active = true
    AND now() BETWEEN p.start_date AND p.end_date
    AND (p.target_levels = '{}' OR guest_level = ANY(p.target_levels))
    AND (p.days_of_week = '{}' OR current_day = ANY(p.days_of_week))
    AND order_amount >= p.min_order_amount
    AND (
      p.max_uses_per_guest IS NULL 
      OR (
        SELECT count(*) 
        FROM promotion_usage pu 
        WHERE pu.promotion_id = p.id 
        AND pu.guest_id IN (
          SELECT id FROM guests WHERE level = guest_level LIMIT 1
        )
      ) < p.max_uses_per_guest
    );
END;
$$ LANGUAGE plpgsql;

-- RLS პოლისები ახალი ცხრილებისთვის
ALTER TABLE promotions ENABLE ROW LEVEL SECURITY;
ALTER TABLE referrals ENABLE ROW LEVEL SECURITY;
ALTER TABLE promotion_usage ENABLE ROW LEVEL SECURITY;

-- დაშვების პოლისები
DROP POLICY IF EXISTS "promotions_select" ON promotions;
CREATE POLICY "promotions_select" ON promotions FOR SELECT USING (true);

DROP POLICY IF EXISTS "referrals_select" ON referrals;
CREATE POLICY "referrals_select" ON referrals FOR SELECT USING (true);

DROP POLICY IF EXISTS "referrals_insert" ON referrals;
CREATE POLICY "referrals_insert" ON referrals FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "referrals_update" ON referrals;
CREATE POLICY "referrals_update" ON referrals FOR UPDATE USING (true);

DROP POLICY IF EXISTS "promotion_usage_all" ON promotion_usage;
CREATE POLICY "promotion_usage_all" ON promotion_usage FOR ALL USING (true);

-- საწყისი აქციების მაგალითები (თუ ცარიელია ცხრილი)
INSERT INTO promotions (title, description, start_date, end_date, discount_type, discount_value, days_of_week) 
SELECT 'სამშაბათის აქცია', 'სამშაბათს ორმაგი ქულები!', '2026-01-01', '2026-12-31', 'points_multiplier', 2.0, '{3}'
WHERE NOT EXISTS (SELECT 1 FROM promotions WHERE title = 'სამშაბათის აქცია');

INSERT INTO promotions (title, description, start_date, end_date, discount_type, discount_value, days_of_week) 
SELECT 'ვიკენდის ბონუსი', 'შაბათ-კვირას +20% ქულა', '2026-01-01', '2026-12-31', 'points_multiplier', 1.2, '{6,7}'
WHERE NOT EXISTS (SELECT 1 FROM promotions WHERE title = 'ვიკენდის ბონუსი');

INSERT INTO promotions (title, description, start_date, end_date, discount_type, discount_value, target_levels, min_order_amount) 
SELECT 'Silver VIP', 'Silver წევრებისთვის 15% ფასდაკლება', '2026-05-01', '2026-05-31', 'percentage', 15, '{Silver}', 0
WHERE NOT EXISTS (SELECT 1 FROM promotions WHERE title = 'Silver VIP');

INSERT INTO promotions (title, description, start_date, end_date, discount_type, discount_value, min_order_amount) 
SELECT 'დიდი შეკვეთის ბონუსი', '100₾+ შეკვეთაზე 200 ბონუს ქულა', '2026-01-01', '2026-12-31', 'bonus_points', 200, 100
WHERE NOT EXISTS (SELECT 1 FROM promotions WHERE title = 'დიდი შეკვეთის ბონუსი');