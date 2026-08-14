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
│   └── assets/                  #   css/, js/ (MapLibre widget), geo/ (GeoJSON)
├── data-raw/generate_geo.R      # Regenerates the bundled geo assets
├── caddy/compose.yml            # Reverse proxy
│   └── Caddyfile
│
├── pginit/                      # DB init scripts (users table + demo seed)
└── pgdata/                      # PostgreSQL data volume
```

### Administrative-boundary data

The admin polygons ship as static GeoJSON under `irid/assets/geo/` and
are served at `/geo/*.geojson`. Countries are one small file fetched up
front; states and counties are split per country (`/geo/states/{id}.geojson`,
`/geo/counties/{id}.geojson`) so the MapLibre widget lazy-loads only the
polygons for the countries the user selects. R only loads the lightweight
`*_meta.json` tables for the pickers. Re-run `Rscript data-raw/generate_geo.R`
to regenerate (the script uses `rnaturalearth` for admin 0/1 and geoBoundaries
for admin 2 — the heavy geospatial stack is dev-only, not an app dependency).

## Getting Started

```bash
# 1. Copy environment template
cp .env.example .env

# 2. Build and start
docker compose build
docker compose up -d

# 3. Visit in browser
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
