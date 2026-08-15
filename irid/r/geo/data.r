#' r/geo — Administrative-boundary metadata and GeoJSON from PostGIS
#'
#' The runtime data layer for the admin picker. Instead of reading bundled
#' JSON, it queries the `gadm` schema produced by `data-raw/generate_geo.R`:
#'
#'   - `load_geo()` returns the three per-level metadata tables (no geometry)
#'     used to populate the pickers and cascade parent/child selections.
#'   - `geo_dataobj_url()` registers a per-session Shiny data object backed by
#'     the parametrized `gadm.admin_geojson(level, countries)` SQL function,
#'     and returns the URL the map widget fetches GeoJSON from.
#'
#' Metadata is cached per process; sessions share it. Geometry never enters
#' the R process — PostGIS serializes it straight to GeoJSON for the browser.
#'
#' @md
#' @name geo
box::use(
  DBI[dbGetQuery, dbExecute],
  shiny[getDefaultReactiveDomain, parseQueryString, httpResponse],
  jsonlite[toJSON],
)

box::use(
  ../db[connect, disconnect],
)

.geo_cache <- new.env(parent = emptyenv())

`%||%` <- function(a, b) {
  if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
}

#' Load the three admin-level metadata tables
#'
#' Reads `gadm.countries`, `gadm.states`, and `gadm.counties` and returns
#' them as data.frames. Cached in `.geo_cache` after the first call.
#'
#' @return A list with `countries`, `states`, and `counties` data.frames.
#'   Common columns: `id`, `name`, `admin_level`, `engtype`. `states` has
#'   `country_id`; `counties` has `country_id` and `state_id`.
#' @export
load_geo <- function() {
  if (is.null(.geo_cache$data)) {
    con <- connect()
    on.exit(disconnect(con))

    countries <- dbGetQuery(
      con,
      "SELECT id, name, engtype, admin_level, country_id
       FROM gadm.countries
       ORDER BY name"
    )
    states <- dbGetQuery(
      con,
      "SELECT id, name, engtype, admin_level, country_id, state_id
       FROM gadm.states
       ORDER BY name"
    )
    counties <- dbGetQuery(
      con,
      "SELECT id, name, engtype, admin_level, country_id, state_id
       FROM gadm.counties
       ORDER BY name"
    )

    .geo_cache$data <- list(
      countries = countries,
      states    = states,
      counties  = counties
    )
  }
  .geo_cache$data
}

#' Build an id → name lookup for a metadata table
#'
#' @param meta A data.frame with `id` and `name` columns.
#' @return A named character vector (`id` = `name`).
#' @export
lookup_names <- function(meta) {
  stats::setNames(meta$name, meta$id)
}

#' Build an id → English type label lookup for a metadata table
#'
#' @param meta A data.frame with `id` and `engtype` columns.
#' @return A named character vector (`id` = `engtype`), with empty labels
#'   replaced by `NA_character_`.
#' @export
lookup_engtype <- function(meta) {
  eng <- meta$engtype
  eng[is.na(eng) | !nzchar(eng)] <- NA_character_
  stats::setNames(eng, meta$id)
}

#' Filter a child table to rows whose `country_id` is in `country_ids`
#'
#' @param meta A data.frame with a `country_id` column.
#' @param country_ids Character vector of selected country ids.
#' @return The filtered data.frame (row order preserved).
#' @export
filter_by_country <- function(meta, country_ids) {
  if (length(country_ids) == 0L) {
    return(meta[0, , drop = FALSE])
  }
  meta[meta$country_id %in% country_ids, , drop = FALSE]
}

#' Filter a child table to rows whose `state_id` is in `state_ids`
#'
#' @param meta A data.frame with a `state_id` column.
#' @param state_ids Character vector of selected state ids.
#' @return The filtered data.frame (row order preserved).
#' @export
filter_by_state <- function(meta, state_ids) {
  if (length(state_ids) == 0L) {
    return(meta[0, , drop = FALSE])
  }
  meta[meta$state_id %in% state_ids, , drop = FALSE]
}

