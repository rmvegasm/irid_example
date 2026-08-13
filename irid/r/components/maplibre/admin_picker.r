#' r/components/maplibre/admin_picker — Reusable admin-unit picker
#'
#' A multi-select "picker" component (a searchable dropdown with checkable
#' options). All three admin levels render the exact same component; the
#' behavioural differences (which units are offered, which selection is
#' mutated, which level becomes active on focus) are supplied by the caller
#' as plain callables and handlers.
#'
#' This is the "select input" of the design doc: a controlled multi-select
#' built on irid primitives rather than a native `<select multiple>`, so it
#' keeps the full reactive binding story (filtering via `Each`, open state
#' via `When`, controlled search input via `reactiveProxy`).
#'
#' @md
#' @name admin_picker
box::use(
  shiny[tags, tagList],
  irid[reactive, reactiveVal, reactiveProxy, When, Each],
)

# ── tiny inline icons ──────────────────────────────────────────────

.check_icon <- function() {
  tags$svg(
    class = "h-4 w-4 shrink-0 text-blue-600 dark:text-blue-400",
    viewBox = "0 0 20 20", fill = "currentColor", `aria-hidden` = "true",
    tags$path(
      d = paste0(
        "M10 18a8 8 0 100-16 8 8 0 000 16zm3.857-9.809a.75.75 0 ",
        "00-1.214-.882l-3.483 4.79-1.88-1.88a.75.75 0 10-1.06 1.061l",
        "2.5 2.5a.75.75 0 001.137-.089l4-5.5z"
      )
    )
  )
}

.empty_icon <- function() {
  tags$svg(
    class = "h-4 w-4 shrink-0 text-gray-400 dark:text-neutral-500",
    viewBox = "0 0 20 20", fill = "none", stroke = "currentColor",
    `stroke-width` = "1.5", `aria-hidden` = "true",
    tags$circle(cx = "10", cy = "10", r = "8")
  )
}

.chevron <- function() {
  tags$svg(
    class = "h-4 w-4 text-gray-400 dark:text-neutral-500",
    viewBox = "0 0 20 20", fill = "currentColor", `aria-hidden` = "true",
    tags$path(
      `fill-rule` = "evenodd", `clip-rule` = "evenodd",
      d = paste0(
        "M5.23 7.21a.75.75 0 011.06.02L10 11.168l3.71-3.938a.75.75 0 ",
        "111.08 1.04l-4.25 4.5a.75.75 0 01-1.08 0l-4.25-4.5a.75.75 0 ",
        "01.02-1.06z"
      )
    )
  )
}

# ── component ──────────────────────────────────────────────────────

