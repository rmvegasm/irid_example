#' r/geo — Administrative-boundary metadata (data prep + loading)
#'
#' The runtime half of the geo pipeline. `data-raw/generate_geo.R`
#' produces the assets; `load_geo()` exposes their lightweight metadata
#' to the app. Geometry is fetched browser-side by the maplibre widget.
#'
#' @md
#' @name geo
#' @export
box::use(
  ./data[filter_by_country, load_geo, lookup_names],
)
