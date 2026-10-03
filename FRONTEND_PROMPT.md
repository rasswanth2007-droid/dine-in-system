# Prompt for the frontend AI

Build a very basic web frontend for an existing REST API. Plain HTML, one CSS file and plain JavaScript (fetch). No frameworks, no build step, no libraries.

## Design rules
- Very basic: white background, black text, system font, default-looking buttons, simple bordered tables and forms, one column, max width 700px, centered.
- NO animation: no CSS transitions, no keyframes, no spinners, no hover effects, no scroll effects. Show "Loading..." as plain text if needed.
- Every input has a visible label. Errors are shown as plain red text under the form. All pages work on a phone.
- Files: index.html (login/register), restaurants.html, book.html, mybookings.html, booking.html, staff.html, stats.html, style.css, app.js (shared helpers). A simple link menu on every page.

## API
Base URL is a constant `API = "http://localhost:8000"` at the top of app.js. Send JSON with `Content-Type: application/json`. After login, store `token` in localStorage and send it as header `X-Token` on user calls. Errors come as `{"error": "message"}` with HTTP 4xx, so show that message.

- POST /register {name, phone, password} and POST /login {phone, password} return {token, user_id, name}
- GET /restaurants returns [{restaurant_id, name, type, city, area, tables, max_capacity, waiting, seated_now}]
- GET /predict?restaurant_id=1&party_size=4&group_type=friends returns {wait_min:{p10,p50,p90}, eat_min_p50, expected_seat_time, expected_finish_time, parties_ahead, tables_in_use, tables_total, model_visits}
- POST /bookings (user) {restaurant_id, group_type, party_size, members:[phone strings]} returns {booking_id, ...same prediction fields}
- GET /bookings/mine (user) returns [{booking_id, restaurant, group_type, party_size, status, pred_wait_p50, pred_eat_p50, created_at, role}] where role is host or guest
- GET /bookings/{id} (user) returns {booking:{...}, members:[{phone_last4, invite_status, name}], live_estimate:{...prediction}, eating_for_min}. live_estimate only appears while status is confirmed, eating_for_min only while seated.
- POST /bookings/{id}/respond (user) {action:"accept"|"decline"}; POST /bookings/{id}/cancel (user)
- Staff, header `X-Staff-Key`: GET /staff/queue?restaurant_id=1, POST /staff/bookings/{id}/seat, POST /staff/bookings/{id}/finish
- GET /stats returns accuracy numbers (real_visits, wait_mae_min, wait_baseline_mae_min, wait_interval_coverage, eat_mae_min) or a note when there is no data yet.

## Pages
1. **index.html**: login form and register form (name, phone, password). On success go to restaurants.html.
2. **restaurants.html**: table of restaurants (name, type, area, people waiting, tables in use). A "Book" link goes to book.html?restaurant_id=N. Redirect to index.html if not logged in.
3. **book.html**: steps on one page.
   - "Who are you dining with?" radio buttons: friends, colleagues, family.
   - Number of members (total including me), number input 1 to 30.
   - Friends: a list of phone number inputs plus an "Add another friend" button (max party size minus 1). If `navigator.contacts` and `navigator.contacts.select` exist, also show a "Pick from contacts" button that fills phone numbers (only when supported; manual entry always works). Say in plain text that friends who also use the app will see this booking.
   - "Check estimate" button calls /predict and shows: expected seating time, wait range (p10 to p90 minutes), expected eating time, expected finish time, parties ahead.
   - "Confirm booking" button calls POST /bookings, then goes to booking.html?id=ID.
4. **mybookings.html**: table of /bookings/mine with status, restaurant, role and a link to details. Guests with pending invites get Accept and Decline buttons on the detail page.
5. **booking.html?id=N**: show booking details, member list (name or "xxxxxx" + last 4 digits, and invite status), the live estimate while waiting, and "eating for X minutes" while seated. A "Refresh" button reloads; also auto-refresh every 30 seconds with no visual effect. Host sees a Cancel button while waiting. Invited users see Accept/Decline.
6. **staff.html**: input for staff key and restaurant dropdown (from /restaurants). Show the queue table with a "Seat" button for waiting parties and a "Finish" button for seated parties. After Finish, show the returned actual vs predicted times.
7. **stats.html**: show /stats values in a simple table, with a one-line explanation of each.

Output complete file contents for every file, ready to save, and a short note on how to open them (just open index.html, or serve the folder with `python -m http.server 5500`).
