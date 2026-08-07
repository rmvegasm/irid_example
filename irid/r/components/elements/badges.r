#' r/components/elements/badges — Badge / pill label
#'
#' A small label for tagging, status indication, or counts.
#'
#' @md
#' @name badges
box::use(
  shiny[tags],
)

#' Badge / pill label
#'
#' A small label for tagging, status indication, or counts.
#'
#' @param text Label text.
#' @param variant One of "default", "success", "warning", "danger", "info".
#' @return A shiny.tag `<span>` element.
#' @export
badge <- function(text, variant = "default") {
  variants <- c(
    default = "bg-gray-100 dark:bg-neutral-700 text-gray-800 dark:text-neutral-200",
    success = "bg-green-100 dark:bg-green-900/40 text-green-800 dark:text-green-300",
    warning = "bg-yellow-100 dark:bg-yellow-900/40 text-yellow-800 dark:text-yellow-300",
    danger  = "bg-red-100 dark:bg-red-900/40 text-red-800 dark:text-red-300",
    info    = "bg-blue-100 dark:bg-blue-900/40 text-blue-800 dark:text-blue-300"
  )
  cls <- variants[[variant]]
  if (is.null(cls)) cls <- variants[["default"]]
  tags$span(
    class = paste("inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium", cls),
    text
  )
}
