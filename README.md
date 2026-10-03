# Dine-In — Restaurant Booking & Wait-Time Prediction

A full-stack restaurant booking system with a real-time ML-powered wait and seating time predictor.

**Backend:** R (Plumber REST API + SQLite)  
**Frontend:** Plain HTML/CSS/JS (no frameworks, no build step)  
**Model:** Gamma GLM on eating duration + Monte Carlo table simulation

---

## Features

### Customer (User)
- Register / Login with phone number
- Browse all restaurants with live waiting and seated counts
- Book a table — add party members by phone number
- Real-time queue status: expected seating time, estimated finish time, parties ahead
- Accept or decline booking invites from other users
- Cancel your own booking while waiting
- Post-meal feedback form (star rating, eating duration, wait accuracy, crowd level)

### Hotel / Restaurant Staff
- Sign in with a staff key and select your restaurant
- Live dashboard — KPI strip (waiting, seated, free tables, queue limit)
- Set a maximum queue size to control walk-in overload
- Seat and Finish bookings directly from the dashboard
- After each Finish: see actual vs predicted wait and meal time
- Auto-refreshes every 30 seconds

### Prediction Model
- **Gamma GLM** trained on eating duration (group type, party size, meal period, restaurant type)
- **Monte Carlo simulation** (800 runs) to predict seating wait time with p10/p50/p90 intervals
- Model retrains automatically after every completed booking
- `/stats` endpoint reports MAE, baseline MAE, and p10-p90 interval coverage on real visits
- Predicted eating duration is intentionally hidden from users — shown only to staff and used for model accuracy

---

## Quick Start

### 1. Install R packages
```r
install.packages(c("plumber", "DBI", "RSQLite", "digest", "uuid"))
```

### 2. Start the API (Terminal 1)
```powershell
# Windows — add R to PATH first
$env:PATH += ";C:\Program Files\R\R-4.6.1\bin"
cd "d:\projects\dine-in system"
Rscript run.R
```
First run automatically creates `dinein.sqlite` and seeds 11 restaurants + 900 synthetic visits.

API runs at: **http://localhost:8000**  
Swagger docs: **http://localhost:8000/__docs__/**

### 3. Start the frontend (Terminal 2)
```powershell
python -m http.server 5500 --directory frontend
```
Open: **http://localhost:5500**

### Staff key
Default: `staff123`  
Override with environment variable: `STAFF_KEY=yourkey Rscript run.R`

---

## Project Structure

```
dine-in system/
├── api.R              # All REST endpoints (Plumber)
├── db.R               # DB connection, phone hashing, time helpers
├── model.R            # Gamma GLM + Monte Carlo seating prediction
├── seed.R             # 11 restaurants + 900 synthetic visits
├── run.R              # Entry point — starts the server
├── schema.sql         # SQLite schema
├── start-api.ps1      # Convenience script (Windows)
├── start-frontend.ps1 # Convenience script (Windows)
└── frontend/
    ├── app.js          # Shared helpers: apiFetch, hotelFetch, buildNav, auth
    ├── style.css       # Dark theme, cards, badges, responsive
    ├── index.html      # Role picker → Customer login/register OR Hotel login
    ├── restaurants.html# Restaurant list with live counts
    ├── book.html       # Booking form (party size, members, estimate, confirm)
    ├── booking.html    # Booking detail — queue status, members, actions
    ├── mybookings.html # Expandable booking cards
    ├── feedback.html   # Post-meal feedback form
    ├── hotel.html      # Hotel dashboard — queue, KPIs, seat/finish
    ├── staff.html      # Redirects hotel users to hotel.html
    └── stats.html      # Model accuracy metrics
```

---

## Restaurants (11 total)

| # | Name | Type | City |
|---|---|---|---|
| 1 | Mandhi Palace | mandhi | Coimbatore |
| 2 | Desert Rose Mandhi | mandhi | Chennai |
| 3 | Urban Bites (franchise) | franchise | Coimbatore |
| 4 | Grill Hub (franchise) | franchise | Chennai |
| 5 | Saffron Fine Dine | finedine | Chennai |
| 6 | Corner Cafe | cafe | Coimbatore |
| 7 | Spice Garden | mandhi | Coimbatore |
| 8 | The Biryani Co. | franchise | Chennai |
| 9 | Olive Bistro | finedine | Chennai |
| 10 | Noodle Street | cafe | Coimbatore |
| 11 | Royal Darbaar | finedine | Chennai |

---

## API Reference

Auth headers: `X-Token: <token>` (users) · `X-Staff-Key: <key>` (hotel staff)

| Method | Path | Auth | Description |
|---|---|---|---|
| POST | /register | — | `{name, phone, password}` → `{token, user_id, name}` |
| POST | /login | — | `{phone, password}` → `{token, user_id, name}` |
| GET | /restaurants | — | List with live waiting/seated counts |
| GET | /predict | — | `?restaurant_id&party_size&group_type` → prediction object |
| POST | /bookings | user | `{restaurant_id, group_type, party_size, members:[phones]}` |
| GET | /bookings/mine | user | All bookings (hosted + invited) |
| GET | /bookings/{id} | user | Detail + members + live_estimate while waiting |
| POST | /bookings/{id}/respond | user | `{action:"accept"/"decline"}` |
| POST | /bookings/{id}/cancel | user | Host only, while waiting |
| GET | /staff/queue | staff | `?restaurant_id` — waiting + seated queue |
| POST | /staff/bookings/{id}/seat | staff | Assigns smallest free table |
| POST | /staff/bookings/{id}/finish | staff | Records real duration, retrains model |
| GET | /stats | — | MAE, baseline MAE, interval coverage on real visits |

**Prediction response fields:**
`wait_min {p10, p50, p90}`, `eat_min_p50`, `expected_seat_time`, `expected_finish_time`, `parties_ahead`, `tables_in_use`, `tables_total`, `model_visits`

> Note: `eat_min_p50` is intentionally not shown to users in the frontend — it is internal model data used for accuracy tracking.

---

## How the model works

1. **Gamma GLM** fits eating duration from historical visits using:
   - Group type (friends / colleagues / family)
   - Party size
   - Meal period (breakfast / lunch / snacks / dinner)
   - Restaurant type (mandhi / franchise / finedine / cafe)

2. **Monte Carlo simulation** (800 runs per prediction):
   - Draws remaining time for each currently occupied table
   - Queues waiting parties ahead of the new booking
   - Records the earliest time a suitable table becomes free
   - Returns p10 / p50 / p90 wait quantiles

3. **Retraining:** After every `POST /staff/bookings/{id}/finish`, real visit data is appended and `train_model()` runs again.

---

## Notes

- `dinein.sqlite` is excluded from version control (contains user data)
- Seed data is synthetic — label accordingly in any report
- Passwords use salted SHA-256 (use bcrypt/argon2 in production)
- Phone numbers are stored as SHA-256 hashes — only the last 4 digits are retained for display
- Feedback from users is stored in `localStorage` — a `/feedback` API endpoint can be added to persist it server-side