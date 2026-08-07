#' r/components/elements/alert — Alert / notification banner
#'
#' A colored banner for feedback messages, imported from the
#' elements submodule.
#'
#' @md
#' @name alert
box::use(
  shiny[tags],
)

#' Alert / notification banner
#'
#' A colored banner for feedback messages (success, error, info, warning).
#'
#' @param message Alert text.
#' @param variant One of "info", "success", "warning", "error".
#' @return A shiny.tag `<div>` element.
#' @export
alert <- function(message, variant = "info") {
  variants <- c(
    info    = "bg-blue-50 dark:bg-blue-900/30 text-blue-700 dark:text-blue-300 border-blue-200 dark:border-blue-800",
    success = "bg-green-50 dark:bg-green-900/30 text-green-700 dark:text-green-300 border-green-200 dark:border-green-800",
    warning = "bg-yellow-50 dark:bg-yellow-900/30 text-yellow-700 dark:text-yellow-300 border-yellow-200 dark:border-yellow-800",
    error   = "bg-red-50 dark:bg-red-900/30 text-red-700 dark:text-red-300 border-red-200 dark:border-red-800"
  )
  cls <- variants[[variant]]
  if (is.null(cls)) cls <- variants[["info"]]
  tags$div(
    class = paste("rounded-md border px-4 py-3 text-sm", cls),
    tags$p(message)
  )
}
