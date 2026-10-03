source("model.R")
STAFF_KEY <- Sys.getenv("STAFF_KEY", "staff123")
local({ con <- db(); train_model(con); dbDisconnect(con) })

err <- function(res, code, msg) { res$status <- code; list(error = msg) }
staff_ok <- function(req) identical(req$HTTP_X_STAFF_KEY, STAFF_KEY)
user_of <- function(req, con) {
  tok <- req$HTTP_X_TOKEN
  if (is.null(tok)) return(NULL)
  r <- qry(con, "SELECT user_id FROM sessions WHERE token = ?", tok)
  if (nrow(r)) r$user_id else NULL
}
new_session <- function(con, uid) { t <- UUIDgenerate(); exe(con, "INSERT INTO sessions VALUES (?,?,?)", t, uid, ts_now()); t }

#* @filter cors
function(req, res) {
  res$setHeader("Access-Control-Allow-Origin", "*")
  res$setHeader("Access-Control-Allow-Headers", "Content-Type, X-Token, X-Staff-Key")
  res$setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
  if (req$REQUEST_METHOD == "OPTIONS") { res$status <- 200; return(list()) }
  plumber::forward()
}

#* Create account. Body: name, phone, password
#* @post /register
function(req, res) {
  b <- req$body; con <- db(); on.exit(dbDisconnect(con))
  p <- norm_phone(b$phone)
  if (length(b$name) != 1 || !nzchar(b$name) || is.na(p) || length(b$password) != 1 || nchar(b$password) < 6)
    return(err(res, 400, "name, 10-digit phone and password (6+ chars) required"))
  h <- phone_hash(p)
  if (nrow(qry(con, "SELECT 1 FROM users WHERE phone_hash = ?", h))) return(err(res, 409, "phone already registered"))
  salt <- UUIDgenerate()
  exe(con, "INSERT INTO users (name, phone_hash, phone_last4, salt, pass_hash, created_at) VALUES (?,?,?,?,?,?)",
      b$name, h, substr(p, 7, 10), salt, hash_pw(b$password, salt), ts_now())
  uid <- qry(con, "SELECT last_insert_rowid() AS id")$id
  # friends who added this phone earlier now see those bookings
  exe(con, "UPDATE booking_members SET user_id = ?, invite_status = 'pending' WHERE phone_hash = ? AND user_id IS NULL", uid, h)
  list(token = new_session(con, uid), user_id = uid, name = b$name)
}

#* Body: phone, password
#* @post /login
function(req, res) {
  b <- req$body; con <- db(); on.exit(dbDisconnect(con))
  p <- norm_phone(b$phone)
  u <- if (is.na(p)) data.frame() else qry(con, "SELECT * FROM users WHERE phone_hash = ?", phone_hash(p))
  if (!nrow(u) || !identical(u$pass_hash, hash_pw(b$password, u$salt))) return(err(res, 401, "wrong phone or password"))
  list(token = new_session(con, u$user_id), user_id = u$user_id, name = u$name)
}

