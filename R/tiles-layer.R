#' Crop-resistant tiled watermark
#'
#' Tiles a faint 12 x 12 grid of dots behind the data in every panel. Each tile
#' carries the whole ID and a CRC-16 checksum, so a crop that keeps enough of
#' the panel still decodes with [extract_watermark()]: about two tiles across
#' in each direction, roughly 70 mm square of open panel at the default pitch.
#' Use it alongside, or instead of, [watermark_dots()] when images may be
#' cropped.
#'
#' Tiles are drawn in the panels, on a lattice anchored to the page, so facets
#' share one continuous pattern. They need open panel between the data: a plot
#' whose data covers the whole panel (such as `geom_raster()`) leaves nothing
#' to read. On a dark panel use `colour = "white"`. At the default 3 mm pitch a
#' tile is 36 mm square, so figures smaller than about 5 x 4 in hold too few
#' tiles; use `pitch = 2, size = 0.7` for those, saved at 150 dpi or more.
#'
#' @param id The ID to embed: a string of at most 12 bytes. [wm_id()] makes
#'   8-character ones.
#' @param colour Dot colour. Use a light colour on dark panel backgrounds.
#' @param alpha Dot opacity.
#' @param size Dot diameter in mm; about a third of `pitch`.
#' @param pitch Spacing between lattice points in mm. A tile is 12 pitches
#'   square.
#' @return An object to add to a ggplot with `+`.
#' @seealso [watermark_dots()] for the margin strip, [extract_watermark()] to
#'   read either back.
#' @export
#' @examples
#' library(ggplot2)
#' p <- ggplot(mtcars, aes(wt, mpg)) +
#'   geom_point() +
#'   watermark_tiles("RUN-42")
#'
#' file <- tempfile(fileext = ".png")
#' ggsave(file, p, width = 6, height = 4, dpi = 150)
#' extract_watermark(file)
watermark_tiles <- function(id, colour = "black", alpha = 0.04, size = 1.05, pitch = 3) {
  structure(
    list(bits = encode_tile(id), colour = colour, alpha = alpha, size = size, pitch = pitch),
    class = "watermark_tiles_spec"
  )
}

#' @exportS3Method ggplot2::ggplot_add
ggplot_add.watermark_tiles_spec <- function(object, plot, ...) {
  plot$layers <- c(list(watermark_layer(GeomWatermarkTiles, unclass(object))), plot$layers)
  plot
}

GeomWatermarkTiles <- ggplot2::ggproto(
  "GeomWatermarkTiles", ggplot2::Geom,
  draw_panel = function(data, panel_params, coord, spec) tiles_grob(spec)
)

tiles_grob <- function(spec) grid::gTree(spec = unclass(spec), cl = "watermark_tiles_grob")

span_index <- function(lo, hi) if (hi >= lo) seq.int(lo, hi) else integer()

tile_cells <- function(x0_mm, y0_mm, w_mm, h_mm, pitch) {
  gx <- span_index(ceiling(x0_mm / pitch - 0.5), floor((x0_mm + w_mm) / pitch - 0.5))
  gy <- span_index(ceiling(y0_mm / pitch - 0.5), floor((y0_mm + h_mm) / pitch - 0.5))
  cells <- expand.grid(gx = gx, gy = gy)
  cells$x_mm <- (cells$gx + 0.5) * pitch
  cells$y_mm <- (cells$gy + 0.5) * pitch
  cells$cell <- as.integer(((-cells$gy - 1L) %% 12L) * 12L + cells$gx %% 12L)
  cells
}

#' @exportS3Method grid::makeContent
makeContent.watermark_tiles_grob <- function(x) {
  s <- x$spec
  w <- grid::convertWidth(grid::unit(1, "npc"), "mm", valueOnly = TRUE)
  h <- grid::convertHeight(grid::unit(1, "npc"), "mm", valueOnly = TRUE)
  origin <- grid::deviceLoc(grid::unit(0, "npc"), grid::unit(0, "npc"), valueOnly = TRUE)
  x0 <- origin$x * 25.4
  y0 <- origin$y * 25.4
  cells <- tile_cells(x0, y0, w, h, s$pitch)
  cells <- cells[s$bits[cells$cell + 1L] == 1L, , drop = FALSE]
  dots <- if (nrow(cells) > 0L) {
    grid::circleGrob(
      x = grid::unit(cells$x_mm - x0, "mm"), y = grid::unit(cells$y_mm - y0, "mm"),
      r = grid::unit(s$size / 2, "mm"),
      gp = grid::gpar(fill = s$colour, col = NA, alpha = s$alpha)
    )
  } else {
    grid::nullGrob()
  }
  grid::setChildren(x, grid::gList(dots))
}
