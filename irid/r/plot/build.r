#' r/plot/build — ggplot2 plot builder implementation
#'
#' Factory that returns a zero-arg function producing a ggplot from
#' reactive store state. Decouples plot construction from the app body
#' so it is testable and reusable.
#'
#' @md
#' @name plot
box::use(
  ggplot2[...],
)

#' Build a scatter-plot function from store state
#'
#' Returns a 0-arg function that, when called, reads the current x/y/color
#' variables from `store$plot` and constructs a `ggplot` scatter plot.
#'
#' @param store A `reactiveStore` with a `plot` branch containing
#'   `x_var`, `y_var`, and `color_var` (all character reactiveVals).
#' @param data A data.frame containing the data to plot.
#' @param dark_mode A 0-arg callable (reactiveVal) returning a logical
#'   indicating whether the OS is in dark mode. Drives the plot's
#'   foreground colours via `theme()`.
#' @return A 0-arg function that returns a `ggplot` object.
#' @export
build_plot <- function(store, data, dark_mode) {
  force(store)
  force(data)
  force(dark_mode)
  \() {
    # ── Colour palette: match the page's Tailwind tokens ───────
    # Text:  text-gray-900 (light) / text-neutral-100 (dark)
    # Page:  bg-gray-50 (light)     / bg-neutral-900 (dark)
    fg <- if (isTRUE(dark_mode())) "#f5f5f5" else "#111827"
    bg <- if (isTRUE(dark_mode())) "#171717" else "#f9fafb"

    p <- ggplot(data, aes(
      x = .data[[store$plot$x_var()]],
      y = .data[[store$plot$y_var()]]
    ))

    if (store$plot$color_var() != "(none)") {
      p <- p + aes(color = .data[[store$plot$color_var()]])
    }

    p <- p +
      geom_point(size = 3, alpha = 0.7) +
      # theme_minimal(paper, ink) correctly colours text, title, axis
      # labels, and all rectangles.  But it uses col_mix(ink, paper, X)
      # for grid lines and axis ticks — a formula that assumes ink is
      # *darker* than paper.  In dark mode that invert gives nearly-
      # invisible grid lines.  So we set paper/ink for the simple
      # elements, then explicitly override the col_mix-based ones.
      theme_minimal(
        base_size = 14,
        paper = bg,
        ink   = fg
      ) +
      theme(
        # Grid lines — override the col_mix(ink, paper, 0.92) from
        # theme_bw() with a semi-transparent foreground that works
        # the same in both light and dark modes.
        panel.grid.major = element_line(
          colour = alpha(fg, 0.15),
          linewidth = 0.5
        ),
        # Minor grid: theme_minimal() blanks it; bring it back.
        panel.grid.minor = element_line(
          colour = alpha(fg, 0.08),
          linewidth = 0.25
        ),
        # Axis tick labels: theme_grey() sets colour via
        # col_mix(ink, paper, 0.302).  Override with pure fg.
        axis.text = element_text(colour = fg),
        # Tick marks: theme_minimal() blanks them.  Restore with a
        # muted fg so they are visible but not distracting.
        axis.ticks = element_line(colour = alpha(fg, 0.4)),
        # Strip background (facets): use a subtle fg tint rather
        # than the col_mix-based default.
        strip.background = element_rect(
          fill = alpha(fg, 0.08),
          colour = alpha(fg, 0.15)
        )
      ) +
      labs(
        title = paste(store$plot$y_var(), "vs", store$plot$x_var()),
        x = store$plot$x_var(),
        y = store$plot$y_var()
      )

    if (store$plot$color_var() != "(none)") {
      p <- p + labs(color = store$plot$color_var())
    }

    p
  }
}
