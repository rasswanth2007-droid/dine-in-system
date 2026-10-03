source("model.R")
set.seed(42)
init_db()
con <- db()
if (dbGetQuery(con, "SELECT COUNT(*) n FROM restaurants")$n == 0) {
  rest <- data.frame(
    name = c("Mandhi Palace", "Desert Rose Mandhi", "Urban Bites (franchise)", "Grill Hub (franchise)",
             "Saffron Fine Dine", "Corner Cafe",
             "Spice Garden", "The Biryani Co.", "Olive Bistro", "Noodle Street", "Royal Darbaar"),
    type = c("mandhi", "mandhi", "franchise", "franchise", "finedine", "cafe",
             "mandhi", "franchise", "finedine", "cafe", "finedine"),
    city = c("Coimbatore", "Chennai", "Coimbatore", "Chennai", "Chennai", "Coimbatore",
             "Coimbatore", "Chennai", "Chennai", "Coimbatore", "Chennai"),
    area = c("Central", "Central", "Mall road", "Highway", "Downtown", "Market street",
             "RS Puram", "T. Nagar", "Alwarpet", "Anna Nagar", "Nungambakkam"))
  dbWriteTable(con, "restaurants", rest, append = TRUE)
  ids <- dbGetQuery(con, "SELECT restaurant_id, type FROM restaurants")
  caps <- list(mandhi   = c(4, 4, 6, 6, 8, 10),
               franchise = c(2, 2, 2, 4, 4, 4, 6, 8),
               finedine  = c(2, 2, 4, 4, 6),
               cafe      = c(2, 2, 2, 2, 4, 4))
  for (i in seq_len(nrow(ids)))
    dbWriteTable(con, "dining_tables",
                 data.frame(restaurant_id = ids$restaurant_id[i], capacity = caps[[ids$type[i]]]), append = TRUE)

  # SYNTHETIC history (assumed distributions) so the model is not empty at launch
  base <- c(mandhi = 55, franchise = 45, finedine = 70, cafe = 40)
  gm <- c(friends = 1.25, colleagues = .85, family = 1.1)
  pm <- c(breakfast = .8, lunch = 1, snacks = .85, dinner = 1.15)
  n <- 900
  v <- data.frame(restaurant_id = sample(ids$restaurant_id, n, TRUE),
                  group_type = sample(GROUPS, n, TRUE, prob = c(.45, .2, .35)),
                  party_size = pmin(10, 1 + rpois(n, 2.5)),
                  meal_period = sample(PERIODS, n, TRUE, prob = c(.1, .4, .15, .35)))
  rt <- ids$type[match(v$restaurant_id, ids$restaurant_id)]
  mu <- unname(base[rt] * gm[v$group_type] * pm[v$meal_period]) + 2.5 * (v$party_size - 2)
  v$duration_min <- pmax(8, rgamma(n, shape = 6, rate = 6 / mu))
  v$synthetic <- 1
  dbWriteTable(con, "visits", v, append = TRUE)
}
train_model(con)
print(summary(MODEL$fit))
dbDisconnect(con)