#* @get /restaurants
function() {
  con <- db(); on.exit(dbDisconnect(con))
  qry(con, "SELECT r.restaurant_id, r.name, r.type, r.city, r.area,
              COUNT(t.table_id) AS tables, MAX(t.capacity) AS max_capacity,
              (SELECT COUNT(*) FROM bookings b WHERE b.restaurant_id = r.restaurant_id AND b.status = 'confirmed') AS waiting,
              (SELECT COUNT(*) FROM bookings b WHERE b.restaurant_id = r.restaurant_id AND b.status = 'seated') AS seated_now
            FROM restaurants r JOIN dining_tables t ON t.restaurant_id = r.restaurant_id
            GROUP BY r.restaurant_id")
}

#* Estimate without booking. Query: restaurant_id, party_size, group_type
#* @get /predict
function(req, res) {
  a <- req$argsQuery; con <- db(); on.exit(dbDisconnect(con))
  gt <- if (is.null(a$group_type)) "friends" else a$group_type
  if (is.null(a$restaurant_id) || is.null(a$party_size) || !(gt %in% GROUPS))
    return(err(res, 400, "restaurant_id, party_size, group_type (friends/colleagues/family) required"))
  tryCatch(predict_seating(con, as.integer(a$restaurant_id), as.integer(a$party_size), gt),
           error = function(e) err(res, 400, conditionMessage(e)))
}

#* Body: restaurant_id, group_type, party_size, members (array of friend phone numbers)
#* @post /bookings
function(req, res) {
  con <- db(); on.exit(dbDisconnect(con))
  uid <- user_of(req, con); if (is.null(uid)) return(err(res, 401, "login required"))
  b <- req$body
  rid <- as.integer(b$restaurant_id); n <- as.integer(b$party_size); gt <- b$group_type
  valid <- length(rid) == 1 && length(n) == 1 && !is.na(rid) && !is.na(n) &&
    length(gt) == 1 && gt %in% GROUPS && n >= 1 && n <= 30
  if (!valid) return(err(res, 400, "restaurant_id, party_size (1-30), group_type required"))
  me <- qry(con, "SELECT phone_hash FROM users WHERE user_id = ?", uid)$phone_hash
  phones <- vapply(as.list(unlist(b$members)), norm_phone, "")
  phones <- unique(phones[!is.na(phones)])
  phones <- phones[vapply(phones, phone_hash, "") != me]
  if (length(phones) > n - 1) return(err(res, 400, "more friends than party_size - 1"))
  pred <- tryCatch(predict_seating(con, rid, n, gt), error = function(e) e)
  if (inherits(pred, "error")) return(err(res, 400, conditionMessage(pred)))
  exe(con, "INSERT INTO bookings (restaurant_id, host_user_id, group_type, party_size, created_at,
            pred_wait_p10, pred_wait_p50, pred_wait_p90, pred_eat_p50) VALUES (?,?,?,?,?,?,?,?,?)",
      rid, uid, gt, n, ts_now(), pred$wait_min$p10, pred$wait_min$p50, pred$wait_min$p90, pred$eat_min_p50)
  bid <- qry(con, "SELECT last_insert_rowid() AS id")$id
  for (p in phones) {
    h <- phone_hash(p); u <- qry(con, "SELECT user_id FROM users WHERE phone_hash = ?", h)
    exe(con, "INSERT INTO booking_members (booking_id, phone_hash, phone_last4, user_id, invite_status) VALUES (?,?,?,?,?)",
        bid, h, substr(p, 7, 10), if (nrow(u)) u$user_id else NA_integer_, if (nrow(u)) "pending" else "not_on_app")
  }
  c(list(booking_id = bid), pred)
}

