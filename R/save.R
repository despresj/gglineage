#' Save a plot with a dot watermark and embedded provenance metadata
#'
#' A drop-in replacement for [ggplot2::ggsave()] that stamps the plot with
#' [watermark_dots()] and, for PNG files, also writes provenance fields into
#' the file's `tEXt` metadata chunks. The dots survive screenshots and
#' recompression; the metadata is lossless and can carry much more (a UUID,
#' a git commit, a script path) but is lost when the image is screenshotted or
#' re-encoded. Using both gives you the rich record when the original file is
#' shared and the short ID when it isn't.
#'
#' @param filename File to create, as in [ggplot2::ggsave()].
#' @param plot Plot to save; defaults to the last plot displayed.
#' @param id ID to embed. Defaults to a fresh [wm_id()].
#' @param metadata A named list of extra fields to store in the PNG metadata,
#'   e.g. `list(commit = "a1b2c3d", script = "analysis/fig2.R")`.
#' @param dots If `FALSE`, skip the dot code and only write metadata.
#' @param ... Passed to [ggplot2::ggsave()] (`width`, `height`, `dpi`, ...).
#'
#' @return The ID, invisibly.
#' @seealso [read_watermark_metadata()], [extract_watermark()].
#' @export
#' @examples
#' library(ggplot2)
#' p <- ggplot(mtcars, aes(wt, mpg)) + geom_point()
#'
#' file <- tempfile(fileext = ".png")
#' id <- ggsave_watermark(file, p, metadata = list(script = "fig1.R"),
#'                        width = 6, height = 4, dpi = 150)
#'
#' extract_watermark(file)
#' read_watermark_metadata(file)
ggsave_watermark <- function(filename,
                             plot = ggplot2::last_plot(),
                             id = wm_id(),
                             metadata = list(),
                             dots = TRUE,
                             ...) {
  check_id(id)
  if (length(metadata) > 0L &&
      (is.null(names(metadata)) || any(!nzchar(names(metadata))))) {
    stop("`metadata` must be a named list.", call. = FALSE)
  }

  to_save <- if (dots) plot + watermark_dots(id) else plot
  ggplot2::ggsave(filename, to_save, ...)

  if (is_png(filename)) {
    write_png_metadata(filename, c(
      list(
        id = id,
        created = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
        title = plot_title(plot),
        software = sprintf(
          "R %s; ggplot2 %s; gglineage %s",
          getRversion(), utils::packageVersion("ggplot2"),
          utils::packageVersion("gglineage")
        )
      ),
      metadata
    ))
  } else if (length(metadata) > 0L) {
    warning("Metadata is only embedded in PNG files; saved dots only.",
            call. = FALSE)
  }
  invisible(id)
}

#' Read provenance metadata written by ggsave_watermark()
#'
#' @param file Path to a PNG file.
#' @return A named list of metadata fields (`id`, `created`, `title`,
#'   `software`, plus anything passed via `metadata`), or an empty list if the
#'   file carries none, e.g. because it was screenshotted or re-encoded.
#' @export
#' @examples
#' library(ggplot2)
#' file <- tempfile(fileext = ".png")
#' ggsave_watermark(file, ggplot(mtcars, aes(wt, mpg)) + geom_point(),
#'                  width = 4, height = 3, dpi = 100)
#' read_watermark_metadata(file)
read_watermark_metadata <- function(file) {
  if (!file.exists(file)) stop("File not found: ", file, call. = FALSE)
  if (!is_png(file)) return(list())
  text <- attr(png::readPNG(file, info = TRUE), "info")$text
  keys <- names(text) %||% character()
  # Files written before the package was renamed use the old prefix.
  for (prefix in c(metadata_prefix, legacy_metadata_prefix)) {
    ours <- startsWith(keys, prefix)
    if (any(ours)) {
      return(as.list(stats::setNames(
        unname(text[ours]),
        substring(keys[ours], nchar(prefix) + 1L)
      )))
    }
  }
  list()
}

metadata_prefix <- "gglineage:"
legacy_metadata_prefix <- "watermark:"

is_png <- function(file) {
  identical(readBin(file, "raw", 4L), as.raw(c(0x89, 0x50, 0x4e, 0x47)))
}

write_png_metadata <- function(file, fields) {
  fields <- fields[!vapply(fields, is.null, logical(1))]
  text <- vapply(fields, function(x) paste(as.character(x), collapse = " "),
                 character(1))
  names(text) <- paste0(metadata_prefix, names(fields))

  img <- png::readPNG(file, info = TRUE)
  info <- attr(img, "info")
  existing <- info$text
  if (!is.null(existing)) {
    existing <- existing[!startsWith(names(existing), metadata_prefix) &
                           !startsWith(names(existing), legacy_metadata_prefix)]
  }
  png::writePNG(img, file, dpi = info$dpi, text = c(existing, text))
}

plot_title <- function(plot) {
  title <- tryCatch(plot$labels$title, error = function(e) NULL)
  if (is.character(title) && length(title) == 1L) title else NULL
}
