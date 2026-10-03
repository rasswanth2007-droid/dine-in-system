CREATE TABLE IF NOT EXISTS users (
  user_id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  phone_hash TEXT NOT NULL UNIQUE,
  phone_last4 TEXT NOT NULL,
  salt TEXT NOT NULL,
  pass_hash TEXT NOT NULL,
  created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS sessions (
  token TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(user_id),
  created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS restaurants (
  restaurant_id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  type TEXT NOT NULL,
  city TEXT,
  area TEXT
);
CREATE TABLE IF NOT EXISTS dining_tables (
  table_id INTEGER PRIMARY KEY AUTOINCREMENT,
  restaurant_id INTEGER NOT NULL REFERENCES restaurants(restaurant_id),
  capacity INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS bookings (
  booking_id INTEGER PRIMARY KEY AUTOINCREMENT,
  restaurant_id INTEGER NOT NULL REFERENCES restaurants(restaurant_id),
  host_user_id INTEGER NOT NULL REFERENCES users(user_id),
  group_type TEXT NOT NULL CHECK (group_type IN ('friends','colleagues','family')),
  party_size INTEGER NOT NULL CHECK (party_size BETWEEN 1 AND 30),
  status TEXT NOT NULL DEFAULT 'confirmed' CHECK (status IN ('confirmed','seated','completed','cancelled')),
  table_id INTEGER REFERENCES dining_tables(table_id),
  created_at TEXT NOT NULL,
  seated_at TEXT,
  finished_at TEXT,
  pred_wait_p10 REAL, pred_wait_p50 REAL, pred_wait_p90 REAL, pred_eat_p50 REAL
);
CREATE TABLE IF NOT EXISTS booking_members (
  booking_id INTEGER NOT NULL REFERENCES bookings(booking_id),
  phone_hash TEXT NOT NULL,
  phone_last4 TEXT NOT NULL,
  user_id INTEGER REFERENCES users(user_id),
  invite_status TEXT NOT NULL DEFAULT 'pending' CHECK (invite_status IN ('pending','accepted','declined','not_on_app')),
  PRIMARY KEY (booking_id, phone_hash)
);
CREATE TABLE IF NOT EXISTS visits (
  visit_id INTEGER PRIMARY KEY AUTOINCREMENT,
  booking_id INTEGER,
  restaurant_id INTEGER NOT NULL,
  group_type TEXT NOT NULL,
  party_size INTEGER NOT NULL,
  meal_period TEXT NOT NULL,
  actual_wait_min REAL,
  duration_min REAL NOT NULL,
  pred_wait_p10 REAL, pred_wait_p50 REAL, pred_wait_p90 REAL, pred_eat_p50 REAL,
  synthetic INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS ix_book_rest ON bookings(restaurant_id, status)
