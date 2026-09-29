#' Invisible, machine-readable dot watermark
#'
#' Adds a row of faint dots along the bottom margin of the plot that encodes
#' `id`. The code survives screenshots, JPEG compression and moderate
#' rescaling, and is read back with [extract_watermark()].
#'
#' The dots are drawn relative to the whole figure, not the data, so the
#' watermark never touches your scales, coordinate system or facets. The plot's
#' bottom margin is widened to 14pt to make room; a complete theme added *after*
#' the watermark (e.g. `+ theme_minimal()`) resets that margin, so add themes
#' first.
#'
#' The code is framed with sync patterns, a header and a 32-bit checksum, so a
#' decode either returns the exact ID or nothing. IDs made only of the
#' characters [wm_id()] uses are packed at 5 bits per character, so they fit
#' in fewer, larger dots than other strings of the same length.
#'
#' @param id The ID to embed: a string of at most 16 bytes. Shorter IDs are
#'   more robust; [wm_id()] makes 8-character ones.
#' @param colour Dot colour. Use a light colour on dark plot backgrounds.
#' @param alpha Dot opacity. Lower is less visible but less robust to heavy
#'   compression.
#' @param size Maximum dot diameter in mm. Dots shrink automatically when the
#'   plot is too narrow to fit them at this size.
#'
#' @return A list of ggplot2 components, to be added to a plot with `+`.
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
watermark_dots <- function(id, colour = "grey30", alpha = 0.15, size = 1.2) {
  spec <- list(
    bits = encode_bits(id),
    colour = colour,
    alpha = alpha,
    size = size
  )
  list(
    watermark_layer(GeomWatermarkDots, spec),
    ggplot2::theme(plot.margin = bottom_margin(14))
  )
}

#' @rdname watermark_dots
#' @param plot A ggplot object.
#' @param ... Passed to `watermark_dots()`.
#' @export
add_watermark <- function(plot, id, ...) {
  plot + watermark_dots(id, ...)
}

GeomWatermarkDots <- watermark_geom("GeomWatermarkDots", "watermark_dots_grob")

# Horizontal inset of the first/last dot, as a fraction of plot width, and the
# height of the dot row above the bottom edge of the figure.
dots_inset <- 0.04
dots_offset_mm <- 2.4
# Height of the bottom strip reserved for the dots; visible text stays above.
dots_band_mm <- 4.2

#' @export
drawDetails.watermark_dots_grob <- function(x, recording) {
  spec <- x$spec
  in_plot_viewport(function() {
    n <- length(spec$bits)
    width_mm <- grid::convertWidth(grid::unit(1, "npc"), "mm", valueOnly = TRUE)
    pitch_mm <- width_mm * (1 - 2 * dots_inset) / (n - 1)
    radius <- min(spec$size / 2, pitch_mm * 0.4)
    xs <- seq(dots_inset, 1 - dots_inset, length.out = n)[spec$bits == 1L]
    grid::grid.circle(
      x = grid::unit(xs, "npc"),
      y = grid::unit(dots_offset_mm, "mm"),
      r = grid::unit(radius, "mm"),
      gp = grid::gpar(
        fill = scales::alpha(spec$colour, spec$alpha),
        col = NA
      )
    )
  })
}
