# irid Example — Shiny App with irid, PostgreSQL, and Caddy

A minimal Docker Compose project running an irid Shiny app with
PostgreSQL-backed authentication behind a Caddy reverse proxy.

The app itself is a **MapLibre GL administrative-unit explorer**: after
signing in you can pick countries, states/provinces, and counties from
three linked multi-select pickers while a live map shows the selected
polygons (clicking them removes/toggles selection). It showcases a
custom `IridWidget` wrapping MapLibre GL, a dedicated `reactiveStore`
for the picker state, and three instances of one reusable picker
component. See [Code organization & component
modules](docs/architecture.md) and [Custom widgets: the MapLibre GL admin
map](docs/maplibre-widget.md) for the walkthrough.

## Architecture

```
Browser ──▶ Caddy:80 ──▶ irid:3839 ──▶ PostgreSQL
```

## Project Structure

```
├── compose.yml                  # Root: name + include stanzas
├── .env                         # Single env file for all services
│
├── db/compose.yml               # PostgreSQL
├── irid/compose.yml             # irid Shiny app
│   ├── Dockerfile               #   Multi-stage: CSS build + R runtime
│   ├── app.r                    #   App entry point
│   ├── config.yml               #   App configuration
│   ├── r/                       #   R box modules (geo/, server/, components/)
│   └── assets/                  #   css/, js/ (MapLibre widget)
├── data-raw/generate_geo.R      # Loads GADM 4.1 boundaries into PostGIS
├── caddy/compose.yml            # Reverse proxy
│   └── Caddyfile
│
├── pginit/                      # DB init scripts (users table + demo seed)
└── pgdata/                      # PostgreSQL data volume
```

### Administrative-boundary data

The admin polygons live in PostgreSQL/PostGIS. `data-raw/generate_geo.R`
loads the GADM 4.1 GeoPackage into the `gadm` schema: it imports the leaf
rows, dissolves them into a `gadm.units` table with one polygon per
admin-0/1/2 unit (GADM stores only the deepest subdivision per row), and
exposes picker metadata through views plus GeoJSON through the parametrized
`gadm.admin_geojson(level, countries)` function.

Two per-session Shiny data objects serve the browser without pushing
data through the irid wire channel: `admin_geojson` GeoJSON for the map
(lazy-loaded per selected country) and picker metadata
(`r/geo$geo_meta_url`, cached client-side per level/parents). R only loads
the lightweight metadata views for labels, selected-unit chips, and
parent/child cascade cleanup.

The heavy geospatial stack (GDAL/sf) is dev-only, not an app dependency.
Run `Rscript data-raw/generate_geo.R` to load or refresh the data
(`--refresh-units` rebuilds the dissolved table from the raw import;
`--drop-raw` drops the ~2.4 GB raw import afterward to reclaim disk).

## Getting Started

```bash
# 1. Copy environment template
cp .env.example .env

# 2. Build and start the database + load GADM data
docker compose up -d db

#    Load .env into the shell so host-side tools (generate_geo.R) see
#    config such as POSTGRES_HOST_PORT and the POSTGRES_* credentials.
set -a; . ./.env; set +a
Rscript data-raw/generate_geo.R

# 3. Build and start the rest of the stack
docker compose build
docker compose up -d

# 4. Visit in browser
open http://localhost:8080
```

Demo credentials: username `demo`, password `demo123`.

## R Package Management

R packages are pinned via `renv.lock`. The irid Dockerfile restores them
at build time. There is no separate `r-lib` image — all R dependencies
live in the irid image.

To add or update packages:

```bash
R -e 'renv::install("newpkg"); renv::snapshot()'
docker compose build irid
```

## Tailwind CSS

The irid Dockerfile compiles Tailwind CSS v4 in a build stage by scanning
R source files for utility classes. For local development without Docker:

```bash
bash irid/assets/css/build.sh          # one-shot
bash irid/assets/css/build.sh --watch  # watch mode
```
