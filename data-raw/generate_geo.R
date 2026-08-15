#!/usr/bin/env Rscript
# ─────────────────────────────────────────────────────────────────────
# generate_geo.R — load GADM 4.1 administrative boundaries into PostGIS
#
# Replaces the old "write GeoJSON files" generator. The runtime app now
# reads admin metadata and polygons from PostgreSQL/PostGIS instead of
# static files under irid/assets/geo/.
#
# What this script does (idempotent — safe to re-run):
#
#   1. Ensures the GADM 4.1 GeoPackage exists on disk, downloading and
#      unzipping it from geodata.ucdavis.edu when it does not.
#   2. Connects to PostgreSQL and creates the `postgis` extension and the
#      `gadm` schema when they are missing.
#   3. Imports the raw GADM layer into `gadm.raw` (only the columns the
#      app needs) via GDAL's ogr2ogr. Skipped when `gadm.raw` already has
#      rows.
#   4. Builds a dissolved `gadm.units` table with one row per
#      admin-0 / admin-1 / admin-2 unit. GADM stores only the *deepest*
#      subdivision per row, so a state whose polygons exist only as
#      county rows (or a county that only exists as commune rows) must be
#      reconstructed by unioning its descendants. This is the step that
#      restores the admin-1 ↔ admin-2 parent/child relationship.
#   5. Creates spatial/attribute indexes, three picker-metadata views, and
#      a parametrized `gadm.admin_geojson(level, countries)` function that
#      returns GeoJSON FeatureCollections for the map widget.
#
# The three app levels are always:
#
#   level 0 — country            (GID_0)
#   level 1 — first subdivision  (GID_1)
#   level 2 — second subdivision (GID_2)
#
# GADM 4.1 is strictly nested (no skipped levels in this release), so a
# country either ends at GID_1 (no counties) or at GID_2. Deeper levels
# (GID_3…GID_5) are collapsed into the GID_2 polygons.
#
# ENGTYPE_* (English type, e.g. "Province", "Census Division") is carried
# into `gadm.units.engtype` (falling back to the local TYPE_* label), so
# the app can show per-unit type badges and dynamic picker labels.
#
# Usage:
#   Rscript data-raw/generate_geo.R
#   Rscript data-raw/generate_geo.R --refresh-units   # rebuild units from raw
#   Rscript data-raw/generate_geo.R --drop-raw        # reclaim disk after build
#
# Connection settings come from the standard PG* environment variables.
# The port defaults to POSTGRES_HOST_PORT (the host-published port from
# .env), because this script runs on the host and reaches the DB through
# the compose port mapping; it falls back to PGPORT/5432 for manual runs.
# Credentials fall back to the POSTGRES_* names used in .env.
# ─────────────────────────────────────────────────────────────────────

suppressPackageStartupMessages({
  library(DBI)
  library(RPostgres)
})

# ── configuration ────────────────────────────────────────────────────

GADM_URL  <- "https://geodata.ucdavis.edu/gadm/gadm4.1/gadm_410-gpkg.zip"
GADM_DIR  <- "data-raw"
GADM_ZIP  <- file.path(GADM_DIR, "gadm_410-gpkg.zip")
GADM_GPKG <- file.path(GADM_DIR, "gadm_410.gpkg")

# Degree tolerance for ST_SimplifyPreserveTopology. 0.01° ≈ 1.1 km keeps
# the browser payloads reasonable (US counties drop from ~90 MB raw to
# ~5 MB) without visibly distorting the polygons.
SIMPLIFY_TOL <- 0.01

db_host <- Sys.getenv("PGHOST", "localhost")
db_port <- Sys.getenv("POSTGRES_HOST_PORT", Sys.getenv("PGPORT", "5432"))
db_user <- Sys.getenv("PGUSER", Sys.getenv("POSTGRES_USER", "postgres"))
db_pass <- Sys.getenv("PGPASSWORD", Sys.getenv("POSTGRES_PASSWORD", "postgres"))
db_name <- Sys.getenv("PGDATABASE", Sys.getenv("POSTGRES_DB", "irid_example"))

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || is.na(a[[1L]])) b else a

