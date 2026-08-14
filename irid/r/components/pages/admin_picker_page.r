#' r/components/pages/admin_picker_page — MapLibre admin picker page
#'
#' The main app section (replaces the mtcars explorer). Left panel hosts
#' three instances of the same `admin_picker` component (countries, states,
#' counties); the right two-thirds hosts the MapLibre map. Selection state
#' lives in a dedicated `reactiveStore` (`geo`), kept separate from the
#' authentication store. Removing a unit also removes its selected children
#' in lower admin levels.
#'
#' @md
#' @name admin_picker_page
box::use(
  shiny[tags],
  irid[reactive, Each, When],
)

box::use(
  ../maplibre/admin_map[MaplibreAdmin],
  ../maplibre/admin_picker[admin_picker],
  ../../geo[filter_by_country, lookup_names],
)

# ── helpers ────────────────────────────────────────────────────────

.records <- function(df) {
  lapply(seq_len(nrow(df)), function(i) list(id = df$id[i], name = df$name[i]))
}

.selected_names <- function(ids, lookup) {
  if (length(ids) == 0L) return(character())
  nms <- unname(lookup[ids])
  nms[!is.na(nms)]
}

.hint <- function(level) {
  switch(
    level,
    country = "Click a country on the map to remove it from the selection.",
    state   = "Click a state on the map to toggle its selection.",
    county  = "Click a county on the map to toggle its selection.",
    "Select an admin unit."
  )
}