#' Serve one GeoJSON FeatureCollection from `gadm.admin_geojson()`
#'
#' Shiny `registerDataObj` filter. `data` is unused (the handler opens its
#' own short-lived DB connection per request); `req` carries the query
#' string (`level=countries|states|counties`, optional `country=GID_0`).
#'
#' @param data Registered data object (ignored).
#' @param req Shiny request environment.
#' @return A Shiny `httpResponse` with `application/json` GeoJSON.
#' @keywords internal
geo_dataobj_handler <- function(data, req) {
  params <- parseQueryString(req$QUERY_STRING %||% "")
  level <- params$level %||% "countries"
  country <- params$country %||% ""

  lvl <- switch(
    level,
    countries = 0L,
    states    = 1L,
    counties  = 2L,
    stop("geo_dataobj_handler: unknown level ", level, call. = FALSE)
  )

  con <- connect()
  on.exit(disconnect(con))

  geojson <- dbGetQuery(
    con,
    "SELECT gadm.admin_geojson($1::integer, $2::text) AS geojson",
    params = list(lvl, country)
  )$geojson[[1L]]

  httpResponse(
    status       = 200L,
    content_type = "application/json",
    content      = as.character(geojson)
  )
}

#' Register (once per session) and return the GeoJSON data-object URL
#'
#' The URL is relative to the app root and is what the maplibre widget
#' fetches, appending `&level=…` and `&country=…` parameters.
#'
#' @return A character URL, or `NULL` when called outside a Shiny session.
#' @export
geo_dataobj_url <- function() {
  session <- getDefaultReactiveDomain()
  if (is.null(session)) return(NULL)

  key <- "irid_geo_dataobj_url"
  url <- session$userData[[key]]
  if (!is.null(url)) return(url)

  url <- session$registerDataObj("geo", NULL, geo_dataobj_handler)
  session$userData[[key]] <- url
  url
}

#' Serve picker metadata (id/name/engtype/parents) as JSON
#'
#' Shiny `registerDataObj` filter for the picker widgets. Reads the cached
#' `load_geo()` tables (no DB round-trip per request) and returns an array
#' of records for one admin level, optionally narrowed by parent ids:
#'
#'   `level=countries`
#'   `level=states&country=USA,CAN`
#'   `level=counties&country=USA`   or   `level=counties&state=USA.1_1`
#'
#' The picker widgets cache responses by URL, so each (level, parents)
#' combination is transferred once per session and then stays client-side.
#'
#' @param data Registered data object (ignored).
#' @param req Shiny request environment.
#' @return A Shiny `httpResponse` with `application/json` records.
#' @keywords internal
geo_meta_handler <- function(data, req) {
  params <- parseQueryString(req$QUERY_STRING %||% "")
  level   <- params$level %||% "countries"
  country <- params$country %||% ""
  state   <- params$state %||% ""

  geo <- load_geo()

  records <- switch(
    level,
    countries = geo$countries[c("id", "name", "engtype")],
    states    = geo$states[c("id", "name", "engtype", "country_id")],
    counties  = geo$counties[c("id", "name", "engtype", "country_id", "state_id")],
    stop("geo_meta_handler: unknown level ", level, call. = FALSE)
  )

  if (level %in% c("states", "counties") && nzchar(country)) {
    cids <- strsplit(country, ",", fixed = TRUE)[[1L]]
    records <- records[records$country_id %in% cids, , drop = FALSE]
  }
  if (identical(level, "counties") && nzchar(state)) {
    sids <- strsplit(state, ",", fixed = TRUE)[[1L]]
    records <- records[records$state_id %in% sids, , drop = FALSE]
  }

  records$engtype[is.na(records$engtype)] <- ""

  json <- toJSON(records, dataframe = "rows", auto_unbox = TRUE, na = "null")
  httpResponse(
    status       = 200L,
    content_type = "application/json",
    content      = as.character(json)
  )
}

#' Register (once per session) and return the picker-metadata data-object URL
#'
#' @return A character URL, or `NULL` when called outside a Shiny session.
#' @export
geo_meta_url <- function() {
  session <- getDefaultReactiveDomain()
  if (is.null(session)) return(NULL)

  key <- "irid_geo_meta_url"
  url <- session$userData[[key]]
  if (!is.null(url)) return(url)

  url <- session$registerDataObj("geo_meta", NULL, geo_meta_handler)
  session$userData[[key]] <- url
  url
}
