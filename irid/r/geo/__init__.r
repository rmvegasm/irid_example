#' r/geo — Administrative-boundary metadata (PostGIS data layer)
#'
#' The runtime half of the geo pipeline. `data-raw/generate_geo.R` loads the
#' GADM 4.1 boundaries into PostGIS; this module exposes the lightweight
#' metadata tables to the pickers and registers the per-session GeoJSON
#' endpoint the maplibre widget fetches. Geometry stays out of the R
#' process — PostGIS serializes it straight to GeoJSON.
#'
#' @md
#' @name geo
#' @export
box::use(
  ./data[
    filter_by_country, filter_by_state, geo_dataobj_url, geo_meta_url,
    load_geo, lookup_engtype, lookup_names
  ],
)
