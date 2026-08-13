<!-- agents: this is a design goals statement for the main section of the app -->

# Maplibre GL admin polygon picker

This should become the main app section and replace the `mtcars` explorer
currently used. The main goal is to display a maplibre map by using a custom
`iridWidget`. The map uses 2/3 of the screen. At the left side, a panel displays
three select input 'pickers', all three using the same irid component. Each
picker displays administrative units, the first displays countries (admin 0);
the second displays states (admin 1) **within** selected countries, nothing if
there's no selection in the country level; the third does as the second for
counties (admin 2).

Use `rnaturalearth` package for easy access to polygons and admin data.

Even though each 'picker' uses the same irid component, their behaviour and
interaction with the map differs:

- country level picker: has all world countries already loaded. Map displays the
  corresponding polygon for each selected country, removes them as countries are
  removed from selection. Clicking a polygon removes it from the selection.
- state/county pickers: loads every polygon within selected countries into the
  map, with `selected = FALSE` initial state. Not selected is reflected
  graphically by a transparent polygon fill, only the borders are visible.
  Clicking on a polygon toggles it's `selected` state. selected polygons have
  colored fill.

# state management

This idea requires keeping app state, use for this irid's `reactiveStore`. Make
a different store than the one used for authentication. We need to keep track of
the active admin level (country/state/county) based on the select input 'focus'
and the current selection for each level. The same state can also hold the
polygons with the 'selected' state column, but beware that countries must be
handled differently, we don't want to load the whole countries table with no
reason.

# other outputs

Below the picker's panel, the app displays the list of selected admin units for
each level.
