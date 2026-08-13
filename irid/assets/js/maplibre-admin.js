/* ─────────────────────────────────────────────────────────────────────
 * maplibre-admin.js — irid widget factory for the admin polygon picker
 *
 * Registers `maplibre-admin` with irid. The factory returns its
 * `{update, destroy}` handle synchronously; the async loading work
 * (waiting for `window.maplibregl`, fetching the bundled GeoJSON) is
 * kicked off in the background. `update()` merges values into the local
 * state immediately and the map applies the latest state once
 * construction completes. (irid ≥ 0.3.0 also awaits async factories, but
 * the sync handle keeps the two concerns decoupled and works everywhere.)
 *
 * Server → client props (reactive, delivered through update()):
 *   selectedCountries: string[]   admin-0 ids currently selected
 *   selectedStates:    string[]   admin-1 ids currently selected
 *   selectedCounties:  string[]   admin-2 ids currently selected
 *   activeLevel:       "country" | "state" | "county"
 *   darkMode:          boolean
 *
 * Client → server event:
 *   feature-click: { id, adminLevel } — a feature of the active level was
 *   clicked. R decides what it means (remove for countries, toggle for
 *   states/counties) so the widget stays behaviour-agnostic.
 * ───────────────────────────────────────────────────────────────────── */

(function () {
  "use strict";

  var LEVELS = {
    country: 0,
    state: 1,
    county: 2
  };

  var SOURCE_BY_LEVEL = { 0: "countries", 1: "states", 2: "counties" };

  var LAYERS_BY_LEVEL = {
    0: ["countries-fill", "countries-line"],
    1: ["states-fill", "states-line"],
    2: ["counties-fill", "counties-line"]
  };

  var BASEMAPS = {
    light: "https://a.basemaps.cartocdn.com/light_all/{z}/{x}/{y}@2x.png",
    dark: "https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png"
  };

  function waitFor(predicate, interval, timeout) {
    return new Promise(function (resolve, reject) {
      var started = Date.now();
      (function poll() {
        var value;
        try { value = predicate(); } catch (e) { value = undefined; }
        if (value) return resolve(value);
        if (Date.now() - started > timeout) {
          return reject(new Error("maplibre-admin: timed out waiting for dependency"));
        }
        setTimeout(poll, interval);
      })();
    });
  }

  function fetchJSON(url) {
    return fetch(url).then(function (res) {
      if (!res.ok) throw new Error(url + ": HTTP " + res.status);
      return res.json();
    });
  }

  // irid serializes a length-1 character vector as a JSON *scalar* (Shiny's
  // `auto_unbox`), while 0 -> `[]` and 2+ -> `[...]`. Normalize so selection
  // props are ALWAYS arrays before they feed maplibre `literal` filters.
  function toArray(v) {
    if (v == null) return [];
    return Array.isArray(v) ? v : [v];
  }

  // The app's dark mode mirrors the OS `prefers-color-scheme` media query,
  // bridged into the reactive store by the `dark-mode-detector` widget. That
  // value arrives a tick *after* this map widget's first render, so use the
  // media query directly for the initial basemap — otherwise the map flashes
  // light before the store catches up.
  function systemPrefersDark() {
    return typeof window.matchMedia === "function" &&
      window.matchMedia("(prefers-color-scheme: dark)").matches;
  }

  function makeBasemapStyle(dark) {
    return {
      version: 8,
      sources: {
        basemap: {
          type: "raster",
          tiles: [dark ? BASEMAPS.dark : BASEMAPS.light],
          tileSize: 256,
          attribution:
            '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> ' +
            '&copy; <a href="https://carto.com/attributions">CARTO</a>'
        }
      },
      layers: [{ id: "basemap", type: "raster", source: "basemap" }]
    };
  }

  // Build a fill-opacity expression. `case` takes (cond, value) pairs and a
  // default, so: hovered → hoverOpaque, selected → selectedOpaque, otherwise
  // transparent (but NOT absent — a near-zero opacity keeps the fill rendered
  // and therefore clickable, so unselected polygons can be toggled from their
  // interior instead of only from their border).
  function fillOpacity(ids, hoverOpaque, selectedOpaque) {
    return [
      "case",
      ["boolean", ["feature-state", "hover"], false], hoverOpaque,
      ["in", ["get", "id"], ["literal", ids]], selectedOpaque,
      0.01
    ];
  }

  function lineWidth(ids, hoverW, selectedW, defaultW) {
    return [
      "case",
      ["boolean", ["feature-state", "hover"], false], hoverW,
      ["in", ["get", "id"], ["literal", ids]], selectedW,
      defaultW
    ];
  }

  function makeLayers() {
    return [
      {
        id: "countries-fill",
        type: "fill",
        source: "countries",
        paint: {
          "fill-color": "#3b82f6",
          "fill-opacity": ["case", ["boolean", ["feature-state", "hover"], false], 0.78, 0.5]
        }
      },
      {
        id: "countries-line",
        type: "line",
        source: "countries",
        paint: {
          "line-color": "#1d4ed8",
          "line-width": ["case", ["boolean", ["feature-state", "hover"], false], 2.4, 1.4],
          "line-opacity": 0.9
        }
      },
      {
        id: "states-fill",
        type: "fill",
        source: "states",
        paint: {
          "fill-color": "#10b981",
          "fill-opacity": ["case", ["boolean", ["feature-state", "hover"], false], 0.72, 0.01]
        }
      },
      {
        id: "states-line",
        type: "line",
        source: "states",
        paint: {
          "line-color": "#047857",
          "line-width": ["case", ["boolean", ["feature-state", "hover"], false], 2.4, 1.1],
          "line-opacity": 0.9
        }
      },
      {
        id: "counties-fill",
        type: "fill",
        source: "counties",
        minzoom: 4,
        paint: {
          "fill-color": "#f59e0b",
          "fill-opacity": ["case", ["boolean", ["feature-state", "hover"], false], 0.72, 0.01]
        }
      },
      {
        id: "counties-line",
        type: "line",
        source: "counties",
        minzoom: 4,
        paint: {
          "line-color": "#b45309",
          "line-width": ["case", ["boolean", ["feature-state", "hover"], false], 2, 0.7],
          "line-opacity": 0.9
        }
      }
    ];
  }

  // Compute a [[west,south],[east,north]] bbox from a set of GeoJSON features.
  function bboxOfFeatures(features) {
    var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    function visit(ring) {
      if (typeof ring[0] === "number") {
        var x = ring[0], y = ring[1];
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
        return;
      }
      for (var i = 0; i < ring.length; i++) visit(ring[i]);
    }
    features.forEach(function (f) {
      var g = f.geometry;
      if (!g) return;
      if (g.type === "Polygon") visit(g.coordinates);
      else if (g.type === "MultiPolygon") visit(g.coordinates);
      else if (g.type === "GeometryCollection") {
        g.geometries.forEach(function (sub) {
          if (sub.type === "Polygon") visit(sub.coordinates);
          else if (sub.type === "MultiPolygon") visit(sub.coordinates);
        });
      }
    });
    if (!isFinite(minX)) return null;
    return [[minX, minY], [maxX, maxY]];
  }

  window.irid.defineWidget("maplibre-admin", function (el, props, sendEvent, setProp) {
    // ── tooltip ──────────────────────────────────────────────────
    var tooltip = document.createElement("div");
    tooltip.style.cssText =
      "position:absolute;z-index:10;pointer-events:none;display:none;" +
      "background:rgba(17,24,39,0.92);color:#fff;font:12px/1.4 -apple-system,sans-serif;" +
      "padding:4px 8px;border-radius:6px;box-shadow:0 2px 8px rgba(0,0,0,0.3);" +
      "transform:translate(14px,14px);white-space:nowrap;";
    el.appendChild(tooltip);

    // ── state the factory keeps locally ─────────────────────────
    var state = {
      selectedCountries: toArray(props.selectedCountries),
      selectedStates: toArray(props.selectedStates),
      selectedCounties: toArray(props.selectedCounties),
      activeLevel: props.activeLevel || "country",
      darkMode: !!props.darkMode || systemPrefersDark()
    };
    var prevCountryKey = state.selectedCountries.slice().sort().join("|");
    var map = null;
    var countriesData = null;
    var destroyed = false;
    var hovered = null; // { source, id }
    var userInteracting = false;

    function levelNumber(name) {
      return LEVELS[name] != null ? LEVELS[name] : 0;
    }

    function applyFilters() {
      var sc = state.selectedCountries || [];
      var ss = state.selectedStates || [];
      var scc = state.selectedCounties || [];
      var inCountries = ["in", ["get", "country_id"], ["literal", sc]];

      // Countries: per the design only *selected* countries are shown at all
      // (the map "removes them as countries are removed from selection").
      map.setFilter("countries-fill", ["in", ["get", "id"], ["literal", sc]]);
      map.setFilter("countries-line", ["in", ["get", "id"], ["literal", sc]]);

      // States/counties: every polygon within the selected countries is
      // rendered (line = visible border; fill = coloured when selected,
      // transparent-but-clickable when not).
      map.setFilter("states-fill", inCountries);
      map.setFilter("states-line", inCountries);
      map.setFilter("counties-fill", inCountries);
      map.setFilter("counties-line", inCountries);

      // The fill/line styling branches on the selection, so refresh the paint
      // expressions whenever the selection changes.
      map.setPaintProperty("states-fill", "fill-opacity", fillOpacity(ss, 0.72, 0.42));
      map.setPaintProperty("states-line", "line-width", lineWidth(ss, 2.4, 1.6, 1.1));
      map.setPaintProperty("counties-fill", "fill-opacity", fillOpacity(scc, 0.72, 0.45));
      map.setPaintProperty("counties-line", "line-width", lineWidth(scc, 2, 1.2, 0.7));
    }

    // Only the *active* admin level is visible. Switching picker focus swaps
    // the rendered level (countries → states → counties and back) so the map
    // never shows several levels stacked on top of each other.
    function applyVisibility() {
      var level = levelNumber(state.activeLevel);
      for (var lv = 0; lv <= 2; lv++) {
        var layers = LAYERS_BY_LEVEL[lv];
        var visibility = lv === level ? "visible" : "none";
        map.setLayoutProperty(layers[0], "visibility", visibility);
        map.setLayoutProperty(layers[1], "visibility", visibility);
      }
    }

    function applyBasemap() {
      var src = map.getSource("basemap");
      if (src && src.setTiles) {
        src.setTiles([state.darkMode ? BASEMAPS.dark : BASEMAPS.light]);
      }
    }

    function fitToSelectedCountries() {
      if (!state.selectedCountries.length) {
        map.flyTo({ center: [0, 25], zoom: 1.3, duration: 600 });
        return;
      }
      // Compute the bbox from the ORIGINAL fetched features, not from
      // `querySourceFeatures` — maplibre's geojson-vt tiling can split a
      // feature across tiles, which pollutes both counts and geometry.
      if (!countriesData) return;
      var ids = {};
      state.selectedCountries.forEach(function (id) { ids[id] = true; });
      var feats = countriesData.features.filter(function (f) {
        return ids[f.properties.id];
      });
      var bbox = bboxOfFeatures(feats);
      if (bbox) {
        map.fitBounds(bbox, { padding: 80, maxZoom: 6, duration: 600 });
      }
    }

    function setHover(level, id) {
      if (hovered) {
        map.setFeatureState(
          { source: hovered.source, id: hovered.id },
          { hover: false }
        );
      }
      if (id == null) {
        hovered = null;
        return;
      }
      hovered = { source: SOURCE_BY_LEVEL[level], id: id };
      map.setFeatureState({ source: hovered.source, id: hovered.id }, { hover: true });
    }

    function showTooltip(point, name) {
      tooltip.textContent = name;
      tooltip.style.display = "block";
      tooltip.style.left = point.x + "px";
      tooltip.style.top = point.y + "px";
    }

    function hideTooltip() {
      tooltip.style.display = "none";
    }

    function activeFeature(e) {
      var level = levelNumber(state.activeLevel);
      var layers = LAYERS_BY_LEVEL[level];
      var feats = map.queryRenderedFeatures(e.point, { layers: layers });
      for (var i = 0; i < feats.length; i++) {
        if (feats[i].properties.admin_level === level) return feats[i];
      }
      return null;
    }

    // ── map construction (background async load, sync handle) ──
    function initMap(maplibregl, countriesFC, statesFC, countiesFC) {
      if (destroyed) return;
      countriesData = countriesFC;

      map = new maplibregl.Map({
        container: el,
        style: makeBasemapStyle(state.darkMode),
        center: [0, 25],
        zoom: 1.3,
        attributionControl: true
      });

      // Debug/inspection hook — harmless to leave in; lets a developer poke
      // at the live map from the browser console (`window.__adminMap`).
      window.__adminMap = map;
      window.__adminState = state;

      map.addControl(new maplibregl.NavigationControl({ visualizePitch: true }), "top-right");

      map.on("load", function () {
        map.addSource("countries", { type: "geojson", data: countriesFC, promoteId: "id" });
        map.addSource("states", { type: "geojson", data: statesFC, promoteId: "id" });
        map.addSource("counties", { type: "geojson", data: countiesFC, promoteId: "id" });

        makeLayers().forEach(function (layer) { map.addLayer(layer); });

        applyFilters();
        applyVisibility();
        applyBasemap();
        if (state.selectedCountries.length > 0) fitToSelectedCountries();
      });

      map.on("click", function (e) {
        var feat = activeFeature(e);
        if (!feat) return;
        sendEvent("feature-click", {
          id: feat.properties.id,
          adminLevel: feat.properties.admin_level
        });
      });

      map.on("mousemove", function (e) {
        var feat = activeFeature(e);
        if (feat) {
          map.getCanvas().style.cursor = "pointer";
          showTooltip(e.point, feat.properties.name);
          setHover(feat.properties.admin_level, feat.properties.id);
        } else {
          map.getCanvas().style.cursor = "";
          hideTooltip();
          setHover(levelNumber(state.activeLevel), null);
        }
      });

      map.on("mouseleave", function () {
        map.getCanvas().style.cursor = "";
        hideTooltip();
        setHover(levelNumber(state.activeLevel), null);
      });

      map.on("dragstart", function () { userInteracting = true; });
      map.on("dragend", function () { userInteracting = false; });
    }

    Promise.all([
      waitFor(function () { return window.maplibregl; }, 50, 30000),
      fetchJSON("/geo/countries.geojson"),
      fetchJSON("/geo/states.geojson"),
      fetchJSON("/geo/counties.geojson")
    ]).then(function (parts) {
      initMap(parts[0], parts[1], parts[2], parts[3]);
    }).catch(function (e) {
      console.error("maplibre-admin: init failed", e);
    });

    return {
      update: function (values) {
        window.__adminUpdateCount = (window.__adminUpdateCount || 0) + 1;

        var countryChanged = false;
        if ("selectedCountries" in values) {
          var next = toArray(values.selectedCountries);
          var nextKey = next.slice().sort().join("|");
          if (nextKey !== prevCountryKey) {
            countryChanged = true;
            prevCountryKey = nextKey;
          }
          state.selectedCountries = next;
        }
        if ("selectedStates" in values) state.selectedStates = toArray(values.selectedStates);
        if ("selectedCounties" in values) state.selectedCounties = toArray(values.selectedCounties);
        if ("activeLevel" in values) state.activeLevel = values.activeLevel;
        if ("darkMode" in values) state.darkMode = !!values.darkMode;

        if (!map || !map.loaded()) return; // map applies latest state on load

        applyFilters();
        applyVisibility();
        if ("darkMode" in values) applyBasemap();

        if (countryChanged && !userInteracting) {
          fitToSelectedCountries();
        }
      },
      destroy: function () {
        destroyed = true;
        if (map) map.remove();
        if (tooltip && tooltip.parentNode) tooltip.parentNode.removeChild(tooltip);
      }
    };
  });
})();
