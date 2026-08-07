#' r/components/elements — Atomic UI elements
#'
#' Single-purpose, leaf-level components that do not import from any
#' other component submodule. These are the atoms of the design system.
#'
#' @md
#' @name elements
#' @export
box::use(
  ./alert[alert],
  ./badges[badge],
  ./buttons[btn_primary, btn_secondary, btn_danger],
  ./inputs[
    text_input, password_input, select_input,
    slider_input, checkbox_input
  ],
)
