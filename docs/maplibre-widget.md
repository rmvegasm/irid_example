<!-- agents: custom irid widgets, IridWidget contract, and MapLibre GL wiring -->

# Custom widgets: the MapLibre GL admin map

This page explains how the app wraps MapLibre GL as a custom irid widget.
It is the deepest part of the example, and the best starting point if you
want to bring a non-Shiny JavaScript library into an irid app.

It assumes you have read [Code organization & component
modules](architecture.md) and have the irid mental model: a component is an
R function holding state and markup, with no `ui`/`server` split.

## What IridWidget is for

Shiny ships `htmlwidgets` for wrapping JavaScript libraries, but
`htmlwidgets` lives outside irid's reactive graph. `IridWidget()` is the
irid-native bridge: a widget that participates in fine-grained reactivity
the same way a `value` binding or a `When` control-flow node does.

A widget has two halves:

- **R side** --- `IridWidget(name = ..., props = ..., events = ...)`.
- **JavaScript side** ---
  `window.irid.defineWidget("...", factory)` where `factory(el, props,
  sendEvent, setProp)` returns a `{ update, destroy }` handle.

The two halves agree on the `name`. Props flow server-to-client; events
flow client-to-server.

## The R side of a widget

`IridWidget()` takes:

- `name` --- the registry key, matching a JS
  `irid.defineWidget("<name>", ...)` call.
- `props` --- a named list. A **callable** value (`reactiveVal`, store
  leaf, `reactiveProxy`) is a two-way-capable binding; a non-callable value
  is an init-only constant.
- `events` --- a named list of client-to-server handlers, keyed by the wire
  event name the JS passes to `sendEvent()`. `NULL` entries are dropped so
  optional handlers forward declaratively.
- `deps` --- an `html_dependency` or list of them; required for any widget
  whose JS is not already loaded.
- `container` --- the wrapper `shiny.tag`. irid sets its `id` and
  `data-irid-widget` attribute automatically.

Props and events share a per-widget namespace, so a prop and an event may
not have the same name.

## The JavaScript side of a widget

A widget factory is registered once and called once per mount:

```js
window.irid.defineWidget("my-widget", function (el, props, sendEvent, setProp) {
  // el:      the container element
  // props:   the init object (constants + first values of callable props)
  // sendEvent(name, payload):  emit a client -> server event
  // setProp(name, value):      write back through a bound reactive

  return {
    update: function (values) {
      // values: the merged map of props that changed this flush
    },
    destroy: function () {
      // teardown; called on unmount and on teardown-mid-construction
    }
  };
});
```

