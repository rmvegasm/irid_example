#' r/components/tables/data_table — Static HTML data table
#'
#' Renders a data.frame as a styled HTML table. For interactive tables
#' use irid's DTOutput or TableOutput.
#'
#' @md
#' @name data_table
box::use(
  shiny[tags],
)

#' Data table (static HTML)
#'
#' Renders a data.frame as a styled HTML table.
#'
#' @param data A data.frame.
#' @param class Additional CSS classes.
#' @return A shiny.tag `<table>` element.
#' @export
data_table <- function(data, class = "") {
  if (!is.data.frame(data)) stop("'data' must be a data.frame")
  tags$div(
    class = "overflow-x-auto",
    tags$table(
      class = paste(
        "min-w-full divide-y divide-gray-200 dark:divide-neutral-700 border border-gray-200 dark:border-neutral-700 rounded-lg", class
      ),
      # Header
      tags$thead(
        class = "bg-gray-50 dark:bg-neutral-800",
        tags$tr(
          lapply(names(data), function(nm) {
            tags$th(
              class = "px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-neutral-400 uppercase tracking-wider",
              nm
            )
          })
        )
      ),
      # Body
      tags$tbody(
        class = "bg-white dark:bg-neutral-800 divide-y divide-gray-200 dark:divide-neutral-700",
        lapply(seq_len(nrow(data)), function(i) {
          tags$tr(
            lapply(data[i, ], function(val) {
              tags$td(
                class = "px-4 py-3 text-sm text-gray-700 dark:text-neutral-300 whitespace-nowrap",
                format(val, trim = TRUE)
              )
            })
          )
        })
      )
    )
  )
}
