#' r/components/layouts/app_shell — App shell layout
#'
#' Top-level layout that wraps page content with chrome (navbar,
#' content area). Pages are rendered inside the `...` slot.
#'
#' @md
#' @name app_shell
box::use(
  shiny[tags, tagList],
  irid[When],
)

#' App shell layout
#'
#' Wraps page content in a full-height flex column with a top navbar
#' and a container for the main content area. Use as the top-level
#' layout for every page in an irid app.
#'
#' Returns a `tagList` with `<head>` elements (meta, CSS, title) that
#' Shiny merges into the document head, plus a `<div>` wrapper for the
#' body-level styling. Does NOT wrap in `<html>` / `<body>` — Shiny
#' provides the document shell; adding a second set creates invalid
#' nested `<body>` that loses attributes and confuses anchor lookup.
#'
#' @param ... Child tags (the page content).
#' @param title Page title (shown in navbar and `<title>`).
#' @param user Reactive expression returning the logged-in user, or NULL.
#'   If provided (and non-NULL reactively), the username and logout button
#'   appear in the navbar via a `When` control flow node.
#' @param on_logout A 0-arg function called when the navbar logout button
#'   is clicked. If NULL, the button calls the internal placeholder.
#' @param fluid When `TRUE`, the shell renders full-bleed: the body wrapper
#'   becomes a fixed-height flex column, the main area is a flex-1 region
#'   with no padding/max-width, and the page fills it (used by the map
#'   explorer).
#' @return A shiny tag tree.
#' @export
app_shell <- function(..., title = "App", user = NULL, on_logout = NULL,
                       fluid = FALSE) {
  body_class <- if (fluid) {
    paste(
      "h-screen flex flex-col overflow-hidden",
      "bg-gray-50 dark:bg-neutral-900 text-gray-900 dark:text-neutral-100",
      "font-sans antialiased"
    )
  } else {
    paste(
      "min-h-screen bg-gray-50 dark:bg-neutral-900",
      "text-gray-900 dark:text-neutral-100 font-sans antialiased"
    )
  }
  main_class <- if (fluid) {
    "flex-1 min-h-0 flex flex-col"
  } else {
    "max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8"
  }
  nav_inner_class <- if (fluid) {
    "px-4 sm:px-6 lg:px-8"
  } else {
    "max-w-7xl mx-auto px-4 sm:px-6 lg:px-8"
  }

  tagList(
    # Head elements — Shiny merges these into the document `<head>`
    tags$head(
      tags$meta(charset = "utf-8"),
      tags$meta(name = "viewport", content = "width=device-width, initial-scale=1"),
      # Tailwind CSS v4 — compiled output from `@tailwindcss/cli`.
      # The app's Dockerfile compiles input.css → app.css.
      # During local development without Docker, run:
      #   bash irid/assets/css/build.sh
      tags$link(href = "css/app.css", rel = "stylesheet"),
      tags$title(title)
    ),

    # Body-level wrapper — provides the styling that was on `<body>`.
    # `min-h-screen` on this div inherits from the real `<body>` via CSS.
    tags$div(
      class = body_class,

      # Navbar
      tags$nav(
        class = "bg-white dark:bg-neutral-800 border-b border-gray-200 dark:border-neutral-700 shadow-sm",
        tags$div(
          class = nav_inner_class,
          tags$div(
            class = "flex justify-between h-14 items-center",
            tags$span(class = "text-lg font-semibold text-gray-800 dark:text-neutral-100", title),
            # User area — reactive via When (shown when user() returns non-NULL)
            When(
              function() {
                u <- if (is.function(user)) user() else user
                !is.null(u)
              },
              function() {
                u <- if (is.function(user)) user() else user
                tags$div(
                  class = "flex items-center gap-3",
                  tags$span(class = "text-sm text-gray-500 dark:text-neutral-400", u$username),
                  tags$button(
                    class = "text-sm text-red-600 dark:text-red-400 hover:text-red-800 dark:hover:text-red-300 transition-colors cursor-pointer",
                    "Sign out",
                    onClick = if (is.null(on_logout)) function() .trigger_logout() else on_logout
                  )
                )
              }
            )
          )
        )
      ),

      # Main content
      tags$main(
        class = main_class,
        ...
      )
    )
  )
}

#' Internal helper: trigger logout
.trigger_logout <- function() {
  # In a real app, this would invalidate the session.
  # The irid app handles this via reactive state + When().
}
