#' r/components/maplibre/admin_map — MapLibre GL admin map widget
#'
#' A thin `IridWidget` wrapper around MapLibre GL JS. The JS factory
#' (`assets/js/maplibre-admin.js`) owns the map lifecycle and reports
#' clicks on the active admin level through the `feature-click` event;
#' every piece of map state (which polygons are selected, which level is
#' interactive, light/dark basemap) flows in as two-way-capable props
#' bound to the reactive store.
#'
#' Geometry is *not* shipped through the widget channel: the GeoJSON assets
#' are served under `/geo/` (see `addResourcePath` in app.r) and fetched by
#' the factory directly. Countries ship as one small file; states and
#' counties ship as per-country files so the factory can lazy-load only the
#' polygons the user selects. Only the compact selection ids round-trip
#' through irid.
#'
#' @md
#' @name admin_map
box::use(
  shiny[tags],
  htmltools[htmlDependency],
  irid[IridWidget],
)

#' MapLibre GL + widget factory dependencies
#'
#' @return A list of two html_dependency objects: the MapLibre GL library
#'   (CSS + JS from unpkg) and the irid widget factory script served from
#'   the app's `js/` resource path.
#' @keywords internal
maplibre_deps <- function() {
  list(
    htmltools::htmlDependency(
      name       = "maplibre-gl",
      version    = "5.2.0",
      src        = c(href = "https://unpkg.com/maplibre-gl@5.2.0/dist"),
      script     = "maplibre-gl.js",
      stylesheet = "maplibre-gl.css"
    ),
    htmltools::htmlDependency(
      name    = "maplibre-admin",
      version = "1.0.0",
      src     = c(href = "js"),
      script  = "maplibre-admin.js"
    )
  )
}

#' Admin map widget
#'
#' @param selected_countries Callable returning a character vector of
#'   selected admin-0 ids.
#' @param selected_states Callable returning a character vector of selected
#'   admin-1 ids.
#' @param selected_counties Callable returning a character vector of selected
#'   admin-2 ids.
#' @param active_level Callable returning one of "country", "state", "county".
#' @param dark_mode Callable returning a logical; drives the basemap style.
#' @param on_feature_click Function called with the `feature-click` payload
#'   (`list(id = …, adminLevel = …)`).
#' @return An `irid_widget` construct.
#' @export
MaplibreAdmin <- function(
  selected_countries,
  selected_states,
  selected_counties,
  active_level,
  dark_mode,
  on_feature_click = NULL
) {
  IridWidget(
    name = "maplibre-admin",
    props = list(
      selectedCountries = selected_countries,
      selectedStates    = selected_states,
      selectedCounties  = selected_counties,
      activeLevel       = active_level,
      darkMode          = dark_mode
    ),
    events = list(
      `feature-click` = on_feature_click
    ),
    deps = maplibre_deps(),
    container = tags$div(
      class = "absolute inset-0 w-full h-full"
    )
  )
}
