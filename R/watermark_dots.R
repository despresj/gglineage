#' Invisible, machine-readable dot watermark
#'
#' Adds a row of faint dots along the bottom margin of the plot that encodes
#' `id`. The code survives screenshots, JPEG compression and moderate
#' rescaling, and is read back with [extract_watermark()].
#'
#' The dots are drawn relative to the whole figure, not the data, so the
#' watermark never touches your scales, coordinate system or facets. The plot's
#' bottom margin is widened to make room (14pt for a text ID, 20pt for a UUID);
#' a complete theme added *after* the watermark (e.g. `+ theme_minimal()`)
#' resets that margin, so add themes first.
#'
#' Each row is framed with sync patterns, a header and a 32-bit check, so a
#' decode either returns the exact ID or nothing. IDs made only of the
#' characters [wm_id()] uses are packed at 5 bits per character, so they fit
#' in fewer, larger dots than other strings of the same length.
#'
#' @section UUIDs:
#' A UUID in canonical form (`xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`, either
#' case, optionally in braces or with a `urn:uuid:` prefix) is recognised and
#' carried in full: all 128 bits, as two rows of dots, one above the other.
#' [extract_watermark()] returns it lowercase. The letter case of a UUID's
#' hex digits is not part of its value (RFC 9562, section 4), so an
#' uppercase input is not an error, just not preserved. Nothing else is
#' interpreted: the version and variant fields are carried as given.
#'
#' Thirty-two hexadecimal digits without hyphens are *not* treated as a UUID
#' (that could equally be an MD5 hash), and at 32 bytes are too long for a
#' text ID, so they are rejected with a message. Any text of 16 bytes or fewer
#' is carried literally, so no text ID can ever be mistaken for a UUID.
#'
#' Each UUID row has 136 dot positions to a text row's 77-200 (112 for an
#' 8-character `wm_id()`), so a UUID needs more pixel width than an
#' 8-character ID to survive the same JPEG compression. Measured on 7 x 5 in
#' figures (12 trials per width), quality 50 held in every trial down to 400
#' px wide for a UUID and 300 px for an 8-character ID; below that, some
#' decodes return `NULL`. The full table is in the README. These are
#' measurements, not guarantees: the limits vary with the ID and the plot.
#'
#' @section One plot, one ID:
#' A plot carries one ID. Adding `watermark_dots()` or [watermark_tiles()]
#' with a different ID to a plot that already has one is an error, because a
#' figure carrying two IDs could be traced to either. Adding the same ID
#' again changes nothing. The ID belongs to the plot object, so a plot built
#' from a watermarked one (`p + labs(...)`, or `p` given new data) carries the
#' same ID; to give every saved figure its own ID, leave the watermark off the
#' shared plot and add it when saving, with [ggsave_watermark()].
#'
#' @param id The ID to embed: text of at most 16 bytes, or a UUID. Shorter
#'   text is more robust; [wm_id()] makes 8-character IDs and [wm_uuid()]
#'   UUIDs.
#' @param colour Dot colour. Use a light colour on dark plot backgrounds.
#' @param alpha Dot opacity. Lower is less visible but less robust to heavy
#'   compression.
#' @param size Maximum dot diameter in mm. Dots are drawn at 0.8 of their
#'   spacing, up to this size, so on a typical 7-inch figure the spacing sets
#'   the size; the cap matters on wide figures, whose dots would otherwise be
#'   too small to survive being shown small and recompressed.
#'
#' @return An object to add to a plot with `+`; `add_watermark()` returns
#'   the watermarked plot.
#' @seealso [add_watermark()] for a pipe-friendly version,
#'   [ggsave_watermark()] to also embed file metadata.
#' @export
#' @examples
#' library(ggplot2)
#' p <- ggplot(mtcars, aes(wt, mpg)) +
#'   geom_point() +
#'   watermark_dots("RUN-42")
#'
#' file <- tempfile(fileext = ".png")
#' ggsave(file, p, width = 6, height = 4, dpi = 150)
#' extract_watermark(file)
#'
#' # A UUID is carried in full, on two rows of dots.
#' p2 <- ggplot(mtcars, aes(wt, mpg)) +
#'   geom_point() +
#'   watermark_dots("6BA7B810-9DAD-11D1-80B4-00C04FD430C8")
#' ggsave(file, p2, width = 6, height = 4, dpi = 150)
#' extract_watermark(file)
watermark_dots <- function(id, colour = "grey30", alpha = 0.15, size = 2) {
  check_mark_style(colour, alpha, size)
  structure(
    list(
      id = check_id(id),
      rows = encode_rows(id),
      colour = colour,
      alpha = alpha,
      size = size
    ),
    class = "watermark_dots_spec"
  )
}

#' @exportS3Method ggplot2::ggplot_add
ggplot_add.watermark_dots_spec <- function(object, plot, ...) {
  spec <- unclass(object)
  if (!needs_watermark(plot, spec$id, "GeomWatermarkDots")) return(plot)
  plot$layers <- c(plot$layers, list(watermark_layer(GeomWatermarkDots, spec)))
  plot + ggplot2::theme(plot.margin = bottom_margin(dots_margin_pt(length(spec$rows))))
}

#' @rdname watermark_dots
#' @param plot A ggplot object.
#' @param ... Passed to `watermark_dots()`.
#' @export
add_watermark <- function(plot, id, ...) {
  if (!inherits(plot, "ggplot")) {
    stop("`plot` must be a ggplot object.", call. = FALSE)
  }
  plot + watermark_dots(id, ...)
}

GeomWatermarkDots <- watermark_geom("GeomWatermarkDots", "watermark_dots_grob")

# Horizontal inset of the first/last dot, as a fraction of plot width; the
# height of the lowest dot row above the bottom edge of the figure; and the
# spacing between rows when there is more than one.
dots_inset <- 0.04
dots_offset_mm <- 2.4
dots_row_gap_mm <- 2.2
# Height of the bottom strip reserved for the dots; visible text stays above.
# Two rows of dots reach 5.2 mm, plus clearance.
dots_band_mm <- 6.4

# Bottom plot margin that keeps the rows clear of the axis, in points.
dots_margin_pt <- function(n_rows) if (n_rows > 1L) 20 else 14

#' @export
drawDetails.watermark_dots_grob <- function(x, recording) {
  spec <- x$spec
  in_plot_viewport(function() {
    width_mm <- grid::convertWidth(grid::unit(1, "npc"), "mm", valueOnly = TRUE)
    for (i in seq_along(spec$rows)) {
      bits <- spec$rows[[i]]
      n <- length(bits)
      pitch_mm <- width_mm * (1 - 2 * dots_inset) / (n - 1)
      radius <- min(spec$size / 2, pitch_mm * 0.4)
      xs <- seq(dots_inset, 1 - dots_inset, length.out = n)[bits == 1L]
      grid::grid.circle(
        x = grid::unit(xs, "npc"),
        y = grid::unit(dots_offset_mm + (i - 1) * dots_row_gap_mm, "mm"),
        r = grid::unit(radius, "mm"),
        gp = grid::gpar(
          fill = scales::alpha(spec$colour, spec$alpha),
          col = NA
        )
      )
    }
  })
}
