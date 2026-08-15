/* ─────────────────────────────────────────────────────────────────────
 * admin-picker.js — irid widget factory for the admin-unit picker
 *
 * A searchable, multi-select combobox rendered entirely client-side. The
 * option *metadata* (id/name/engtype/parent ids) is fetched from the
 * per-session `geo_meta` data object (see r/geo) and cached by URL, so a
 * given (level, parents) list is transferred once and all subsequent
 * opening/filtering is instant. Geometry is never involved here.
 *
 * Server → client props (reactive):
 *   label:       string        trigger label
 *   selected:    string[]      ids currently selected
 *   active:      boolean       accent the trigger when this is the active level
 *   level:       "countries"|"states"|"counties"
 *   filterField: ""|"country_id"|"state_id"   how to narrow children
 *   filterIds:   string[]      parent ids to narrow by
 *   metaUrl:     string        per-session metadata data-object URL
 *   emptyText:   string        message when there are no matches
 *
 * Client → server events:
 *   picker-focus:  {}          — the picker was opened/focused (R sets active level)
 *   picker-toggle: { id }      — an option was toggled
 *
 * Keyboard behaviour (while open, focus is in the search box):
 *   ↓ / ↑       move the highlighted option
 *   Enter       toggle the highlighted option
 *   Escape      close
 *   Tab         close and move focus to the next picker
 *   typing      goes to the search box (it already has focus)
 *
 * The dropdown closes when the pointer leaves the widget ("unhover"),
 * instead of on focus loss. Selected units are listed first so unselecting
 * them is easy.
 * ───────────────────────────────────────────────────────────────────── */

