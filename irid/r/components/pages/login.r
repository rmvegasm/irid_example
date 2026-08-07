#' r/components/pages/login — Login page
#'
#' Full login page: vertically/horizontally centered card containing
#' the login form. This is a `pages/` component — it composes
#' `containers/` and `forms/` into a complete page ready to be
#' dropped inside `app_shell`.
#'
#' @md
#' @name login_page
box::use(
  shiny[tags],
)

box::use(
  ../forms/login[login_form],
)

#' Login page
#'
#' Centers a login form on screen. Designed to be rendered inside
#' an `app_shell` layout as the main content slot.
#'
#' @param store A `reactiveStore` with `auth` and `login_form` branches.
#' @param on_login A 0-arg function called when the sign-in button is
#'   clicked.
#' @param title Page/card heading text.
#' @return A shiny tag tree.
#' @export
login_page <- function(store, on_login, title = "Sign in") {
  tags$div(
    class = "min-h-[60vh] flex items-center justify-center",
    tags$div(
      class = "w-full max-w-md",
      login_form(store = store, on_login = on_login, title = title)
    )
  )
}
