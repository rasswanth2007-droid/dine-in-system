suppressPackageStartupMessages({ library(DBI); library(RSQLite); library(digest); library(uuid) })
LOCAL_TZ <- "Asia/Kolkata"
DB_PATH  <- Sys.getenv("DB_PATH", "dinein.sqlite")
GROUPS   <- c("friends", "colleagues", "family")

db  <- function() { con <- dbConnect(SQLite(), DB_PATH); dbExecute(con, "PRAGMA foreign_keys = ON"); con }

qry <- function(con, sql, ...) {
  params <- list(...)
  if (length(params) == 0) dbGetQuery(con, sql)
  else dbGetQuery(con, sql, params = params)
}

exe <- function(con, sql, ...) {
  params <- list(...)
  if (length(params) == 0) dbExecute(con, sql)
  else dbExecute(con, sql, params = params)
}

ts_now     <- function() format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC")
as_time    <- function(x) as.POSIXct(x, tz = "UTC")
mins_since <- function(x) as.numeric(difftime(Sys.time(), as_time(x), units = "mins"))

norm_phone <- function(p) {
  if (length(p) != 1 || is.na(p)) return(NA_character_)
  d <- gsub("\\D", "", as.character(p))
  if (nchar(d) < 10) return(NA_character_)
  substr(d, nchar(d) - 9, nchar(d))
}
phone_hash <- function(d) digest(d, algo = "sha256", serialize = FALSE)
hash_pw    <- function(pw, salt) digest(paste0(salt, pw), algo = "sha256", serialize = FALSE)

init_db <- function(path = "schema.sql") {
  con <- db()
  stmts <- trimws(strsplit(paste(readLines(path), collapse = "\n"), ";")[[1]])
  for (s in stmts[nzchar(stmts)]) dbExecute(con, s)
  dbDisconnect(con)
}