#' r/components/pages/mtcars — Mtcars scatter-plot explorer
#'
#' A composite component that renders variable selectors (x, y, colour)
#' and a ggplot2 plot output, all reactively bound to a `reactiveStore`'s
#' `plot` branch. All styles are self-contained via the underlying
#' primitive components; no styling lives in the app.
#'
#' @md
#' @name mtcars
box::use(
  shiny[tags, tagList],
  irid[PlotOutput, reactiveProxy],
  stats[setNames],
)

box::use(
  ../containers/cards[card],
  ../elements/inputs[select_input],
)

#' Mtcars explorer panel
#'
#' Renders a grid of three selectors (X-axis, Y-axis, Color by) bound to
#' `store$plot` and a PlotOutput fed by the provided `plot_fn`.
#'
#' @param store A `reactiveStore` with a `plot` branch containing:
#'   - `x_var` — character reactiveVal for the x-axis variable name
#'   - `y_var` — character reactiveVal for the y-axis variable name
#'   - `color_var` — character reactiveVal for the colour variable name
#' @param data A data.frame (used to derive variable choices if not provided).
#' @param plot_fn A 0-arg function that returns a ggplot object (or another
#'   plot-like object that `renderPlot` can capture).
#' @param num_vars Optional character vector of numeric variable names for
#'   the x/y selectors. If NULL, derived from `data`.
#' @param all_vars Optional character vector of all variable names (including
#'   `"(none)"`) for the colour selector. If NULL, derived from `data`.
#' @return A shiny tag tree (controls + plot + logout).
#' @export
mtcars_explorer <- function(store, data, plot_fn,
                             num_vars = NULL, all_vars = NULL) {
  if (is.null(num_vars)) {
    num_vars <- names(Filter(is.numeric, data))
  }
  if (is.null(all_vars)) {
    all_vars <- c("(none)", setdiff(names(data), "model"))
  }

  tagList(
    # Controls row — three selectors in a responsive grid
    tags$div(
      class = "grid grid-cols-1 md:grid-cols-3 gap-4 mb-8",
      card(
        select_input(
          label = "X-axis",
          value = reactiveProxy(
            get = store$plot$x_var,
            set = \(v) store$plot$x_var(v)
          ),
          choices = setNames(num_vars, num_vars)
        )
      ),
      card(
        select_input(
          label = "Y-axis",
          value = reactiveProxy(
            get = store$plot$y_var,
            set = \(v) store$plot$y_var(v)
          ),
          choices = setNames(num_vars, num_vars)
        )
      ),
      card(
        select_input(
          label = "Color by",
          value = reactiveProxy(
            get = store$plot$color_var,
            set = \(v) store$plot$color_var(v)
          ),
          choices = setNames(all_vars, all_vars)
        )
      )
    ),

    # Ggplot2 output — PlotOutput renders base/grid graphics.
    # print(ggplot) draws to the current device, which PlotOutput captures.
    card(
      class = "p-4",
      style = "min-height: 480px;",
      PlotOutput(\() print(plot_fn()))
    )
  )
}
