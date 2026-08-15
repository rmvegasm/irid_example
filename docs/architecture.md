<!-- agents: code organization, box module layout, component hierarchy, and reactive stores -->

# Code organization & component modules

This page is a map of the irid example app for two audiences:

- R/Shiny developers meeting irid for the first time, who want to see a
  real project organized around components instead of a `ui`/`server`
  split.
- Agents working in this repository, who need to know where things live
  and which parts are still wired in.

For the irid concepts themselves (`reactiveVal`, `reactiveStore`,
`reactiveProxy`, `When`, `Each`, `IridWidget`), see the irid website and
the [MapLibre widget walkthrough](maplibre-widget.md).

## Mental model

An irid app has no `ui` and `server` functions. A component is an ordinary
R function that returns Shiny tags and closes over its own reactive state:

```r
Counter <- function() {
  n <- reactiveVal(0L)
  tags$div(
    tags$button("+1", onClick = \() n(n() + 1L)),
    \() paste("Count:", n())
  )
}
iridApp(Counter)
```

When a reactive value changes, irid updates only the DOM nodes bound to it
---it does not re-render the component or call an `update*Input` helper.
State and markup live together in the same function.

The app entry point (`irid/app.r`) is a factory that builds this component
tree once per session. There is no separate `server` function; the top-level
`iridApp(AdminPickerApp)` launches the factory.

## Repository layout

```
irid_example/
├── compose.yml                  # root: name + include stanzas
├── .env                         # single env file for all services
├── docs/                        # this documentation
├── data-raw/generate_geo.R      # loads GADM 4.1 boundaries into PostGIS
├── db/                          # PostgreSQL service + init scripts
├── caddy/                       # reverse proxy
├── pginit/                      # DB schema + demo seed
└── irid/                        # the Shiny app
    ├── app.r                    # entry point: stores, wiring, iridApp()
    ├── config.yml               # config::get() settings
    ├── Dockerfile               # 3-stage build (CSS, renv, runtime)
    ├── compose.yml              # irid service definition
    ├── renv.lock / .Rprofile    # pinned R packages
    ├── assets/
    │   ├── css/                 # Tailwind source + build script
    │   └── js/                  # widget factories (dark-mode, maplibre)
    └── r/
        ├── components/
        │   ├── elements/        # atoms (alert, badge, buttons, inputs)
        │   ├── containers/      # card
        │   ├── forms/           # login_form
        │   ├── tables/          # data_table (legacy, unused)
        │   ├── layouts/         # app_shell
        │   ├── pages/           # login_page, admin_picker_page
        │   └── maplibre/        # MaplibreAdmin widget, admin_picker
        ├── db/                  # connect, users
        ├── geo/                 # metadata loader + helpers
        ├── server/              # login/logout handlers
        └── plot/                # ggplot2 builder (legacy, unused)
```

## Box modules and the reexport layer