The factory may return the handle directly, or a `Promise` of it --- irid
awaits async factories and buffers updates until the handle lands. In this
app the factory returns the handle synchronously and does its async work in
the background (see [Sync handle, async
init](#sync-handle-async-init)).

## The MapLibre admin map, end to end

```text
                                     ┌────────────────┐                                                      ┌──────────────────┐
 ┌─────────────────┐                 │MaplibreAdmin() │                    ┌──────────┐────────update───────▶│                  │
 │R reactive store │──────props─────▶│                │────────props──────▶│irid wire │                      │                  │                  ┌────────────┐
 │                 │◀┐               └────────────────┘              ┌─────│          │◀────────event────────│maplibre-admin.js │───────style─────▶│MapLibre GL │
 └─────────────────┘ └────────────────────handler────────────────────┘     └──────────┘                      │                  │◀──────click──────│            │
                                                                                                         ┌──▶│                  │                  └────────────┘
                                                                                                         │   │                  │
                                                                         ┌───────────────┐──────fetch────┘   └──────────────────┘
                                                                         │/geo/*.geojson │
                                                                         │               │
                                                                         └───────────────┘
```

▶ Diagram source: [maplibre-widget.d2](maplibre-widget.d2)

The R wrapper is `MaplibreAdmin()` in
`r/components/maplibre/admin_map.r`; the factory is
`assets/js/maplibre-admin.js`. The store (the `geo` reactive store) feeds
callable props into the wrapper; the wrapper forwards them over the irid
wire; the factory applies them to the live map. Clicks travel the other way
as a single `feature-click` event, and the R handler mutates the store,
which flows back down as new props.

## Props: server to client

`MaplibreAdmin()` declares five callable props:

- `selectedCountries`, `selectedStates`, `selectedCounties` --- character
  vectors of selected ids, bound to `geo$selection$*`.
- `activeLevel` --- `"country"` | `"state"` | `"county"`, bound to
  `geo$active_level`.
- `darkMode` --- logical, bound to `state$dark_mode`.

Because each is callable, a change to the store sends only that prop in the
next `update()` call --- the widget re-applies filters or the basemap
without rebuilding the map. The widget never calls `setProp()`, so the
write-back half of each two-way binding stays latent.

## Events: client to server

The widget declares one event:

```r
events = list(
  `feature-click` = on_feature_click
)
```

The JS factory calls `sendEvent("feature-click", { id, adminLevel })` when
the user clicks a polygon of the currently active level. The R handler
(`on_map_click` in `admin_picker_page.r`) decides what the click means:
remove for countries, toggle for states and counties. Keeping that policy
in R means the widget stays behaviour-agnostic --- it only reports *what
was clicked*, never *what to do about it*.

## Dependencies

The wrapper returns two `html_dependency` objects:

- MapLibre GL 5.2.0 (JS + CSS) from the unpkg CDN.
- The app's own factory script, `maplibre-admin.js`, served from the `js/`
  resource path registered in `app.r`.

irid delivers a widget's deps at mount time via `insertUI`, so they are
loaded even for widgets that appear only inside a `When`/`Each` branch.

## Geometry stays out of the wire

The three GeoJSON files are served as static assets at `/geo/*.geojson`.
The factory fetches them directly; R only ever loads the compact
`*_meta.json` tables for the pickers. Only the tiny selection-id vectors
round-trip through irid. This is the central performance decision of the
app: never serialize polygons through Shiny.

## The JS factory, section by section

The factory is a single IIFE in `assets/js/maplibre-admin.js`. These are
the decisions worth understanding before modifying it.

### Sync handle, async init

The factory returns its `{ update, destroy }` handle immediately and kicks
off construction in the background: it waits for the `window.maplibregl`
global, fetches the three GeoJSON files, then builds the map. `update()`
merges values into a local `state` object right away; the map applies the
latest state once construction finishes. This works on every irid version
(irid >= 0.3.0 also awaits async factories), and keeps "library not loaded
yet" a factory-internal concern.

### Normalizing length-1 vectors

Shiny serializes a length-1 character vector as a JSON *scalar* (its
`auto_unbox` behaviour), while a length-0 vector is `[]` and length-2+ is
`[...]`. The `toArray()` helper normalizes every selection prop to a real
array before it feeds MapLibre `literal` filters, which would otherwise
choke on a scalar.

### Dark-mode basemap without a light flash

The initial basemap style is chosen from
`props.darkMode || systemPrefersDark()`, where `systemPrefersDark()` reads
the `prefers-color-scheme` media query directly. The store's `dark_mode`
value arrives a tick after the map's first render (it is bridged in by the
`dark-mode-detector` widget), so without this fallback the map would flash
light before the store caught up.

### Clickable transparent polygons

Unselected fills use an opacity of `0.01`, not `0`. A fully transparent
fill is still rendered and hit-tested, so the interior of an unselected
polygon stays clickable --- users can toggle it from its body rather than
only from its border.

### One visible level at a time

`applyVisibility()` flips each admin level's fill+line layer pair between
`visible` and `none` based on `activeLevel`, so the map never stacks three
levels. Selection filters and paint expressions are applied per level in
`applyFilters()`.

### Bounding box from original features

`fitToSelectedCountries()` computes the zoom-to-selection bounding box from
the original fetched `countriesFC`, not from
`map.querySourceFeatures()`. MapLibre's geojson-vt tiling can split a
feature across tiles, which duplicates features and corrupts both counts
and bounding boxes.

## A second, smaller widget: dark-mode-detector

`assets/js/dark-mode.js` is a minimal widget worth reading before you write
your own. It has no props and one event:

- `scheme-change` --- fired with `{ dark }` when the OS
  `prefers-color-scheme` preference changes.

Two details matter:

- The `matchMedia` listener is added in the factory and removed in
  `destroy()`, so the widget cleans up after itself on teardown.
- The initial event is deferred with `setTimeout(fn, 0)` rather than sent
  synchronously from the factory. Sending during construction races the
  wire-op application and the event is dropped.

## Debugging hints

The factory leaves two globals for browser-console inspection:

- `window.__adminMap` --- the live MapLibre map instance (call
  `getStyle()`, `getFilter()`, `queryRenderedFeatures()`, ...).
- `window.__adminState` --- the factory's local state object (selection,
  active level, dark mode).

A blank map or missing polygons is usually a JS error in the factory ---
check the console and confirm the three `/geo/*.geojson` fetches returned
200. Remember that `curl` on the page HTML shows empty `<!--irid:s:...-->`
comment anchors; irid mounts control-flow content client-side, so a browser
(not `curl`) is the right tool for verifying render output.
