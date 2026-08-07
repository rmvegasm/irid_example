#' r/components/containers/cards — Card container
#'
#' A bordered, rounded container with optional padding. Used for
#' grouping related content (analogous to a card component).
#'
#' @md
#' @name cards
box::use(
  shiny[tags],
)

#' Card container
#'
#' A bordered, rounded container with optional padding. Used for
#' grouping related content (analogous to a card component).
#'
#' @param ... Child content.
#' @param class Additional CSS classes.
#' @return A shiny.tag `<div>` element.
#' @export
card <- function(..., class = "") {
  tags$div(
    class = paste("bg-white dark:bg-neutral-800 rounded-lg shadow-sm border border-gray-200 dark:border-neutral-700 p-6", class),
    ...
  )
}