R code is organized with the
[box](https://klmr.me/box/) module system. Every directory under `irid/r/`
has an `__init__.r` file that reexports the public functions of its
submodules. Callers import one name and get the whole module:

```r
box::use(
  r/components/pages[login_page, admin_picker_page],
  r/geo[load_geo],
)
```

The `__init__.r` file is the public interface. The split inside a module is
an implementation detail. For example, `r/db/__init__.r` reexports
`connect`/`disconnect` from `connect.r` and the user helpers from `users.r`;
callers only ever `box::use(r/db)` and use `db$get_user(...)`.

Conventions (see `docs/_coding_conventions.md`):

- Explicit imports, never `box::use(pkg)` + `pkg$fn()` access.
- Packages first, local modules second, each in its own `box::use()` call.
- Alphabetical order within each group.

## Component hierarchy

Components are layered by how much they import. Leaf-level components know
nothing about each other; higher layers compose lower ones.

- `elements/` --- atoms (alert, badge, buttons, inputs). Import nothing
  from other component submodules.
- `containers/` --- wrappers that take arbitrary children (card). Also
  import nothing from other component submodules.
- `forms/` and `tables/` --- intermediate units built from `elements/` and
  `containers/` (`login_form`, `data_table`).
- `layouts/` --- top-level chrome rendered once, with page content in the
  `...` slot (`app_shell`).
- `pages/` --- complete, drop-in pages (`login_page`, `admin_picker_page`).

Two module groups sit beside the components rather than in the hierarchy:

- `maplibre/` --- domain-specific pieces for the admin picker: the
  `MaplibreAdmin` widget and the reusable `admin_picker` component.
- `geo/` --- data layer: `load_geo()` plus `lookup_names()`,
  `filter_by_country()`, `filter_by_state()`, and the per-session GeoJSON
  endpoint registration (`geo_dataobj_url()`).

`server/` holds handlers that need a Shiny server context (login/logout),
and `db/` wraps PostgreSQL. Both are decoupled from any single app by
taking a `reactiveStore` as an argument rather than closing over app state.

## Reactive stores

Two `reactiveStore` objects hold all mutable application state, created at
the top of `AdminPickerApp()` in `app.r`. A store turns a nested list into
a tree of `reactiveVal`s; each leaf is read by calling it and written by
calling it with a value.

- `state` --- authentication and UI chrome:

  - `auth$logged_in`, `auth$user_name`, `auth$user_id`, `auth$auth_error`
  - `login_form$username`, `login_form$password`
  - `dark_mode`

- `geo` --- the admin-picker state, deliberately separate from the auth
  store:

  - `active_level` --- one of `"country"`, `"state"`, `"county"`
  - `selection$country`, `selection$state`, `selection$county` ---
    character vectors of selected ids

Keeping the two stores separate means the picker state never gets tangled
with authentication, and each store can be passed to exactly the components
that need it.

## How app.r wires it together

`app.r` is intentionally thin. It:

1. Creates the two stores.
2. Loads the geo metadata once (`load_geo()` caches per process).
3. Builds handler closures from the auth store (`handle_login`,
   `handle_logout`).
4. Registers `addResourcePath` for `css/` and `js/` assets (GeoJSON is
   served dynamically from PostGIS, not from a static path).
5. Returns `app_shell(...)` containing a hidden `dark-mode-detector`
   widget and a top-level `When()` that swaps between `login_page` and
   `admin_picker_page` based on `state$auth$logged_in()`.

All markup lives in the components; `app.r` only composes them. Styles are
Tailwind utility classes declared inside the components and compiled by the
Docker build (or `irid/assets/css/build.sh` locally).

## The geo data pipeline

Administrative polygons live in PostgreSQL/PostGIS, not in static files or
`sf` objects in R:

- `data-raw/generate_geo.R` downloads (when needed) the GADM 4.1
  GeoPackage, imports its leaf rows into `gadm.raw` via `ogr2ogr`, and
  dissolves them into a `gadm.units` table with one row per admin-0 /
  admin-1 / admin-2 unit. GADM stores only the deepest subdivision per
  row, so a state (or county) that has children must be reconstructed by
  unioning its descendants. (`--drop-raw` drops the ~2.4 GB raw import
  after a successful build to reclaim disk; the dissolve can always be
  rebuilt from the GeoPackage.)
- The table keeps `id`, `name`, `admin_level` (0/1/2), `country_id`,
  `parent_id`, `engtype` (GADM's `ENGTYPE_*`, falling back to `TYPE_*`),
  and `geom`, with a GIST index plus btree indexes on the id/foreign-key
  columns (including `(admin_level, country_id)` and
  `(admin_level, parent_id)` for child lookups).
- `gadm.admin_geojson(level, countries)` is the parametrized GeoJSON
  function: it returns a FeatureCollection built with `ST_AsGeoJSON`, and
  three thin views (`gadm.countries`, `gadm.states`, `gadm.counties`)
  expose picker metadata.
- Parent linkage is the point of the redesign: counties carry a real
  `state_id` (`parent_id` = their `GID_1`), so county selection cascades
  by state, not only by country.
- Two per-session Shiny data objects serve the browser directly: the map
  widget fetches GeoJSON from `gadm.admin_geojson()` (lazy-loaded per
  selected country), and the picker widgets fetch unit metadata from
  `r/geo$geo_meta_url` (cached client-side per level/parents). R itself
  only loads the metadata views for labels, selected-unit chips, and
  cascade cleanup — geometry and option lists never travel through the
  Shiny/irid wire channel.

This keeps the heavy geospatial stack (`sf`, GDAL, `ogr2ogr`) confined
 to the dev-time generator, not the app runtime. Re-run the script after
the GeoPackage changes, and pass `--refresh-units` to rebuild the dissolved
table from `gadm.raw`.

## Legacy modules (mtcars explorer)

The admin-picker page replaced the original mtcars scatter-plot explorer.
These modules remain in the tree but are no longer imported by `app.r`:

- `r/components/pages/mtcars.r` (`mtcars_explorer`)
- `r/plot/` (`build_plot`)
- `r/components/tables/data_table.r`

They are still reexported from their `__init__.r` files. They can be
deleted during cleanup; nothing else references them.

## Where to look next

- [Custom widgets: the MapLibre GL admin map](maplibre-widget.md) --- how
  the `IridWidget` bridge wraps MapLibre GL and how props/events flow.
- `docs/_coding_conventions.md` --- R and JavaScript style rules.
- `docs/_web_docs.md` --- links to irid, box, MapLibre, and Tailwind docs.
