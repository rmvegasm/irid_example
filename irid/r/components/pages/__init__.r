#' r/components/pages — Complete page components
#'
#' Fully composed pages using layouts/ and intermediate components.
#' App code should only compose the app from these components instead
#' of defining them inline in `app.r`.
#'
#' @md
#' @name pages
#' @export
box::use(
  ./login[login_page],
  ./mtcars[mtcars_explorer],
  ./admin_picker_page[admin_picker_page],
)
