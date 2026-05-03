-- სრული წაშლა და თავიდან შექმნა (ყურადღებით!)
-- გამოიყენეთ მხოლოდ იმ შემთხვევაში, თუ არსებული მონაცემები არ გჭირდებათ

-- ძველი ცხრილების წაშლა (თუ არსებობს)
DROP TABLE IF EXISTS promotion_usage CASCADE;
DROP TABLE IF EXISTS referrals CASCADE;
DROP TABLE IF EXISTS promotions CASCADE;
DROP TABLE IF EXISTS points_history CASCADE;
DROP TABLE IF EXISTS notifications CASCADE;
DROP TABLE IF EXISTS admins CASCADE;
DROP TABLE IF EXISTS guests CASCADE;

-- ახლა გაუშვით თქვენი სრული supabase_schema.sql ფაილი