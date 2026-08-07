#!/usr/bin/env Rscript
# ─────────────────────────────────────────────────────────────────────
# app.r — irid Shiny app: mtcars ggplot2 explorer
#
# This file is intentionally minimal. It:
#   1. Creates a reactiveStore for all app state
#   2. Defines the mtcars dataset
#   3. Wires handlers and components together
#   4. Launches via iridApp()
#
# All UI components live in r/components/ submodules.
# Server-side handlers live in r/server/.
# Reusable logic lives at the r/ top level (r/plot/).
# All styles are contained within the imported components.
#
# Box module layout (box path defaults to app working dir):
#   box::use(r/server)                 — login/logout handlers
#   box::use(r/plot)                   — ggplot2 plot builder
#   box::use(r/components/layouts)     — app shell layout
#   box::use(r/components/pages)       — full page components
#   box::use(r/db)                     — database (re-exported via handlers)
#
# Tailwind CSS: compiled via @tailwindcss/cli, served at /css/app.css.
# ─────────────────────────────────────────────────────────────────────

box::use(
  irid[iridApp, When, reactiveStore, IridWidget],
  shiny[addResourcePath, tags],
  htmltools[htmlDependency],
  ggplot2[...],
)

box::use(
  r/server[handle_login, handle_logout],
  r/plot[build_plot],
  r/components/layouts[app_shell],
  r/components/pages[login_page, mtcars_explorer],
)

# ── Static assets ───────────────────────────────────────────────
# Serve CSS and JS from irid/assets/ — same layout as the host
# project tree. Shiny's default www/ directory is not used.
#
# In Docker:     /app/irid/assets/   (copied at build time)
# Local dev:     ./assets/           (relative to irid/)
addResourcePath("css", "assets/css")
addResourcePath("js", "assets/js")

# ── Default colour palette — viridis for discrete & continuous ──
# Applied globally so every plot inherits perceptually-uniform,
# colourblind-friendly scales without per-plot boilerplate.
options(
  ggplot2.discrete.colour   = function(...) scale_colour_viridis_d(...),
  ggplot2.discrete.fill     = function(...) scale_fill_viridis_d(...),
  ggplot2.continuous.colour = function(...) scale_colour_viridis_c(...),
  ggplot2.continuous.fill   = function(...) scale_fill_viridis_c(...)
)

# ── App configuration (reads env vars via config.yml) ───────────
cfg <- config::get()

# ── App definition (factory function — called once per session) ─
MtcarsApp <- function() {
  # ── Single reactiveStore for all app state ────────────────────
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
    plot = list(
      x_var = "mpg",
      y_var = "hp",
      color_var = "cyl"
    ),
    dark_mode = FALSE
  ))

  # ── Dataset ───────────────────────────────────────────────────
  data <- mtcars
  data$model <- rownames(data)

  # ── Handlers (factories that close over the store) ────────────
  on_login  <- handle_login(state)
  on_logout <- handle_logout(state)

  # ── Plot function (factory that returns a 0-arg ggplot builder)
  plot_fn <- build_plot(state, data, state$dark_mode)

  # ── Dark-mode dependency (JS widget source) ───────────────────
  # The src `c(href = "js")` is served via addResourcePath("js", "assets/js")
  # above, so the browser loads /js/dark-mode.js.
  dark_mode_dep <- htmlDependency(
    name    = "dark-mode",
    version = "1.0.0",
    src     = c(href = "js"),
    script  = "dark-mode.js"
  )

  # ── Assemble ──────────────────────────────────────────────────
  app_shell(
    title = "Mtcars Explorer",
    user = \() {
      if (state$auth$logged_in()) list(username = state$auth$user_name())
      else NULL
    },
    on_logout = on_logout,

    # Hidden widget: bridges prefers-color-scheme into the reactive
    # store via irid's native wire protocol.  The JS factory calls
    # sendEvent("scheme-change", {dark}) on every OS theme change,
    # and the handler below pushes it into state$dark_mode.
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
      \() mtcars_explorer(
        store = state,
        data = data,
        plot_fn = plot_fn
      ),
      otherwise = \() login_page(
        store = state,
        on_login = on_login,
        title = "Mtcars Explorer"
      )
    )
  )
}

# ── Launch ──────────────────────────────────────────────────────
iridApp(MtcarsApp)
