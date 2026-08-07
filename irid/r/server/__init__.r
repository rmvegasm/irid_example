#' r/server — Server-side handlers
#'
#' Handlers that require a Shiny server context (reactive state,
#' database connections, session management).
#'
#' @md
#' @name server
#' @export
box::use(
  ./auth[handle_login, handle_logout],
)