#' Admin unit picker
#'
#' @param label Display label for the picker trigger.
#' @param choices A callable returning a list of records, each with `id`
#'   and `name` (the available units for this level).
#' @param selected A callable returning a character vector of selected ids.
#' @param active A callable returning a logical; when `TRUE` the trigger
#'   gets an accent ring.
#' @param on_focus A 0-arg function invoked when the picker gains focus
#'   (used to set the active admin level).
#' @param on_toggle A 1-arg function invoked with an id when the user
#'   toggles an option.
#' @param empty_text Text shown when `choices` has no matching entries.
#' @return A shiny tag tree.
#' @export
admin_picker <- function(
  label,
  choices,
  selected,
  active,
  on_focus,
  on_toggle,
  empty_text = "No units available"
) {
  open  <- reactiveVal(FALSE)
  query <- reactiveVal("")

  filtered <- reactive({
    opts <- choices()
    q <- tolower(trimws(query()))
    if (nzchar(q)) {
      nms <- vapply(opts, function(o) {
        n <- o$name
        if (is.null(n)) "" else tolower(n)
      }, character(1))
      opts <- opts[grepl(q, nms, fixed = TRUE)]
    }
    opts
  })

  trigger_class <- function(is_active) {
    paste(
      "relative z-30 w-full flex items-center justify-between gap-2 rounded-md border px-3 py-2 text-sm",
      "font-medium text-left transition-colors cursor-pointer",
      if (is_active) {
        paste(
          "border-blue-500 dark:border-blue-500 ring-2 ring-blue-500/30",
          "bg-blue-50/50 dark:bg-blue-900/20 text-gray-900 dark:text-neutral-100"
        )
      } else {
        paste(
          "border-gray-300 dark:border-neutral-600",
          "bg-white dark:bg-neutral-800 text-gray-700 dark:text-neutral-200",
          "hover:bg-gray-50 dark:hover:bg-neutral-700"
        )
      }
    )
  }

  tags$div(
    class = \() paste0("relative", if (isTRUE(open())) " z-50" else ""),
    tabindex = "-1",
    onBlur = \(e) {
      # Close on keyboard focus loss (Tab / Shift+Tab away). Mouse-driven
      # outside clicks are handled by the fixed overlay below.
      open(FALSE)
    },

    # Trigger button
    tags$button(
      type = "button",
      class = \() trigger_class(isTRUE(active())),
      onClick = \() {
        on_focus()
        open(!open())
      },
      onFocus = \() on_focus(),
      tags$span(class = "truncate", label),
      tags$span(
        class = "flex items-center gap-1.5 shrink-0",
        # Selection count badge
        When(
          \() length(selected()) > 0L,
          \() tags$span(
            class = paste(
              "inline-flex items-center justify-center min-w-[1.4rem] h-5 px-1.5",
              "rounded-full text-xs font-semibold",
              "bg-blue-100 dark:bg-blue-900/50 text-blue-700 dark:text-blue-300"
            ),
            \() length(selected())
          )
        ),
        .chevron()
      )
    ),

    # Dropdown
    When(
      \() open(),
      \() tagList(
        # Invisible full-screen layer behind the dropdown. Clicking anywhere
        # outside the picker hits it and closes the dropdown; the trigger and
        # dropdown sit at z-30, above it.
        tags$div(
          class = "fixed inset-0 z-20 cursor-default",
          onClick = \() open(FALSE)
        ),
        tags$div(
          class = paste(
            "absolute z-30 mt-1 w-full rounded-md border",
            "border-gray-200 dark:border-neutral-700 bg-white dark:bg-neutral-800",
            "shadow-lg overflow-hidden"
          ),

        # Search box
        tags$div(
          class = "p-2 border-b border-gray-200 dark:border-neutral-700",
          tags$input(
            type = "text",
            placeholder = "Search…",
            value = reactiveProxy(get = query, set = \(v) query(v)),
            class = paste(
              "block w-full rounded-md border border-gray-300 dark:border-neutral-600",
              "px-2.5 py-1.5 text-sm bg-white dark:bg-neutral-900",
              "text-gray-900 dark:text-neutral-100",
              "placeholder:text-gray-400 dark:placeholder:text-neutral-500",
              "focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500"
            )
          )
        ),

        # Options list
        tags$div(
          class = "max-h-60 overflow-y-auto py-1",
          When(
            \() length(filtered()) == 0L,
            \() tags$p(
              class = "px-3 py-2 text-sm text-gray-500 dark:text-neutral-400",
              empty_text
            ),
            otherwise = \() Each(
              filtered,
              by = \(o) o$id,
              \(item) {
                tags$button(
                  type = "button",
                  class = paste(
                    "w-full flex items-center gap-2 px-3 py-2 text-sm text-left",
                    "text-gray-700 dark:text-neutral-200",
                    "hover:bg-gray-50 dark:hover:bg-neutral-700 transition-colors cursor-pointer"
                  ),
                  onClick = \() on_toggle(item$id()),
                  When(
                    \() item$id() %in% selected(),
                    \() .check_icon(),
                    \() .empty_icon()
                  ),
                  # Name is immutable per item, so render it statically at
                  # build time rather than as a reactive text child.
                  tags$span(class = "truncate", item$name())
                )
              }
            )
          )
        )
      )
    )
  )
)
}
