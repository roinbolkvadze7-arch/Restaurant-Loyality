# 🍽️ რესტორნის ბონუს სისტემა — დაყენების სახელმძღვანელო

## ფაილების სტრუქტურა
```
loyalty/
├── index.html        → სტუმრის პანელი
├── admin.html        → ადმინ პანელი
└── supabase_schema.sql → მონაცემთა ბაზა
```

---

## ნაბიჯი 1: Supabase პროექტის შექმნა

1. გადადი → https://supabase.com
2. შექმენი უფასო ანგარიში
3. "New Project" → შეარქვი სახელი (მაგ. "restaurant-loyalty")
4. ჩაინიშნე **Project URL** და **anon public key**
   - Settings → API → Project URL + anon key

---

## ნაბიჯი 2: მონაცემთა ბაზის შექმნა

1. Supabase Dashboard → **SQL Editor**
2. "New query" → ჩასვი `supabase_schema.sql`-ის მთელი შინაარსი
3. "Run" დააჭირე
4. Table Editor-ში გამოჩება ცხრილები: guests, points_history, notifications, admins

---

## ნაბიჯი 3: კოდის კონფიგურაცია

**index.html** და **admin.html** ორივე ფაილში შეცვალე:
```javascript
const SUPABASE_URL = 'https://YOUR_PROJECT.supabase.co';
const SUPABASE_ANON_KEY = 'YOUR_ANON_KEY';
```
შენი Supabase-ის მონაცემებით.

**admin.html**-ში ასევე შეცვალე ადმინის პაროლი:
```javascript
const ADMIN_PASSWORD = 'admin2024'; // ← შენი პაროლი
```

---

## ნაბიჯი 4: GitHub Pages-ზე განთავსება

1. github.com → "New repository" → სახელი: `restaurant-loyalty` (public)
2. ატვირთე 3 ფაილი: `index.html`, `admin.html`, `supabase_schema.sql`
3. Settings → Pages → Source: **main branch** → Save
4. სტუმრის საიტი: `https://ᲨᲔᲜᲘ_USERNAME.github.io/restaurant-loyalty/`
5. ადმინ პანელი: `https://ᲨᲔᲜᲘ_USERNAME.github.io/restaurant-loyalty/admin.html`

---

## ქულების სისტემა

| მოქმედება | ქულა |
|-----------|------|
| 1 ₾ დახარჯვა | 1 ქულა |
| 100 ქულა | 1 ₾ ფასდაკლება |
| დაბადების დღე | +500 ქულა |
| სამშაბათი | ×2 ქულა |

## დონეები

| დონე | ქულა | ბონუსი |
|------|------|--------|
| Classic | 0 — 999 | სტანდარტული |
| Silver | 1 000 — 4 999 | +10% ქულა |
| Gold | 5 000 — 9 999 | +20% ქულა |
| Platinum | 10 000+ | +50% ქულა + VIP |

---

## მიმტნის სამუშაო პროცესი

1. სტუმარი ატყობინებს ტელეფონის ნომერს
2. მიმტანი ხსნის **admin.html** → სტუმრები → კორექტირება
3. ამატებს ქულებს (დახარჯული თანხა × 1)
4. სტუმარი ხედავს ახლებულ ბალანსს **index.html**-ში

---

## მომავალი გაუმჯობესებები

- [ ] SMS შეტყობინებები (Twilio ან Georgian SMS Gateway)
- [ ] QR სკანირება კამერიდან
- [ ] RKeeper-თან ინტეგრაცია API-ით
- [ ] ავტომატური დაბადების დღის ბონუსი (Supabase Edge Function)
- [ ] ქულების გამოყენება QR-ით

---

## დახმარება

პრობლემის შემთხვევაში შეამოწმე:
- Supabase URL და KEY სწორია?
- SQL სქემა გაეშვა?
- GitHub Pages enabled?