# ── helpers ─────────────────────────────────────────────────────────

curl_fetch <- function(url, dest) {
  status <- tryCatch(
    system2(
      "curl", c("-sL", "--fail", "--retry", "3", "--max-time", "600",
                "-o", shQuote(dest), shQuote(url)),
      stdout = FALSE, stderr = FALSE
    ),
    error = function(e) 1L
  )
  identical(status, 0L) && file.exists(dest) && file.info(dest)$size > 0
}

ensure_gpkg <- function() {
  if (file.exists(GADM_GPKG)) return(GADM_GPKG)

  if (!file.exists(GADM_ZIP)) {
    cat("downloading GADM 4.1 GeoPackage…\n")
    if (!curl_fetch(GADM_URL, GADM_ZIP)) {
      stop("download failed: ", GADM_URL)
    }
  }

  cat("unzipping GADM GeoPackage…\n")
  dir.create(GADM_DIR, recursive = TRUE, showWarnings = FALSE)
  status <- system2(
    "unzip", c("-o", shQuote(GADM_ZIP), "-d", shQuote(GADM_DIR)),
    stdout = FALSE, stderr = FALSE
  )
  if (!identical(status, 0L)) stop("unzip failed")

  found <- list.files(
    GADM_DIR, pattern = "^gadm_410\\.gpkg$",
    recursive = TRUE, full.names = TRUE
  )
  if (length(found) == 0L) stop("gadm_410.gpkg not found after unzip")
  found[[1L]]
}

db_connect <- function() {
  DBI::dbConnect(
    RPostgres::Postgres(),
    host     = db_host,
    port     = as.integer(db_port),
    user     = db_user,
    password = db_pass,
    dbname   = db_name
  )
}

relation_exists <- function(con, name) {
  out <- dbGetQuery(con, "SELECT to_regclass($1::text) AS rel", params = list(name))
  !is.na(out$rel[[1L]]) && nzchar(as.character(out$rel[[1L]]))
}

table_rows <- function(con, name) {
  out <- dbGetQuery(con, sprintf("SELECT COUNT(*) AS n FROM %s", name))
  as.numeric(out$n[[1L]])
}

# Import the raw GADM layer with only the columns the dissolved view needs.
# ogr2ogr is far faster and lighter than reading the 2.7 GB GeoPackage
# into R with sf, and it streams the geometry straight into PostGIS.
import_raw <- function(gpkg, con) {
  cat("importing GADM layer into gadm.raw (this can take a minute or two)…\n")

  conn_str <- sprintf(
    "PG:host=%s port=%s user=%s password=%s dbname=%s",
    db_host, db_port, db_user, db_pass, db_name
  )

  # `fid`/`uid` come from the GeoPackage; gid_0..2/name_0..2 feed the
  # dissolve; engtype_*/type_* drive the dynamic picker labels.
  sql <- paste(
    "SELECT fid, uid, gid_0, name_0,",
    "       gid_1, name_1, engtype_1, type_1,",
    "       gid_2, name_2, engtype_2, type_2,",
    "       geom",
    "FROM gadm_410"
  )

  args <- c(
    "-f", "PostgreSQL", shQuote(conn_str),
    shQuote(gpkg),
    "-nln", "gadm.raw",
    "-sql", shQuote(sql),
    "-nlt", "PROMOTE_TO_MULTI",
    "-lco", "GEOMETRY_NAME=geom",
    "-t_srs", "EPSG:4326"
  )

  res <- system2("ogr2ogr", args, stdout = TRUE, stderr = TRUE)
  status <- attr(res, "status") %||% 0L
  if (!identical(status, 0L)) {
    cat(paste(res, collapse = "\n"), "\n")
    stop("ogr2ogr import failed")
  }

  if (!relation_exists(con, "gadm.raw")) {
    stop("gadm.raw was not created")
  }
  cat("imported", table_rows(con, "gadm.raw"), "rows into gadm.raw\n")
}

# ── SQL DDL (idempotent, no DROP/TRUNCATE) ──────────────────────────

