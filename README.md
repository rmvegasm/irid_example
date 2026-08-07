# irid Example — Shiny App with irid, PostgreSQL, and Caddy

A minimal Docker Compose project running an irid Shiny app with
PostgreSQL-backed authentication behind a Caddy reverse proxy.

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
│   ├── r/                       #   R box modules (logic/ + view/)
│   └── assets/css/              #   Tailwind CSS (input.css + compiled app.css)
├── caddy/compose.yml            # Reverse proxy
│   └── Caddyfile
│
├── pginit/                      # DB init scripts (users table + demo seed)
└── pgdata/                      # PostgreSQL data volume
```

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
