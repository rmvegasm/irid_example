#' r/components/forms/login — Login form component
#'
#' A login form that binds to a reactiveStore's `login_form` and
#' `auth` branches. Wraps inputs + error banner in a card.
#'
#' @md
#' @name login
box::use(
  shiny[tags],
  irid[When, reactiveProxy],
)

box::use(
  ../elements/alert[alert],
  ../elements/inputs[text_input, password_input],
  ../elements/buttons[btn_primary],
  ../containers/cards[card],
)

#' Login form
#'
#' A card containing username/password inputs and a sign-in button.
#' Displays an error banner when `store$auth$auth_error` is non-empty.
#' All inputs are reactively bound to the store's `login_form` branch.
#'
#' @param store A `reactiveStore` with branches:
#'   - `auth$auth_error` — character reactiveVal, shown as error banner
#'   - `login_form$username` — character reactiveVal, bound to username input
#'   - `login_form$password` — character reactiveVal, bound to password input
#' @param on_login A 0-arg function called when the sign-in button is clicked.
#' @param title Card heading text.
#' @return A shiny tag tree (a card with form elements).
#' @export
login_form <- function(store, on_login, title = "Sign in") {
  card(
    tags$h2(class = "text-2xl font-bold mb-6 text-center", title),

    # Error banner — shown only when auth_error is non-empty
    When(
      \() nchar(store$auth$auth_error()) > 0,
      \() alert(store$auth$auth_error(), variant = "error")
    ),

    # Form inputs
    tags$div(class = "space-y-4",
      text_input(
        label = "Username",
        placeholder = "demo",
        value = reactiveProxy(
          get = store$login_form$username,
          set = \(v) store$login_form$username(v)
        )
      ),

      password_input(
        label = "Password",
        value = reactiveProxy(
          get = store$login_form$password,
          set = \(v) store$login_form$password(v)
        )
      ),

      # Submit button
      tags$div(class = "pt-2",
        btn_primary("Sign in", onClick = on_login)
      ),

      # Demo hint
      tags$p(
        class = "mt-4 text-xs text-gray-400 dark:text-neutral-500 text-center",
        'Demo account: username "demo", password "demo123"'
      )
    )
  )
}
