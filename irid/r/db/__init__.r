#' r/db — Database interaction module
#'
#' Aggregates sub-modules for database connections and user authentication.
#' Apps import this module via `box::use(r/db)`.
#'
#' ## Reexport pattern
#'
#' The `__init__.r` file reexports all public functions from sub-modules
#' so that callers import a single name (`db`) and get all functionality:
#'
#' ```r
#' box::use(r/db)
#' db$connect()
#' db$get_user(con, "demo")
#' ```
#'
#' Internally, the module is split by concern into `connect.r` and
#' `users.r`. Each sub-module declares only its own `box::use()` imports.
#' The reexport layer is the sole public interface.
#'
#' @md
#' @name db
#' @export
box::use(
  ./connect[connect, disconnect],
  ./users[
    check_password, create_user, generate_token,
    get_user, hash_password
  ],
)