#' Admin picker page
#'
#' @param geo A `reactiveStore` with:
#'   - `active_level` — character reactiveVal ("country"/"state"/"county")
#'   - `selection` — store node with `country`, `state`, `county` character
#'     reactiveVals holding the selected ids per level.
#' @param data Static geo metadata from `r/geo` (`load_geo()`).
#' @param dark_mode A callable returning a logical (drives the basemap).
#' @return A shiny tag tree.
#' @export
admin_picker_page <- function(geo, data, dark_mode) {
  # ── derived choices (per level) ─────────────────────────────────
  country_choices <- reactive({
    .records(data$countries)
  })

  state_choices <- reactive({
    .records(filter_by_country(data$states, geo$selection$country()))
  })

  county_choices <- reactive({
    .records(filter_by_country(data$counties, geo$selection$country()))
  })

  country_names <- lookup_names(data$countries)
  state_names   <- lookup_names(data$states)
  county_names  <- lookup_names(data$counties)

  # ── selection mutation helpers ──────────────────────────────────
  # Removing a unit also removes any selected children in lower admin
  # levels, so a deselected parent never leaves orphaned selections behind.
  clear_country_children <- function(country_id) {
    state_ids  <- data$states$id[data$states$country_id %in% country_id]
    county_ids <- data$counties$id[data$counties$country_id %in% country_id]
    geo$selection$state(setdiff(geo$selection$state(), state_ids))
    geo$selection$county(setdiff(geo$selection$county(), county_ids))
  }

  clear_state_children <- function(state_id) {
    # Counties are keyed only by country (not by state), so deselecting a
    # state clears its country's county selection.
    cid <- data$states$country_id[data$states$id == state_id]
    if (length(cid) == 0L || all(is.na(cid))) return()
    county_ids <- data$counties$id[data$counties$country_id %in% cid]
    geo$selection$county(setdiff(geo$selection$county(), county_ids))
  }

  remove <- function(level, id) {
    cur <- geo$selection[[level]]()
    if (!(id %in% cur)) return()
    geo$selection[[level]](setdiff(cur, id))
    if (level == "country") {
      clear_country_children(id)
    } else if (level == "state") {
      clear_state_children(id)
    }
  }

  toggle <- function(level, id) {
    cur <- geo$selection[[level]]()
    if (id %in% cur) {
      remove(level, id)
    } else {
      geo$selection[[level]](c(cur, id))
    }
  }

  on_map_click <- function(e) {
    lvl <- as.integer(e$adminLevel)
    if (length(lvl) != 1L || is.na(lvl) || is.null(e$id)) return()
    if (lvl == 0L) {
      # Countries: clicking a polygon removes it (per design).
      remove("country", e$id)
    } else if (lvl == 1L) {
      toggle("state", e$id)
    } else {
      toggle("county", e$id)
    }
  }

  active <- function(level) \() identical(geo$active_level(), level)

  # ── selected units list (per level) ─────────────────────────────
  selected_section <- function(label, level, lookup) {
    ids <- function() geo$selection[[level]]()
    tags$div(
      class = "space-y-1.5",
      tags$div(
        class = "flex items-center justify-between",
        tags$span(class = "text-xs font-semibold uppercase tracking-wide text-gray-400 dark:text-neutral-500", label),
        When(
          \() length(ids()) > 0L,
          \() tags$span(
            class = "text-xs text-gray-400 dark:text-neutral-500",
            \() paste0(length(ids()), " selected")
          )
        )
      ),
      When(
        \() length(ids()) > 0L,
        \() tags$div(
          class = "flex flex-wrap gap-1.5",
          Each(
            \() .selected_names(ids(), lookup),
            \(item) tags$span(
              class = paste(
                "inline-flex items-center rounded-md px-2 py-0.5 text-xs font-medium",
                "bg-gray-100 dark:bg-neutral-700 text-gray-700 dark:text-neutral-200"
              ),
              item()
            )
          )
        ),
        otherwise = \() tags$p(
          class = "text-xs text-gray-400 dark:text-neutral-500 italic",
          "Nothing selected"
        )
      )
    )
  }

  # ── map legend ──────────────────────────────────────────────────
  legend <- function() {
    tags$div(
      class = paste(
        "absolute top-3 left-3 z-10 rounded-lg border border-gray-200 dark:border-neutral-700",
        "bg-white/90 dark:bg-neutral-800/90 backdrop-blur px-3 py-2.5 text-xs shadow-sm",
        "text-gray-700 dark:text-neutral-200"
      ),
      tags$div(class = "font-semibold mb-1.5", "Map layers"),
      tags$div(class = "flex items-center gap-2",
        tags$span(class = "h-2.5 w-2.5 rounded-sm bg-blue-500 inline-block"),
        tags$span("Countries (click to remove)")
      ),
      tags$div(class = "flex items-center gap-2",
        tags$span(class = "h-2.5 w-2.5 rounded-sm bg-emerald-500 inline-block"),
        tags$span("States (click to toggle)")
      ),
      tags$div(class = "flex items-center gap-2",
        tags$span(class = "h-2.5 w-2.5 rounded-sm bg-amber-500 inline-block"),
        tags$span("Counties (click to toggle)")
      )
    )
  }

  # ── page ────────────────────────────────────────────────────────
  tags$div(
    class = "h-full w-full flex flex-col lg:flex-row",

    # Left panel — pickers + selected units
    tags$div(
      class = paste(
        "flex flex-col lg:h-full lg:w-1/3 xl:w-1/4 shrink-0",
        "border-b lg:border-b-0 lg:border-r border-gray-200 dark:border-neutral-700",
        "bg-white dark:bg-neutral-800"
      ),

      # Header
      tags$div(
        class = "px-4 py-4 border-b border-gray-200 dark:border-neutral-700",
        tags$h2(class = "text-lg font-bold text-gray-900 dark:text-neutral-100", "Administrative units"),
        tags$p(
          class = "mt-0.5 text-xs text-gray-500 dark:text-neutral-400",
          \() .hint(geo$active_level())
        )
      ),

      # Pickers
      tags$div(
        class = "px-4 py-4 space-y-3 border-b border-gray-200 dark:border-neutral-700",
        admin_picker(
          label = "Countries",
          choices = country_choices,
          selected = geo$selection$country,
          active = active("country"),
          on_focus = \() geo$active_level("country"),
          on_toggle = \(id) toggle("country", id),
          empty_text = "No countries"
        ),
        admin_picker(
          label = "States / provinces",
          choices = state_choices,
          selected = geo$selection$state,
          active = active("state"),
          on_focus = \() geo$active_level("state"),
          on_toggle = \(id) toggle("state", id),
          empty_text = "Select a country first"
        ),
        admin_picker(
          label = "Counties",
          choices = county_choices,
          selected = geo$selection$county,
          active = active("county"),
          on_focus = \() geo$active_level("county"),
          on_toggle = \(id) toggle("county", id),
          empty_text = "Select a country first"
        )
      ),

      # Selected units
      tags$div(
        class = "flex-1 overflow-y-auto max-h-72 lg:max-h-none px-4 py-4 space-y-4",
        selected_section("Countries", "country", country_names),
        selected_section("States", "state", state_names),
        selected_section("Counties", "county", county_names)
      )
    ),

    # Map — the remaining 2/3
    tags$div(
      class = "relative h-[60vh] lg:h-auto lg:flex-1 bg-gray-100 dark:bg-neutral-900",
      legend(),
      MaplibreAdmin(
        selected_countries = geo$selection$country,
        selected_states    = geo$selection$state,
        selected_counties  = geo$selection$county,
        active_level       = geo$active_level,
        dark_mode          = dark_mode,
        on_feature_click   = on_map_click
      )
    )
  )
}
