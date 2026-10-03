source("db.R")
PERIODS <- c("breakfast", "lunch", "snacks", "dinner")
MODEL <- new.env()

meal_period <- function(t = Sys.time()) {
  h <- as.integer(format(t, "%H", tz = LOCAL_TZ))
  as.character(cut(h, c(-1, 10, 15, 18, 23), labels = PERIODS))
}

# Step 1: eating-duration model (Gamma GLM, log link)
train_model <- function(con) {
  d <- dbGetQuery(con, "SELECT v.duration_min, v.group_type, v.party_size, v.meal_period, r.type AS rtype
                        FROM visits v JOIN restaurants r ON r.restaurant_id = v.restaurant_id")
  if (nrow(d) < 30) stop("not enough visit data - run seed.R first")
  fit <- glm(duration_min ~ group_type + party_size + meal_period + rtype,
             family = Gamma(link = "log"), data = d)
  MODEL$fit <- fit; MODEL$phi <- summary(fit)$dispersion
  MODEL$mean <- mean(d$duration_min); MODEL$n <- nrow(d)
  invisible(fit)
}

predict_mu <- function(group_type, party_size, period, rtype) {
  nd <- data.frame(group_type = group_type, party_size = party_size,
                   meal_period = period, rtype = rtype, stringsAsFactors = FALSE)
  tryCatch(as.numeric(predict(MODEL$fit, nd, type = "response")),
           error = function(e) rep(MODEL$mean, nrow(nd)))
}

draw_dur <- function(mu) { shape <- 1 / MODEL$phi; rgamma(length(mu), shape = shape, rate = shape / mu) }

# remaining time for a table already in use: duration conditioned on > elapsed
rem_draw <- function(mu, elapsed) {
  for (k in 1:30) { d <- draw_dur(mu); if (d > elapsed) return(d - elapsed) }
  runif(1, 1, 5)
}

# Steps 2-3: Monte Carlo seating prediction.
# Parties ahead of this one (booking_id < before_id) take tables first.
predict_seating <- function(con, restaurant_id, party_size, group_type,
                            before_id = 2147483647, n_sim = 800) {
  rest <- qry(con, "SELECT type FROM restaurants WHERE restaurant_id = ?", restaurant_id)
  if (!nrow(rest)) stop("unknown restaurant")
  tabs <- qry(con, "SELECT table_id, capacity FROM dining_tables WHERE restaurant_id = ?", restaurant_id)
  if (!any(tabs$capacity >= party_size)) stop("no table large enough for this party")
  per <- meal_period(); now <- Sys.time()
  occ <- qry(con, "SELECT table_id, party_size, group_type, seated_at FROM bookings
                   WHERE restaurant_id = ? AND status = 'seated'", restaurant_id)
  que <- qry(con, "SELECT party_size, group_type FROM bookings
                   WHERE restaurant_id = ? AND status = 'confirmed' AND booking_id < ?
                   ORDER BY booking_id", restaurant_id, before_id)
  mu_occ <- if (nrow(occ)) predict_mu(occ$group_type, occ$party_size, per, rest$type) else numeric(0)
  el_occ <- if (nrow(occ)) unname(sapply(occ$seated_at, mins_since)) else numeric(0)
  mu_que <- if (nrow(que)) predict_mu(que$group_type, que$party_size, per, rest$type) else numeric(0)
  mu_new <- predict_mu(group_type, party_size, per, rest$type)
  tid <- as.character(tabs$table_id)

  sim <- replicate(n_sim, {
    free <- setNames(rep(0, nrow(tabs)), tid)
    for (i in seq_along(mu_occ)) free[as.character(occ$table_id[i])] <- rem_draw(mu_occ[i], el_occ[i])
    for (j in seq_along(mu_que)) {
      ok <- which(tabs$capacity >= que$party_size[j])
      if (!length(ok)) next
      k <- ok[which.min(free[ok])]
      free[k] <- free[k] + draw_dur(mu_que[j])
    }
    ok <- which(tabs$capacity >= party_size)
    c(min(free[ok]), draw_dur(mu_new))
  })
  w <- sim[1, ]; d <- sim[2, ]; q <- quantile(w, c(.1, .5, .9))
  list(wait_min = list(p10 = round(q[[1]]), p50 = round(q[[2]]), p90 = round(q[[3]])),
       eat_min_p50 = round(median(d)),
       expected_seat_time = format(now + q[[2]] * 60, "%H:%M", tz = LOCAL_TZ),
       expected_finish_time = format(now + median(w + d) * 60, "%H:%M", tz = LOCAL_TZ),
       parties_ahead = nrow(que), tables_in_use = nrow(occ),
       tables_total = nrow(tabs), model_visits = MODEL$n)
}
