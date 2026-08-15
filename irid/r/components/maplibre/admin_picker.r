#' r/components/maplibre/admin_picker — Reusable admin-unit picker
#'
#' A multi-select "picker" (a searchable combobox with checkable options).
#' All three admin levels render the same widget; the behavioural
#' differences (which units are offered, which selection is mutated, which
#' level becomes active on focus) are supplied by the caller as callables.
#'
#' Rendering happens entirely client-side (`assets/js/admin-picker.js`):
#' option metadata is fetched once per (level, parents) from the per-session
#' `geo_meta` data object and cached, so picker interactions never round-trip
#' through R. The JS widget also owns keyboard navigation (↑/↓, Enter,
#' Escape, Tab), closes on pointer-leave instead of focus loss, and lists
#' already-selected units first so deselecting is easy.
#'
#' @md
#' @name admin_picker
box::use(
  shiny[tags],
  htmltools[htmlDependency],
  irid[IridWidget],
)

admin_picker_deps <- function() {
  htmlDependency(
    name    = "admin-picker",
    version = "1.0.0",
    src     = c(href = "js"),
    script  = "admin-picker.js"
  )
}

#' Admin unit picker
#'
#' @param label Display label for the picker trigger. May be a string or a
#'   callable returning a string (for dynamic per-country type labels).
#' @param selected A callable returning a character vector of selected ids.
#' @param active A callable returning a logical; when `TRUE` the trigger
#'   gets an accent ring.
#' @param level One of `"countries"`, `"states"`, `"counties"` — which
#'   metadata bucket the widget reads.
#' @param filter_field Parent column used to narrow the options: `""` for
#'   countries, `"country_id"` for states, and `"state_id"`/`"country_id"`
#'   for counties. May be a string or a callable.
#' @param filter_ids A callable returning a character vector of parent ids
#'   to narrow the options by.
#' @param meta_url A callable returning the per-session metadata data-object
#'   URL (see `r/geo$geo_meta_url`).
#' @param on_focus A 0-arg function invoked when the picker is opened/focused
#'   (used to set the active admin level).
#' @param on_toggle A 1-arg function invoked with an id when the user toggles
#'   an option.
#' @param empty_text Text shown when there are no matching entries.
#' @return An `irid_widget` construct.
#' @export
admin_picker <- function(
  label,
  selected,
  active,
  level,
  filter_field,
  filter_ids,
  meta_url,
  on_focus,
  on_toggle,
  empty_text = "No units available"
) {
  IridWidget(
    name = "admin-picker",
    props = list(
      label       = label,
      selected    = selected,
      active      = active,
      level       = level,
      filterField = filter_field,
      filterIds   = filter_ids,
      metaUrl     = meta_url,
      emptyText   = empty_text
    ),
    events = list(
      `picker-focus`  = \(e) on_focus(),
      `picker-toggle` = \(e) on_toggle(e$id)
    ),
    deps = admin_picker_deps(),
    container = tags$div(class = "relative")
  )
}
