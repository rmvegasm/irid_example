#' r/components/buttons — Action buttons
#'
#' Three button variants consistent with the SolidStart app's button
#' component styling (Tailwind CSS classes).
#'
#' @md
#' @name buttons
box::use(
  shiny[tags],
)

#' Primary action button
#'
#' Filled blue button for the primary call to action.
#'
#' @param label Button text.
#' @param ... Additional attributes (class, onClick, etc.).
#' @return A shiny.tag `<button>` element.
#' @export
btn_primary <- function(label, ...) {
  tags$button(
    class = "inline-flex items-center px-4 py-2 border border-transparent
             text-sm font-medium rounded-md shadow-sm text-white
             bg-blue-600 hover:bg-blue-700 focus:outline-none
             focus:ring-2 focus:ring-offset-2 focus:ring-blue-500
             transition-colors cursor-pointer",
    label,
    ...
  )
}

#' Secondary / outline button
#'
#' Ghost-style button with border, suitable for secondary actions.
#'
#' @param label Button text.
#' @param ... Additional attributes.
#' @return A shiny.tag `<button>` element.
#' @export
btn_secondary <- function(label, ...) {
  tags$button(
    class = "inline-flex items-center px-4 py-2 border border-gray-300 dark:border-neutral-600
             text-sm font-medium rounded-md shadow-sm text-gray-700 dark:text-neutral-200
             bg-white dark:bg-neutral-700 hover:bg-gray-50 dark:hover:bg-neutral-600 focus:outline-none
             focus:ring-2 focus:ring-offset-2 dark:focus:ring-offset-neutral-800 focus:ring-blue-500
             transition-colors cursor-pointer",
    label,
    ...
  )
}

#' Danger / destructive button
#'
#' Red button for irreversible actions (delete, sign out, etc.).
#'
#' @param label Button text.
#' @param ... Additional attributes.
#' @return A shiny.tag `<button>` element.
#' @export
btn_danger <- function(label, ...) {
  tags$button(
    class = "inline-flex items-center px-4 py-2 border border-transparent
             text-sm font-medium rounded-md shadow-sm text-white
             bg-red-600 hover:bg-red-700 focus:outline-none
             focus:ring-2 focus:ring-offset-2 focus:ring-red-500
             transition-colors cursor-pointer",
    label,
    ...
  )
}