ddl_units <- sprintf("
CREATE TABLE gadm.units AS
WITH adm2 AS (
  SELECT
    gid_0,
    MAX(NULLIF(gid_1, '')) AS gid_1,
    gid_2,
    MIN(name_0) AS name_0,
    MAX(NULLIF(name_1, '')) AS name_1,
    MIN(name_2) AS name_2,
    MAX(NULLIF(engtype_1, '')) AS engtype_1,
    MAX(NULLIF(type_1, '')) AS type_1,
    MAX(NULLIF(engtype_2, '')) AS engtype_2,
    MAX(NULLIF(type_2, '')) AS type_2,
    ST_Multi(ST_Union(geom)) AS geom
  FROM gadm.raw
  WHERE gid_2 <> ''
  GROUP BY gid_0, gid_2
),
adm1 AS (
  SELECT
    gid_0,
    gid_1,
    MIN(name_0) AS name_0,
    MAX(NULLIF(name_1, '')) AS name_1,
    MAX(NULLIF(engtype_1, '')) AS engtype_1,
    MAX(NULLIF(type_1, '')) AS type_1,
    ST_Multi(ST_Union(geom)) AS geom
  FROM (
    SELECT gid_0, gid_1, name_0, name_1, engtype_1, type_1, geom FROM adm2
    UNION ALL
    SELECT gid_0, gid_1, name_0, name_1, engtype_1, type_1, geom
    FROM gadm.raw
    WHERE gid_1 <> '' AND gid_2 = ''
  ) t
  GROUP BY gid_0, gid_1
),
adm0 AS (
  SELECT
    gid_0,
    MIN(name_0) AS name_0,
    ST_Multi(ST_Union(geom)) AS geom
  FROM (
    SELECT gid_0, name_0, geom FROM adm1
    UNION ALL
    SELECT gid_0, name_0, geom FROM gadm.raw WHERE gid_1 = ''
  ) t
  GROUP BY gid_0
),
all_units AS (
  SELECT gid_0 AS id, name_0 AS name, NULL::text AS engtype,
         NULL::text AS type, 0::smallint AS admin_level,
         gid_0 AS country_id, NULL::text AS parent_id, geom
  FROM adm0
  UNION ALL
  SELECT gid_1 AS id, name_1 AS name, engtype_1 AS engtype,
         type_1 AS type, 1::smallint AS admin_level,
         gid_0 AS country_id, gid_0 AS parent_id, geom
  FROM adm1
  UNION ALL
  SELECT gid_2 AS id, name_2 AS name, engtype_2 AS engtype,
         type_2 AS type, 2::smallint AS admin_level,
         gid_0 AS country_id, gid_1 AS parent_id, geom
  FROM adm2
)
SELECT
  id, name, engtype, type, admin_level, country_id, parent_id,
  CASE
    WHEN ST_IsEmpty(simp) THEN geom
    ELSE ST_Multi(ST_CollectionExtract(simp, 3))
  END AS geom
FROM (
  SELECT u.*, ST_SimplifyPreserveTopology(u.geom, %s) AS simp
  FROM all_units u
) s
", SIMPLIFY_TOL)

ddl_indexes <- c(
  "CREATE UNIQUE INDEX IF NOT EXISTS gadm_units_level_id_idx ON gadm.units (admin_level, id)",
  "CREATE INDEX IF NOT EXISTS gadm_units_country_idx ON gadm.units (country_id)",
  "CREATE INDEX IF NOT EXISTS gadm_units_parent_idx ON gadm.units (parent_id)",
  "CREATE INDEX IF NOT EXISTS gadm_units_level_country_idx ON gadm.units (admin_level, country_id)",
  "CREATE INDEX IF NOT EXISTS gadm_units_level_parent_idx ON gadm.units (admin_level, parent_id)",
  "CREATE INDEX IF NOT EXISTS gadm_units_geom_idx ON gadm.units USING GIST (geom)"
)

ddl_views <- c(
  "CREATE OR REPLACE VIEW gadm.countries AS
   SELECT id, name, engtype, type, admin_level, country_id, parent_id
   FROM gadm.units WHERE admin_level = 0",
  "CREATE OR REPLACE VIEW gadm.states AS
   SELECT id, name, engtype, type, admin_level, country_id, id AS state_id
   FROM gadm.units WHERE admin_level = 1",
  "CREATE OR REPLACE VIEW gadm.counties AS
   SELECT id, name, engtype, type, admin_level, country_id, parent_id AS state_id
   FROM gadm.units WHERE admin_level = 2"
)

ddl_geojson_fn <- "
CREATE OR REPLACE FUNCTION gadm.admin_geojson(level integer, countries text)
RETURNS json
LANGUAGE sql
STABLE
AS $$
  SELECT json_build_object(
    'type', 'FeatureCollection',
    'features', COALESCE(
      json_agg(
        json_build_object(
          'type', 'Feature',
          'geometry', ST_AsGeoJSON(
            CASE
              -- Countries are an overview layer: a coarser simplification
              -- keeps the up-front fetch small (~1.5 MB instead of ~20 MB).
              WHEN admin_level = 0 THEN
                CASE WHEN ST_IsEmpty(ST_Simplify(geom, 0.05)) THEN geom
                     ELSE ST_Multi(ST_CollectionExtract(ST_Simplify(geom, 0.05), 3))
                END
              ELSE geom
            END
          )::json,
          'properties', json_build_object(
            'id', id,
            'name', name,
            'admin_level', admin_level,
            'country_id', country_id,
            'state_id', CASE
              WHEN admin_level = 1 THEN id
              WHEN admin_level = 2 THEN parent_id
              ELSE NULL
            END,
            'engtype', COALESCE(engtype, '')
          )
        )
      ),
      '[]'::json
    )
  )
  FROM gadm.units
  WHERE admin_level = level
    AND (countries IS NULL OR countries = '' OR country_id = ANY(string_to_array(countries, ',')))
$$;
"

# ── main ────────────────────────────────────────────────────────────

args <- commandArgs(trailingOnly = TRUE)
refresh_units <- "--refresh-units" %in% args
drop_raw <- "--drop-raw" %in% args

gpkg <- ensure_gpkg()
cat("using GeoPackage:", gpkg, "\n")

con <- db_connect()
on.exit(dbDisconnect(con), add = TRUE)

dbExecute(con, "CREATE EXTENSION IF NOT EXISTS postgis")
dbExecute(con, "CREATE SCHEMA IF NOT EXISTS gadm")

# raw is only needed to build/rebuild gadm.units; if units already exists
# and we are not rebuilding, skip the (large) import entirely.
need_raw <- !relation_exists(con, "gadm.units") || refresh_units

if (!relation_exists(con, "gadm.raw") || table_rows(con, "gadm.raw") == 0L) {
  if (need_raw) {
    import_raw(gpkg, con)
  } else {
    cat("gadm.raw absent but gadm.units exists; skipping import (use --refresh-units to rebuild)\n")
  }
} else {
  cat(sprintf(
    "gadm.raw already present (%d rows); skipping import\n",
    table_rows(con, "gadm.raw")
  ))
}

if (!relation_exists(con, "gadm.units")) {
  cat("building dissolved gadm.units table (this is the slow step)…\n")
  dbExecute(con, ddl_units)
} else if (refresh_units) {
  cat("rebuilding gadm.units from gadm.raw…\n")
  dbExecute(con, "DROP TABLE IF EXISTS gadm.units CASCADE")
  dbExecute(con, ddl_units)
} else {
  cat("gadm.units already present; skipping dissolve (use --refresh-units to rebuild)\n")
}

cat("creating indexes…\n")
for (sql in ddl_indexes) dbExecute(con, sql)

cat("creating metadata views…\n")
for (sql in ddl_views) dbExecute(con, sql)

cat("creating gadm.admin_geojson()…\n")
dbExecute(con, ddl_geojson_fn)

if (drop_raw) {
  if (relation_exists(con, "gadm.raw")) {
    cat("dropping gadm.raw to reclaim disk…\n")
    dbExecute(con, "DROP TABLE gadm.raw")
  } else {
    cat("gadm.raw already absent\n")
  }
}

cat(sprintf(
  "done: %d units across %d countries\n",
  table_rows(con, "gadm.units"),
  table_rows(con, "gadm.countries")
))
