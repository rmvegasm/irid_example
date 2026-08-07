#' db/users — User authentication helpers
#'
#' Query the users table, hash and verify passwords, generate session tokens.
#' Password hashing uses bcrypt (the same algorithm as the Node.js apps).
#'
#' @md
#' @name users
box::use(
  DBI[dbGetQuery],
  bcrypt[checkpw, hashpw],
  sodium[bin2hex, random],
)

#' Get a user by username
#'
#' @param con A DBI connection.
#' @param username Character string.
#' @return A named list with columns from the `users` row, or NULL if
#'   not found.
#' @export
get_user <- function(con, username) {
  stopifnot(is.character(username), length(username) == 1)
  query <- "SELECT id, username, password_hash, created_at FROM users WHERE username = $1"
  result <- dbGetQuery(con, query, list(username))
  if (nrow(result) == 0) return(NULL)
  as.list(result[1, ])
}

#' Create a new user
#'
#' Inserts a row into the `users` table. The password must already be
#' hashed by the caller (see [hash_password]).
#'
#' @param con A DBI connection.
#' @param username Character string.
#' @param password_hash Character string — bcrypt hash.
#' @return The new user's id (integer), or NULL on conflict.
#' @export
create_user <- function(con, username, password_hash) {
  stopifnot(is.character(username), length(username) == 1)
  stopifnot(is.character(password_hash), length(password_hash) == 1)
  query <- "
    INSERT INTO users (username, password_hash)
    VALUES ($1, $2)
    ON CONFLICT (username) DO NOTHING
    RETURNING id
  "
  result <- dbGetQuery(con, query, list(username, password_hash))
  if (nrow(result) == 0) return(NULL)
  result$id[1]
}

#' Hash a password using bcrypt
#'
#' Wraps the bcrypt package for consistent hashing across R apps.
#'
#' @param password Character string (plaintext).
#' @return Character string (bcrypt hash).
#' @export
hash_password <- function(password) {
  hashpw(password)
}

#' Verify a password against a bcrypt hash
#'
#' Normalises the hash prefix so that \code{$2b$} (Node.js bcrypt) and
#' \code{$2y$} (OpenBSD, PHP) are recognised by the R bcrypt package
#' (which uses \code{$2a$}). The underlying algorithm is identical for
#' all three variants in modern implementations.
#'
#' @param password Character string (plaintext).
#' @param hash Character string (bcrypt hash from the database).
#' @return TRUE if the password matches, FALSE otherwise.
#' @export
check_password <- function(password, hash) {
  # Normalise non-$2a$ prefixes to $2a$ for bcrypt R package compatibility
  hash <- sub("^\\$2[b-y]\\$", "$2a$", hash)
  checkpw(password, hash)
}

#' Generate a random session token
#'
#' Uses sodium to produce a hex-encoded 32-byte token.
#'
#' @return Character string.
#' @export
generate_token <- function() {
  bin2hex(random(32))
}
