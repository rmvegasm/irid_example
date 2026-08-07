#' server/auth — Authentication handlers
#'
#' Factory functions that produce login/logout event handlers for irid apps.
#' Each handler takes a `reactiveStore` and returns a 0-arg closure suitable
#' for use as an `onClick` or similar event handler.
#'
#' Handlers are defined outside the app body so they are testable and reusable
#' across apps. The store parameter decouples handler logic from app-internal
#' state setup.
#'
#' @md
#' @name auth
box::use(
  ../db,
)

#' Create a login handler
#'
#' Reads credentials from `store$login_form$username` / `$password`, verifies
#' against the database via `r/db`, and updates `store$auth` on success
#' or sets `auth_error` on failure.
#'
#' @param store A `reactiveStore` with at least:
#'   - `auth`: branch with `logged_in`, `user_name`, `user_id`, `auth_error`
#'   - `login_form`: branch with `username`, `password`
#' @return A 0-arg function suitable for `onClick` on a sign-in button.
#' @export
handle_login <- function(store) {
  force(store)
  \() {
    con <- db$connect()
    on.exit(db$disconnect(con))

    user <- db$get_user(con, store$login_form$username())

    if (is.null(user) || !db$check_password(store$login_form$password(), user$password_hash)) {
      store$auth(list(
        logged_in = FALSE,
        user_name = "",
        user_id = NULL,
        auth_error = "Invalid username or password"
      ))
      return()
    }

    # Success
    store$auth(list(
      logged_in = TRUE,
      user_name = user$username,
      user_id = user$id,
      auth_error = ""
    ))
    store$login_form$password("")   # clear password from memory
  }
}

#' Create a logout handler
#'
#' Resets the `auth` branch to its logged-out state.
#'
#' @param store A `reactiveStore` with an `auth` branch.
#' @return A 0-arg function suitable for `onClick` on a sign-out button.
#' @export
handle_logout <- function(store) {
  force(store)
  \() {
    store$auth(list(
      logged_in = FALSE,
      user_name = "",
      user_id = NULL,
      auth_error = ""
    ))
  }
}
