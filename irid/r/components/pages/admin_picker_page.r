#' r/components/pages/admin_picker_page — MapLibre admin picker page
#'
#' The main app section (replaces the mtcars explorer). Left panel hosts
#' three instances of the same `admin_picker` component (countries, level-1
#' subdivisions, level-2 subdivisions); the right two-thirds hosts the
#' MapLibre map. Selection state lives in a dedicated `reactiveStore`
#' (`geo`), kept separate from the authentication store. Removing a unit
#' also removes its selected children in lower admin levels.
#'
#' Labels and option badges are driven by the GADM `ENGTYPE_*` values loaded
#' into the metadata tables, so a country's "level 1" picker reads
#' "Province / Territory" for Canada and "State" for the United States.
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
  ../../geo[filter_by_country, filter_by_state, geo_dataobj_url, geo_meta_url],
)

# ── helpers ────────────────────────────────────────────────────────

.has_type <- function(x) {
  length(x) == 1L && !is.na(x) && nzchar(x)
}

.selected_records <- function(ids, df) {
  if (length(ids) == 0L) return(list())
  idx <- match(ids, df$id)
  idx <- idx[!is.na(idx)]
  lapply(idx, function(i) {
    eng <- df$engtype[i]
    if (length(eng) == 0L || is.na(eng)) eng <- ""
    list(name = df$name[i], engtype = eng)
  })
}

.types_label <- function(engtypes, fallback) {
  engtypes <- unique(engtypes[!is.na(engtypes) & nzchar(engtypes)])
  if (length(engtypes) == 0L) return(fallback)
  paste(engtypes, collapse = " / ")
}

.hint <- function(level) {
  switch(
    level,
    country = "Click a country on the map to remove it from the selection.",
    state   = "Click a unit on the map to toggle its selection.",
    county  = "Click a unit on the map to toggle its selection.",
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
  # ── parent filters (options are resolved client-side) ─────────
  state_filter_ids <- reactive({
    geo$selection$country()
  })

  county_filter <- reactive({
    states <- geo$selection$state()
    if (length(states) > 0L) {
      list(field = "state_id", ids = states)
    } else {
      list(field = "country_id", ids = geo$selection$country())
    }
  })

  # Dynamic picker labels from the GADM ENGTYPE values currently offered.
  # When no parent is selected we show the hint instead of the full
  # concatenation of every country's unit types.
  state_label <- reactive({
    countries <- geo$selection$country()
    if (length(countries) == 0L) return("Select a country first")
    sub <- filter_by_country(data$states, countries)
    if (nrow(sub) == 0L) return("States / provinces")
    .types_label(sub$engtype, "States / provinces")
  })

  county_label <- reactive({
    countries <- geo$selection$country()
    states    <- geo$selection$state()
    if (length(countries) == 0L && length(states) == 0L) {
      return("Select a country or state first")
    }
    sub <- if (length(states) > 0L) {
      filter_by_state(data$counties, states)
    } else {
      filter_by_country(data$counties, countries)
    }
    if (nrow(sub) == 0L) return("Counties")
    .types_label(sub$engtype, "Counties")
  })

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
    # Counties now carry their parent state id, so deselecting a state only
    # clears that state's counties (not the whole country's).
    county_ids <- data$counties$id[data$counties$state_id %in% state_id]
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
  selected_section <- function(label, level, df) {
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
            \() .selected_records(ids(), df),
            \(item) tags$span(
              class = paste(
                "inline-flex items-center rounded-md px-2 py-0.5 text-xs font-medium",
                "bg-gray-100 dark:bg-neutral-700 text-gray-700 dark:text-neutral-200"
              ),
              item$name(),
              When(
                \() .has_type(item$engtype()),
                \() tags$span(
                  class = paste(
                    "ml-1 text-[10px] uppercase tracking-wide",
                    "text-gray-400 dark:text-neutral-500"
                  ),
                  item$engtype()
                )
              )
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
        tags$span("Level 1 (click to toggle)")
      ),
      tags$div(class = "flex items-center gap-2",
        tags$span(class = "h-2.5 w-2.5 rounded-sm bg-amber-500 inline-block"),
        tags$span("Level 2 (click to toggle)")
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
          selected = geo$selection$country,
          active = active("country"),
          level = "countries",
          filter_field = "",
          filter_ids = \() character(),
          meta_url = geo_meta_url,
          on_focus = \() geo$active_level("country"),
          on_toggle = \(id) toggle("country", id),
          empty_text = "No countries"
        ),
        admin_picker(
          label = state_label,
          selected = geo$selection$state,
          active = active("state"),
          level = "states",
          filter_field = "country_id",
          filter_ids = state_filter_ids,
          meta_url = geo_meta_url,
          on_focus = \() geo$active_level("state"),
          on_toggle = \(id) toggle("state", id),
          empty_text = "Select a country first"
        ),
        admin_picker(
          label = county_label,
          selected = geo$selection$county,
          active = active("county"),
          level = "counties",
          filter_field = \() county_filter()$field,
          filter_ids = \() county_filter()$ids,
          meta_url = geo_meta_url,
          on_focus = \() geo$active_level("county"),
          on_toggle = \(id) toggle("county", id),
          empty_text = "Select a country or state first"
        )
      ),

      # Selected units
      tags$div(
        class = "flex-1 overflow-y-auto max-h-72 lg:max-h-none px-4 py-4 space-y-4",
        selected_section("Countries", "country", data$countries),
        selected_section("Level 1", "state", data$states),
        selected_section("Level 2", "county", data$counties)
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
        geo_base_url       = geo_dataobj_url,
        on_feature_click   = on_map_click
      )
    )
  )
}