#* Bookings I host or was invited to
#* @get /bookings/mine
function(req, res) {
  con <- db(); on.exit(dbDisconnect(con))
  uid <- user_of(req, con); if (is.null(uid)) return(err(res, 401, "login required"))
  qry(con, "SELECT b.booking_id, r.name AS restaurant, b.group_type, b.party_size, b.status,
              b.pred_wait_p50, b.pred_eat_p50, b.created_at,
              CASE WHEN b.host_user_id = ? THEN 'host' ELSE 'guest' END AS role
            FROM bookings b JOIN restaurants r ON r.restaurant_id = b.restaurant_id
            WHERE b.host_user_id = ? OR b.booking_id IN (SELECT booking_id FROM booking_members WHERE user_id = ?)
            ORDER BY b.booking_id DESC", uid, uid, uid)
}

#* Booking detail with live re-estimate while waiting
#* @get /bookings/<id:int>
function(id, req, res) {
  con <- db(); on.exit(dbDisconnect(con))
  uid <- user_of(req, con); if (is.null(uid)) return(err(res, 401, "login required"))
  b <- qry(con, "SELECT b.*, r.name AS restaurant, u.name AS host FROM bookings b
                 JOIN restaurants r ON r.restaurant_id = b.restaurant_id
                 JOIN users u ON u.user_id = b.host_user_id WHERE b.booking_id = ?", id)
  if (!nrow(b)) return(err(res, 404, "booking not found"))
  allowed <- b$host_user_id == uid ||
    nrow(qry(con, "SELECT 1 FROM booking_members WHERE booking_id = ? AND user_id = ?", id, uid)) > 0
  if (!allowed) return(err(res, 403, "not your booking"))
  mem <- qry(con, "SELECT m.phone_last4, m.invite_status, u.name FROM booking_members m
                   LEFT JOIN users u ON u.user_id = m.user_id WHERE m.booking_id = ?", id)
  out <- list(booking = as.list(b), members = mem)
  if (b$status == "confirmed")
    out$live_estimate <- predict_seating(con, b$restaurant_id, b$party_size, b$group_type, before_id = id)
  if (b$status == "seated") out$eating_for_min <- round(mins_since(b$seated_at))
  out
}

#* Body: action = "accept" | "decline"
#* @post /bookings/<id:int>/respond
function(id, req, res) {
  con <- db(); on.exit(dbDisconnect(con))
  uid <- user_of(req, con); if (is.null(uid)) return(err(res, 401, "login required"))
  a <- req$body$action
  if (!identical(a, "accept") && !identical(a, "decline")) return(err(res, 400, "action must be accept or decline"))
  n <- exe(con, "UPDATE booking_members SET invite_status = ? WHERE booking_id = ? AND user_id = ?",
           if (a == "accept") "accepted" else "declined", id, uid)
  if (n == 0) return(err(res, 404, "no invite for you on this booking"))
  list(ok = TRUE)
}

#* @post /bookings/<id:int>/cancel
function(id, req, res) {
  con <- db(); on.exit(dbDisconnect(con))
  uid <- user_of(req, con); if (is.null(uid)) return(err(res, 401, "login required"))
  n <- exe(con, "UPDATE bookings SET status = 'cancelled' WHERE booking_id = ? AND host_user_id = ? AND status = 'confirmed'", id, uid)
  if (n == 0) return(err(res, 409, "only your waiting bookings can be cancelled"))
  list(ok = TRUE)
}

#* Restaurant desk: header X-Staff-Key. Query: restaurant_id
#* @get /staff/queue
function(req, res) {
  if (!staff_ok(req)) return(err(res, 401, "bad staff key"))
  con <- db(); on.exit(dbDisconnect(con))
  qry(con, "SELECT b.booking_id, u.name AS host, b.group_type, b.party_size, b.status, b.table_id,
              b.created_at, b.seated_at, b.pred_wait_p50
            FROM bookings b JOIN users u ON u.user_id = b.host_user_id
            WHERE b.restaurant_id = ? AND b.status IN ('confirmed','seated') ORDER BY b.booking_id",
      as.integer(req$argsQuery$restaurant_id))
}

#* @post /staff/bookings/<id:int>/seat
function(id, req, res) {
  if (!staff_ok(req)) return(err(res, 401, "bad staff key"))
  con <- db(); on.exit(dbDisconnect(con))
  b <- qry(con, "SELECT * FROM bookings WHERE booking_id = ?", id)
  if (!nrow(b) || b$status != "confirmed") return(err(res, 409, "booking is not waiting"))
  t <- qry(con, "SELECT table_id FROM dining_tables WHERE restaurant_id = ? AND capacity >= ?
                 AND table_id NOT IN (SELECT table_id FROM bookings WHERE status = 'seated' AND table_id IS NOT NULL)
                 ORDER BY capacity LIMIT 1", b$restaurant_id, b$party_size)
  if (!nrow(t)) return(err(res, 409, "no free table of suitable size"))
  exe(con, "UPDATE bookings SET status = 'seated', table_id = ?, seated_at = ? WHERE booking_id = ?", t$table_id, ts_now(), id)
  list(booking_id = id, table_id = t$table_id, actual_wait_min = round(mins_since(b$created_at), 1))
}

#* Records the real eating time and retrains the model
#* @post /staff/bookings/<id:int>/finish
function(id, req, res) {
  if (!staff_ok(req)) return(err(res, 401, "bad staff key"))
  con <- db(); on.exit(dbDisconnect(con))
  b <- qry(con, "SELECT * FROM bookings WHERE booking_id = ?", id)
  if (!nrow(b) || b$status != "seated") return(err(res, 409, "booking is not seated"))
  dur <- mins_since(b$seated_at)
  wait <- as.numeric(difftime(as_time(b$seated_at), as_time(b$created_at), units = "mins"))
  exe(con, "INSERT INTO visits (booking_id, restaurant_id, group_type, party_size, meal_period, actual_wait_min,
            duration_min, pred_wait_p10, pred_wait_p50, pred_wait_p90, pred_eat_p50, synthetic)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,0)",
      id, b$restaurant_id, b$group_type, b$party_size, meal_period(as_time(b$seated_at)), wait, dur,
      b$pred_wait_p10, b$pred_wait_p50, b$pred_wait_p90, b$pred_eat_p50)
  exe(con, "UPDATE bookings SET status = 'completed', finished_at = ? WHERE booking_id = ?", ts_now(), id)
  train_model(con)
  list(duration_min = round(dur, 1), actual_wait_min = round(wait, 1),
       predicted_wait_p50 = b$pred_wait_p50, predicted_eat_p50 = b$pred_eat_p50)
}

#* Model accuracy on real (non-synthetic) visits
#* @get /stats
function() {
  con <- db(); on.exit(dbDisconnect(con))
  v <- qry(con, "SELECT * FROM visits WHERE synthetic = 0 AND pred_wait_p50 IS NOT NULL")
  out <- list(real_visits = nrow(v), training_rows = MODEL$n)
  if (nrow(v) == 0) { out$note <- "no completed real visits yet"; return(out) }
  c(out, list(
    wait_mae_min = round(mean(abs(v$actual_wait_min - v$pred_wait_p50)), 2),
    wait_baseline_mae_min = round(mean(abs(v$actual_wait_min - mean(v$actual_wait_min))), 2),
    wait_interval_coverage = round(mean(v$actual_wait_min >= v$pred_wait_p10 & v$actual_wait_min <= v$pred_wait_p90), 2),
    eat_mae_min = round(mean(abs(v$duration_min - v$pred_eat_p50)), 2)))
}
