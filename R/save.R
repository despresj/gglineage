#' Save a plot with a dot watermark and embedded provenance metadata
#'
#' A replacement for [ggplot2::ggsave()] that stamps the plot with
#' [watermark_dots()] and, for PNG files, also writes provenance fields into
#' the file's `tEXt` metadata chunks. The dots survive screenshots and
#' recompression; the metadata is lossless and can carry much more (a UUID,
#' a git commit, a script path) but is lost when the image is screenshotted or
#' re-encoded. Using both gives you the rich record when the original file is
#' shared and the short ID when it isn't.
#'
#' @param filename File to create, as in [ggplot2::ggsave()].
#' @param plot Plot to save; defaults to the last plot displayed.
#' @param id ID to embed: text of at most 16 bytes or a UUID (see
#'   [watermark_dots()]). Defaults to the ID the plot already carries, if it
#'   has a [watermark_dots()] or [watermark_tiles()] mark, and otherwise to a
#'   fresh [wm_id()]. A different ID from the one the plot carries is an
#'   error, so the file's metadata and its dots always name the same ID. This
#'   is the third argument, where [ggplot2::ggsave()] has `device`, so pass
#'   `device` and the other `ggsave()` arguments by name.
#' @param metadata A named list of extra fields to store in the PNG metadata,
#'   e.g. `list(commit = "a1b2c3d", script = "analysis/fig2.R")`. Each field
#'   is an atomic vector (stored as text, elements separated by spaces), each
#'   name is used once and is at most 69 bytes (PNG limits keywords to 79,
#'   including the package's prefix). The names `id`, `created`, `title` and
#'   `software` are reserved. Problems are reported before anything is saved.
#' @param dots If `FALSE`, skip the dot code and only write metadata.
#' @param ... Passed to [ggplot2::ggsave()] (`width`, `height`, `dpi`, ...).
#'
#' @return The ID (not the file path, unlike `ggsave()`), invisibly: as
#'   given for text, or in lowercase form for a UUID.
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
                             id = NULL,
                             metadata = list(),
                             dots = TRUE,
                             ...) {
  # A UUID is stored, and returned, in its canonical lowercase form, so the
  # metadata field matches what extract_watermark() reads from the dots.
  carried <- plot_watermark_id(plot)
  id <- check_id(id %||% carried %||% wm_id())
  # Checked whether or not dots are drawn: metadata naming one ID on a figure
  # whose marks carry another would send a lookup to the wrong record.
  if (!is.null(carried) && !identical(carried, id)) stop_two_ids(carried, id)
  check_metadata(metadata)

  to_save <- if (dots) plot + watermark_dots(id) else plot
  # ggsave() returns the path it wrote, which differs from `filename` when
  # `path` is given in `...`.
  saved <- ggplot2::ggsave(filename, to_save, ...)
  if (!is.character(saved) || length(saved) != 1L) {
    dir <- list(...)$path
    saved <- if (is.null(dir)) filename else file.path(dir, filename)
  }

  if (is_png(saved)) {
    write_png_metadata(saved, c(
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

reserved_fields <- c("id", "created", "title", "software")

# Metadata that could not be read back exactly as given is refused before
# anything is saved: libpng truncates long keywords (with only a warning),
# repeated names read back ambiguously, and lists or functions have no text
# form to store.
check_metadata <- function(metadata) {
  if (!is.list(metadata)) stop("`metadata` must be a named list.", call. = FALSE)
  if (length(metadata) == 0L) return(invisible())
  keys <- names(metadata)
  if (is.null(keys) || anyNA(keys) || any(!nzchar(keys))) {
    stop("`metadata` must be a named list.", call. = FALSE)
  }
  clash <- intersect(keys, reserved_fields)
  if (length(clash) > 0L) {
    stop("`metadata` can't use the reserved field name",
         if (length(clash) > 1L) "s", " ", paste0("`", clash, "`", collapse = ", "),
         "; these are written by ggsave_watermark() itself.", call. = FALSE)
  }
  dup <- unique(keys[duplicated(keys)])
  if (length(dup) > 0L) {
    stop("`metadata` uses the name", if (length(dup) > 1L) "s", " ",
         paste0("`", dup, "`", collapse = ", "), " more than once.", call. = FALSE)
  }
  long <- keys[nchar(enc2utf8(keys), type = "bytes") > max_metadata_key_bytes]
  if (length(long) > 0L) {
    stop("`metadata` names must be at most ", max_metadata_key_bytes, " bytes; ",
         paste0("`", long, "`", collapse = ", "), " is longer.", call. = FALSE)
  }
  bad <- keys[!vapply(metadata, function(x) is.null(x) || is.atomic(x), logical(1))]
  if (length(bad) > 0L) {
    stop("`metadata` fields must be atomic vectors (text, numbers, dates); ",
         paste0("`", bad, "`", collapse = ", "), " is not.", call. = FALSE)
  }
  invisible()
}

# PNG keywords are 1-79 bytes, and ours start with "gglineage:".
max_metadata_key_bytes <- 79L - nchar("gglineage:")

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
