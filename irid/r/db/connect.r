#' db/connect — Database connection management
#'
#' Functions to create and close PostgreSQL connections.
#' Thin wrappers around DBI + RPostgres.
#'
#' @md
#' @name connect
box::use(
  DBI[dbConnect, dbDisconnect],
  RPostgres[Postgres],
)

#' Create a database connection from environment variables
#'
#' Reads PGHOST, PGPORT, PGUSER, PGPASSWORD, PGDATABASE from the
#' environment (set by Compose). Returns a DBI connection.
#'
#' @return A DBI connection object (RPostgres).
#' @export
connect <- function() {
  dbConnect(
    Postgres(),
    host     = Sys.getenv("PGHOST", "localhost"),
    port     = as.integer(Sys.getenv("PGPORT", "5432")),
    user     = Sys.getenv("PGUSER", "postgres"),
    password = Sys.getenv("PGPASSWORD", "postgres"),
    dbname   = Sys.getenv("PGDATABASE", "irid_example")
  )
}

#' Close a database connection
#'
#' @param con A DBI connection.
#' @export
disconnect <- function(con) {
  dbDisconnect(con)
}