(function () {
  "use strict";

  var MAX_OPTIONS = 200; // cap rendered rows; search narrows the rest

  // Module-level cache shared by every picker instance (same metaUrl).
  var metaCache = {}; // url -> Promise<records[]>

  function toArray(v) {
    if (v == null) return [];
    return Array.isArray(v) ? v : [v];
  }

  function fetchJSON(url) {
    return fetch(url).then(function (res) {
      if (!res.ok) throw new Error(url + ": HTTP " + res.status);
      return res.json();
    });
  }

  function fetchMeta(url) {
    if (!metaCache[url]) {
      metaCache[url] = fetchJSON(url).catch(function (err) {
        delete metaCache[url];
        throw err;
      });
    }
    return metaCache[url];
  }

  var ICONS = {
    check: '<svg class="h-4 w-4 shrink-0 text-blue-600 dark:text-blue-400" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true"><path d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.857-9.809a.75.75 0 00-1.214-.882l-3.483 4.79-1.88-1.88a.75.75 0 10-1.06 1.061l2.5 2.5a.75.75 0 001.137-.089l4-5.5z"/></svg>',
    empty: '<svg class="h-4 w-4 shrink-0 text-gray-400 dark:text-neutral-500" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true"><circle cx="10" cy="10" r="8"/></svg>',
    chevron: '<svg class="h-4 w-4 text-gray-400 dark:text-neutral-500" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true"><path fill-rule="evenodd" clip-rule="evenodd" d="M5.23 7.21a.75.75 0 011.06.02L10 11.168l3.71-3.938a.75.75 0 111.08 1.04l-4.25 4.5a.75.75 0 01-1.08 0l-4.25-4.5a.75.75 0 01.02-1.06z"/></svg>'
  };

  function el(tag, className, text) {
    var node = document.createElement(tag);
    if (className) node.className = className;
    if (text != null) node.textContent = text;
    return node;
  }

  window.irid.defineWidget("admin-picker", function (root, props, sendEvent) {
    // ── local state ──────────────────────────────────────────────
    var state = {
      level: props.level || "countries",
      label: props.label == null ? "" : String(props.label),
      selected: toArray(props.selected),
      active: !!props.active,
      filterField: props.filterField || "",
      filterIds: toArray(props.filterIds),
      metaUrl: props.metaUrl || "",
      emptyText: props.emptyText || "No units available",
      open: false,
      query: "",
      highlight: -1,
      options: [],
      loading: false,
      fetchSeq: 0
    };
    var destroyed = false;
    var optionButtons = [];

    // ── static DOM skeleton ──────────────────────────────────────
    var trigger = el("button", "relative w-full flex items-center justify-between gap-2 rounded-md border px-3 py-2 text-sm font-medium text-left transition-colors cursor-pointer");
    trigger.type = "button";

    var labelSpan = el("span", "truncate");
    var badgeWrap = el("span", "flex items-center gap-1.5 shrink-0");
    var badge = el("span", "hidden");
    badgeWrap.appendChild(badge);
    badgeWrap.insertAdjacentHTML("beforeend", ICONS.chevron);
    trigger.appendChild(labelSpan);
    trigger.appendChild(badgeWrap);

    var dropdown = el("div", "absolute z-30 mt-1 w-full rounded-md border border-gray-200 dark:border-neutral-700 bg-white dark:bg-neutral-800 shadow-lg overflow-hidden");
    dropdown.style.display = "none";

    var searchWrap = el("div", "p-2 border-b border-gray-200 dark:border-neutral-700");
    var search = el("input", "block w-full rounded-md border border-gray-300 dark:border-neutral-600 px-2.5 py-1.5 text-sm bg-white dark:bg-neutral-900 text-gray-900 dark:text-neutral-100 placeholder:text-gray-400 dark:placeholder:text-neutral-500 focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500");
    search.type = "text";
    search.placeholder = "Search…";
    search.autocomplete = "off";
    searchWrap.appendChild(search);

    var list = el("div", "max-h-60 overflow-y-auto py-1");
    dropdown.appendChild(searchWrap);
    dropdown.appendChild(list);

    root.appendChild(trigger);
    root.appendChild(dropdown);

    // ── metadata URL for the current (level, parents) ────────────
    function metaURL() {
      if (!state.metaUrl) return null;
      var url = state.metaUrl;
      url += (url.indexOf("?") >= 0 ? "&" : "?") + "level=" + encodeURIComponent(state.level);
      if (state.level === "states" && state.filterField === "country_id" && state.filterIds.length) {
        url += "&country=" + encodeURIComponent(state.filterIds.join(","));
      } else if (state.level === "counties") {
        if (state.filterField === "state_id" && state.filterIds.length) {
          url += "&state=" + encodeURIComponent(state.filterIds.join(","));
        } else if (state.filterField === "country_id" && state.filterIds.length) {
          url += "&country=" + encodeURIComponent(state.filterIds.join(","));
        }
      }
      return url;
    }

    function visibleOptions() {
      var q = state.query.trim().toLowerCase();
      var opts = state.options || [];
      if (q) {
        opts = opts.filter(function (o) {
          return (o.name || "").toLowerCase().indexOf(q) !== -1;
        });
      }
      // Surface already-selected units at the very top so deselecting them
      // is easy; the rest keep alphabetical order.
      var sel = {};
      state.selected.forEach(function (id) { sel[id] = true; });
      opts = opts.slice().sort(function (a, b) {
        var as = sel[a.id] ? 0 : 1;
        var bs = sel[b.id] ? 0 : 1;
        if (as !== bs) return as - bs;
        return String(a.name || "").localeCompare(String(b.name || ""));
      });
      return opts;
    }

    function loadOptions() {
      var isChild = state.level === "states" || state.level === "counties";
      if (isChild && state.filterIds.length === 0) {
        state.options = [];
        state.loading = false;
        state.highlight = -1;
        renderOptions();
        return;
      }
      var url = metaURL();
      if (!url) {
        state.options = [];
        state.loading = false;
        state.highlight = -1;
        renderOptions();
        return;
      }
      var seq = ++state.fetchSeq;
      state.loading = true;
      renderOptions();
      fetchMeta(url).then(function (recs) {
        if (destroyed || seq !== state.fetchSeq) return;
        state.options = recs || [];
        state.loading = false;
        state.highlight = -1;
        renderOptions();
      }).catch(function () {
        if (destroyed || seq !== state.fetchSeq) return;
        state.options = [];
        state.loading = false;
        state.highlight = -1;
        renderOptions();
      });
    }

    // ── rendering ────────────────────────────────────────────────
    function triggerClass() {
      var base = "relative w-full flex items-center justify-between gap-2 rounded-md border px-3 py-2 text-sm font-medium text-left transition-colors cursor-pointer ";
      if (state.active) {
        return base + "border-blue-500 dark:border-blue-500 ring-2 ring-blue-500/30 bg-blue-50/50 dark:bg-blue-900/20 text-gray-900 dark:text-neutral-100";
      }
      return base + "border-gray-300 dark:border-neutral-600 bg-white dark:bg-neutral-800 text-gray-700 dark:text-neutral-200 hover:bg-gray-50 dark:hover:bg-neutral-700";
    }

    function renderTrigger() {
      trigger.className = triggerClass();
      labelSpan.textContent = state.label;
      if (state.selected.length > 0) {
        badge.className = "inline-flex items-center justify-center min-w-[1.4rem] h-5 px-1.5 rounded-full text-xs font-semibold bg-blue-100 dark:bg-blue-900/50 text-blue-700 dark:text-blue-300";
        badge.textContent = String(state.selected.length);
      } else {
        badge.className = "hidden";
        badge.textContent = "";
      }
    }

    function optionButton(rec, index) {
      var btn = el("button", "w-full flex items-center gap-2 px-3 py-2 text-sm text-left text-gray-700 dark:text-neutral-200 transition-colors cursor-pointer");
      btn.type = "button";
      var isSel = state.selected.indexOf(rec.id) !== -1;
      btn.insertAdjacentHTML("beforeend", isSel ? ICONS.check : ICONS.empty);
      btn.appendChild(el("span", "truncate", rec.name));
      if (rec.engtype) {
        btn.appendChild(el(
          "span",
          "ml-auto shrink-0 rounded bg-gray-100 dark:bg-neutral-700 px-1.5 py-0.5 text-[10px] font-medium uppercase tracking-wide text-gray-500 dark:text-neutral-400",
          rec.engtype
        ));
      }
      btn.addEventListener("mousemove", function () {
        if (state.highlight !== index) {
          state.highlight = index;
          applyHighlight();
        }
      });
      btn.addEventListener("click", function (e) {
        e.stopPropagation();
        sendEvent("picker-toggle", { id: rec.id });
      });
      return btn;
    }

    function renderOptions() {
      list.textContent = "";
      optionButtons = [];

      if (state.loading) {
        list.appendChild(el("p", "px-3 py-2 text-sm text-gray-500 dark:text-neutral-400", "Loading…"));
        return;
      }

      var opts = visibleOptions();
      if (opts.length === 0) {
        list.appendChild(el("p", "px-3 py-2 text-sm text-gray-500 dark:text-neutral-400", state.emptyText));
        return;
      }

      var shown = opts.slice(0, MAX_OPTIONS);
      shown.forEach(function (rec, i) {
        var btn = optionButton(rec, i);
        optionButtons.push(btn);
        list.appendChild(btn);
      });
      if (opts.length > shown.length) {
        list.appendChild(el(
          "p",
          "px-3 py-2 text-xs text-gray-400 dark:text-neutral-500",
          "Showing " + shown.length + " of " + opts.length + " — refine your search"
        ));
      }
      applyHighlight();
    }

    function applyHighlight() {
      for (var i = 0; i < optionButtons.length; i++) {
        var on = i === state.highlight;
        optionButtons[i].classList.toggle("bg-gray-50", on);
        optionButtons[i].classList.toggle("dark:bg-neutral-700", on);
      }
      if (state.highlight >= 0 && optionButtons[state.highlight]) {
        optionButtons[state.highlight].scrollIntoView({ block: "nearest" });
      }
    }

    function moveHighlight(delta) {
      var n = optionButtons.length;
      if (n === 0) { state.highlight = -1; return; }
      if (state.highlight < 0) {
        state.highlight = delta > 0 ? 0 : n - 1;
      } else {
        state.highlight = (state.highlight + delta + n) % n;
      }
      applyHighlight();
    }

    // ── open / close ─────────────────────────────────────────────
    function openDropdown() {
      sendEvent("picker-focus", {});
      if (!state.open) {
        state.open = true;
        state.query = "";
        if (search) search.value = "";
        state.highlight = -1;
        render();
        loadOptions();
      }
      if (search) search.focus();
    }

    function closeDropdown(restoreFocus) {
      if (!state.open) return;
      state.open = false;
      state.highlight = -1;
      render();
      if (restoreFocus && trigger) trigger.focus();
    }

    function render() {
      renderTrigger();
      dropdown.style.display = state.open ? "block" : "none";
      root.style.zIndex = state.open ? "50" : "";
      if (state.open) renderOptions();
    }

    // ── events ───────────────────────────────────────────────────
    trigger.addEventListener("click", function () {
      if (state.open) closeDropdown(false);
      else openDropdown();
    });
    trigger.addEventListener("focus", function () {
      // Tab/focus into the picker also marks it active (map level).
      sendEvent("picker-focus", {});
    });
    trigger.addEventListener("keydown", function (e) {
      var k = e.key;
      if (k === "ArrowDown" || k === "ArrowUp" || k === "Enter" || k === " ") {
        e.preventDefault();
        if (!state.open) openDropdown();
        else if (k === "Enter" || k === " ") {
          // toggle the highlighted option if any
          if (state.highlight >= 0 && optionButtons[state.highlight]) {
            optionButtons[state.highlight].click();
          }
        }
      } else if (k === "Escape") {
        closeDropdown(true);
      }
    });

    search.addEventListener("input", function () {
      state.query = search.value;
      state.highlight = -1;
      renderOptions();
    });
    search.addEventListener("keydown", function (e) {
      var k = e.key;
      if (k === "ArrowDown") { e.preventDefault(); moveHighlight(1); }
      else if (k === "ArrowUp") { e.preventDefault(); moveHighlight(-1); }
      else if (k === "Enter") {
        e.preventDefault();
        if (state.highlight >= 0 && optionButtons[state.highlight]) {
          optionButtons[state.highlight].click();
        }
      } else if (k === "Escape") { e.preventDefault(); closeDropdown(true); }
      else if (k === "Tab") { closeDropdown(true); }
    });

    // Close on unhover rather than on focus loss.
    root.addEventListener("mouseleave", function () {
      closeDropdown(false);
    });

    render();

    return {
      update: function (values) {
        var needOptions = false;

        if ("level" in values) state.level = values.level || "countries";
        if ("label" in values) state.label = values.label == null ? "" : String(values.label);
        if ("active" in values) state.active = !!values.active;
        if ("metaUrl" in values) state.metaUrl = values.metaUrl || "";
        if ("emptyText" in values) state.emptyText = values.emptyText || "No units available";
        if ("selected" in values) state.selected = toArray(values.selected);

        if ("filterField" in values) {
          var nf = values.filterField == null ? "" : String(values.filterField);
          if (nf !== state.filterField) { state.filterField = nf; needOptions = true; }
        }
        if ("filterIds" in values) {
          var ni = toArray(values.filterIds);
          var niKey = ni.slice().sort().join("|");
          var ciKey = state.filterIds.slice().sort().join("|");
          if (niKey !== ciKey) { state.filterIds = ni; needOptions = true; }
        }

        renderTrigger();
        if (state.open) {
          if (needOptions) loadOptions();
          else renderOptions();
        }
      },
      destroy: function () {
        destroyed = true;
      }
    };
  });
})();
