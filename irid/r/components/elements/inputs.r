#' r/components/inputs — Form inputs with irid reactive bindings
#'
#' Form input components that wrap HTML `<input>`, `<select>`, and
#' `<textarea>` elements with irid's reactive binding conventions.
#'
#' In irid, inputs are "controlled" — a reactive value drives the
#' input's current value, and user interaction writes back through
#' an event handler. This is analogous to controlled inputs in
#' Solid/React (value + onChange pattern).
#'
#' In irid:
#' ```r
#' text_input(value = reactiveProxy(get = rv, set = \(v) rv(v)))
#' ```
#'
#' @md
#' @name inputs
box::use(
  shiny[tags],
  stats[setNames],
)

#' Text input with irid reactive binding
#'
#' @param id Element ID (auto-generated if NULL).
#' @param value A reactive value or reactiveProxy for two-way binding.
#'   Pass a plain string for a static default.
#' @param label Optional label text.
#' @param placeholder Placeholder text.
#' @param type Input type ("text", "email", "password", "number", etc.).
#' @param class Additional CSS classes.
#' @param ... Additional attributes passed to `<input>`.
#' @return A shiny.tag `<input>` element.
#' @export
text_input <- function(id = NULL, value = "", label = NULL,
                       placeholder = "", type = "text",
                       class = "", ...) {
  input <- tags$input(
    id = id,
    type = type,
    value = if (is.function(value)) value else value,
    placeholder = placeholder,
    class = paste(
      "block w-full rounded-md border border-gray-300 dark:border-neutral-600 px-3 py-2 text-sm",
      "bg-white dark:bg-neutral-800 text-gray-900 dark:text-neutral-100",
      "shadow-sm placeholder:text-gray-400 dark:placeholder:text-neutral-500 focus:border-blue-500",
      "focus:outline-none focus:ring-1 focus:ring-blue-500",
      "disabled:cursor-not-allowed disabled:bg-gray-50 dark:disabled:bg-neutral-800 disabled:text-gray-500 dark:disabled:text-neutral-400",
      class
    ),
    ...
  )

  if (!is.null(label)) {
    tags$div(
      class = "space-y-1",
      tags$label(
        class = "block text-sm font-medium text-gray-700 dark:text-neutral-300",
        label
      ),
      input
    )
  } else {
    input
  }
}

#' Password input (wraps text_input with type="password")
#'
#' @inheritParams text_input
#' @export
password_input <- function(id = NULL, value = "", label = NULL,
                           placeholder = "Enter password", class = "", ...) {
  text_input(
    id = id, value = value, label = label,
    placeholder = placeholder, type = "password",
    class = class, ...
  )
}

#' Select / dropdown input
#'
#' @param id Element ID.
#' @param value Reactive value for the selected option.
#' @param label Optional label.
#' @param choices Named character vector (name = display, value = option value)
#'   or a plain character vector.
#' @param class Additional CSS classes.
#' @param ... Additional attributes.
#' @return A shiny.tag `<select>` element.
#' @export
select_input <- function(id = NULL, value = "", label = NULL,
                         choices = character(), class = "", ...) {
  # Normalise choices to a named list
  if (is.null(names(choices))) {
    choices <- setNames(choices, choices)
  }

  select <- tags$select(
    id = id,
    value = if (is.function(value)) value else value,
    class = paste(
      "block w-full rounded-md border border-gray-300 dark:border-neutral-600 px-3 py-2 text-sm",
      "bg-white dark:bg-neutral-800 text-gray-900 dark:text-neutral-100",
      "shadow-sm focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500",
      "disabled:cursor-not-allowed disabled:bg-gray-50 dark:disabled:bg-neutral-800",
      class
    ),
    ...,
    lapply(names(choices), function(nm) {
      tags$option(value = choices[[nm]], nm)
    })
  )

  if (!is.null(label)) {
    tags$div(
      class = "space-y-1",
      tags$label(class = "block text-sm font-medium text-gray-700 dark:text-neutral-300", label),
      select
    )
  } else {
    select
  }
}

#' Range / slider input
#'
#' @param id Element ID.
#' @param value Reactive value.
#' @param label Optional label.
#' @param min Minimum value.
#' @param max Maximum value.
#' @param step Step size.
#' @param class Additional CSS classes.
#' @export
slider_input <- function(id = NULL, value = 50, label = NULL,
                         min = 0, max = 100, step = 1, class = "") {
  input <- tags$input(
    id = id,
    type = "range",
    value = if (is.function(value)) value else value,
    min = min, max = max, step = step,
    class = paste(
      "w-full h-2 bg-gray-200 dark:bg-neutral-700 rounded-lg appearance-none cursor-pointer",
      "accent-blue-600 dark:accent-blue-500",
      class
    )
  )

  if (!is.null(label)) {
    tags$div(
      class = "space-y-1",
      tags$label(class = "block text-sm font-medium text-gray-700 dark:text-neutral-300", label),
      input
    )
  } else {
    input
  }
}

#' Checkbox input
#'
#' @param id Element ID.
#' @param value Reactive value (TRUE/FALSE).
#' @param label Label text shown next to the checkbox.
#' @param class Additional CSS classes.
#' @export
checkbox_input <- function(id = NULL, value = FALSE, label = NULL, class = "") {
  checkbox <- tags$input(
    id = id,
    type = "checkbox",
    checked = if (is.function(value)) value else value,
    class = paste(
      "h-4 w-4 rounded border-gray-300 dark:border-neutral-600 text-blue-600",
      "focus:ring-blue-500",
      class
    )
  )

  if (!is.null(label)) {
    tags$label(
      class = "inline-flex items-center gap-2 text-sm text-gray-700 dark:text-neutral-300 cursor-pointer",
      checkbox,
      label
    )
  } else {
    checkbox
  }
}
