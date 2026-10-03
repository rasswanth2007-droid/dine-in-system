# Run from inside this folder:  Rscript run.R
library(plumber)
if (!file.exists(Sys.getenv("DB_PATH", "dinein.sqlite"))) source("seed.R")
pr("api.R") |>
  pr_set_serializer(serializer_json(na = "null")) |>
  pr_run(host = "0.0.0.0", port = 8000)
