#' Visible text watermark
#'
#' Stamps a label such as "DRAFT" or "CONFIDENTIAL" over the whole figure, as
#' a large diagonal stamp, a repeating tile, or a small corner mark. Like
#' [watermark_dots()], it is drawn relative to the figure and never affects
#' scales, coordinates or facets.
#'
#' Text never enters the bottom few millimetres of the figure, which are
#' reserved for the dot code, so visible and invisible watermarks can be
#' combined freely.
#'
#' @param label Text to stamp.
#' @param position One of `"center"` (one large diagonal stamp sized to the
#'   figure), `"tile"` (a repeating diagonal pattern), or a corner:
#'   `"bottomright"`, `"bottomleft"`, `"topright"`, `"topleft"`.
#' @param colour,alpha Text colour and opacity.
#' @param size Font size in points. `NULL` picks a size suited to `position`;
#'   for `"center"` the stamp is scaled to span most of the figure.
#' @param angle Rotation in degrees. `NULL` uses the figure diagonal for
#'   `"center"`, 30 for `"tile"` and 0 for corners.
#' @param fontface,family Font face and family.
#'
#' @return A ggplot2 layer, to be added to a plot with `+`.
#' @export
#' @examples
#' library(ggplot2)
#' p <- ggplot(mtcars, aes(wt, mpg)) + geom_point()
#'
#' p + watermark_text("DRAFT")
#' p + watermark_text("INTERNAL", position = "tile")
#' p + watermark_text("github.com/you/analysis", position = "bottomright")
watermark_text <- function(label = "DRAFT",
                           position = c("center", "tile", "bottomright",
                                        "bottomleft", "topright", "topleft"),
                           colour = "grey50",
                           alpha = NULL,
                           size = NULL,
                           angle = NULL,
                           fontface = "bold",
                           family = "") {
  if (!is.character(label) || length(label) != 1L || is.na(label)) {
    stop("`label` must be a single string.", call. = FALSE)
  }
  position <- match.arg(position)
  corner <- !position %in% c("center", "tile")
  spec <- list(
    label = label,
    position = position,
    colour = colour,
    alpha = alpha %||% if (corner) 0.7 else 0.2,
    size = size %||% switch(position, center = NA, tile = 14, 9),
    angle = angle,
    fontface = fontface,
    family = family
  )
  watermark_layer(GeomWatermarkText, spec)
}

GeomWatermarkText <- watermark_geom("GeomWatermarkText", "watermark_text_grob")

#' @export
drawDetails.watermark_text_grob <- function(x, recording) {
  spec <- x$spec
  in_plot_viewport(function() {
    # Keep clear of the dot band along the bottom edge.
    grid::pushViewport(grid::viewport(
      y = grid::unit(dots_band_mm, "mm"),
      height = grid::unit(1, "npc") - grid::unit(dots_band_mm, "mm"),
      just = "bottom",
      clip = "on"
    ))
    on.exit(grid::popViewport())
    w <- grid::convertWidth(grid::unit(1, "npc"), "mm", valueOnly = TRUE)
    h <- grid::convertHeight(grid::unit(1, "npc"), "mm", valueOnly = TRUE)
    gp <- function(fontsize) {
      grid::gpar(
        col = scales::alpha(spec$colour, spec$alpha),
        fontsize = fontsize,
        fontface = spec$fontface,
        fontfamily = spec$family
      )
    }
    text_mm <- function(fontsize) {
      grob <- grid::textGrob(spec$label, gp = gp(fontsize))
      c(
        grid::convertWidth(grid::grobWidth(grob), "mm", valueOnly = TRUE),
        grid::convertHeight(grid::grobHeight(grob), "mm", valueOnly = TRUE)
      )
    }

    switch(spec$position,
      center = {
        angle <- spec$angle %||% (atan2(h, w) * 180 / pi)
        size <- spec$size
        if (is.na(size)) {
          # Largest size whose rotated bounding box fits in 85% of the figure.
          ext <- text_mm(100)
          th <- angle * pi / 180
          box_w <- ext[1] * abs(cos(th)) + ext[2] * abs(sin(th))
          box_h <- ext[1] * abs(sin(th)) + ext[2] * abs(cos(th))
          size <- 100 * 0.85 * min(w / box_w, h / box_h)
        }
        grid::grid.text(spec$label, rot = angle, gp = gp(size))
      },
      tile = {
        angle <- spec$angle %||% 30
        ext <- text_mm(spec$size)
        dx <- (ext[1] + 15) / w
        dy <- (ext[2] * 5) / h
        grid_pts <- expand.grid(x = seq(-0.1, 1.1, by = dx), row = seq(0, 1.1 / dy))
        grid_pts$row <- grid_pts$row + 0.5
        grid_pts$x <- grid_pts$x + (grid_pts$row %% 2) * dx / 2
        grid::grid.text(
          spec$label,
          x = grid::unit(grid_pts$x, "npc"),
          y = grid::unit(grid_pts$row * dy, "npc"),
          rot = angle,
          gp = gp(spec$size)
        )
      },
      {
        right <- grepl("right", spec$position)
        top <- grepl("top", spec$position)
        pad <- grid::unit(1.5, "mm")
        grid::grid.text(
          spec$label,
          x = if (right) grid::unit(1, "npc") - pad else pad,
          y = if (top) grid::unit(1, "npc") - pad else pad,
          hjust = if (right) 1 else 0,
          vjust = if (top) 1 else 0,
          rot = spec$angle %||% 0,
          gp = gp(spec$size)
        )
      }
    )
  })
}

`%||%` <- function(x, y) if (is.null(x)) y else x
