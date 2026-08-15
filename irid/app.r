#!/usr/bin/env Rscript
# ─────────────────────────────────────────────────────────────────────
# app.r — irid Shiny app: MapLibre administrative-unit explorer
#
# This file is intentionally minimal. It:
#   1. Creates the authentication reactiveStore
#   2. Creates a separate `geo` reactiveStore for admin-picker state
#   3. Loads the bundled geo metadata (r/geo)
#   4. Wires handlers and components together
#   5. Launches via iridApp()
#
# All UI components live in r/components/ submodules.
# Server-side handlers live in r/server/.
# Geo data loading lives in r/geo/.
# All styles are contained within the imported components.
#
# Box module layout (box path defaults to app working dir):
#   box::use(r/server)                 — login/logout handlers
#   box::use(r/geo)                    — administrative metadata loader
#   box::use(r/components/layouts)     — app shell layout
#   box::use(r/components/pages)       — full page components
#
# Tailwind CSS: compiled via @tailwindcss/cli, served at /css/app.css.
# ─────────────────────────────────────────────────────────────────────

box::use(
  irid[iridApp, When, reactiveStore, IridWidget],
  shiny[addResourcePath, tags],
  htmltools[htmlDependency],
)

box::use(
  r/server[handle_login, handle_logout],
  r/geo[load_geo],
  r/components/layouts[app_shell],
  r/components/pages[login_page, admin_picker_page],
)

# ── Static assets ───────────────────────────────────────────────
# Serve CSS and JS from irid/assets/ — same layout as the host
# project tree. Shiny's default www/ directory is not used. GeoJSON is
# served dynamically from PostGIS via r/geo, not from a static path.
#
# In Docker:     /app/irid/assets/   (copied at build time)
# Local dev:     ./assets/           (relative to irid/)
addResourcePath("css", "assets/css")
addResourcePath("js", "assets/js")

# ── App configuration (reads env vars via config.yml) ───────────
cfg <- config::get()

# ── App definition (factory function — called once per session) ─
AdminPickerApp <- function() {
  # ── Authentication store ────────────────────────────────────────
  state <- reactiveStore(list(
    auth = list(
      logged_in = FALSE,
      user_name = "",
      user_id = NULL,
      auth_error = ""
    ),
    login_form = list(
      username = "",
      password = ""
    ),
    dark_mode = FALSE
  ))

  # ── Admin-picker store (separate from auth) ────────────────────
  geo <- reactiveStore(list(
    active_level = "country",
    selection = list(
      country = character(),
      state   = character(),
      county  = character()
    )
  ))

  # ── Static geo metadata (shared across sessions via r/geo cache)
  data <- load_geo()

  # ── Handlers (factories that close over the store) ────────────
  on_login  <- handle_login(state)
  on_logout <- handle_logout(state)

  # ── Dark-mode dependency (JS widget source) ───────────────────
  dark_mode_dep <- htmlDependency(
    name    = "dark-mode",
    version = "1.0.0",
    src     = c(href = "js"),
    script  = "dark-mode.js"
  )

  # ── Assemble ──────────────────────────────────────────────────
  app_shell(
    title = "Administrative Explorer",
    fluid = TRUE,
    user = \() {
      if (state$auth$logged_in()) list(username = state$auth$user_name())
      else NULL
    },
    on_logout = on_logout,

    # Hidden widget: bridges prefers-color-scheme into the reactive
    # store via irid's native wire protocol.
    IridWidget(
      name = "dark-mode-detector",
      events = list(
        `scheme-change` = \(e) state$dark_mode(isTRUE(e$dark))
      ),
      deps = dark_mode_dep,
      container = tags$span(style = "display: none;")
    ),

    When(
      \() state$auth$logged_in(),
      \() admin_picker_page(
        geo       = geo,
        data      = data,
        dark_mode = state$dark_mode
      ),
      otherwise = \() login_page(
        store = state,
        on_login = on_login,
        title = "Administrative Explorer"
      )
    )
  )
}

# ── Launch ──────────────────────────────────────────────────────
iridApp(AdminPickerApp)
