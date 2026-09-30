# Watermarks are layers whose grobs escape the panel at draw time: they climb
# from the panel viewport up to the plot's gtable viewport ("layout") and draw
# relative to the whole figure. That keeps them independent of scales, coords
# and facets, and they are drawn once (from the first panel only).

watermark_layer <- function(geom, spec) {
  ggplot2::layer(
    geom = geom,
    stat = ggplot2::StatIdentity,
    position = ggplot2::PositionIdentity,
    data = data.frame(x = NA),
    mapping = ggplot2::aes(),
    inherit.aes = FALSE,
    show.legend = FALSE,
    params = list(spec = spec)
  )
}

watermark_geom <- function(class, grob_class) {
  ggplot2::ggproto(
    class, ggplot2::Geom,
    draw_panel = function(data, panel_params, coord, spec) {
      if (!identical(as.integer(data$PANEL[1]), 1L)) {
        return(ggplot2::zeroGrob())
      }
      grid::gTree(spec = spec, cl = grob_class)
    }
  )
}

# Run `draw` in the whole-plot viewport, then return to where grid was.
in_plot_viewport <- function(draw) {
  path <- grid::current.vpPath()
  if (is.null(path)) return(draw())
  names <- strsplit(as.character(path), "::", fixed = TRUE)[[1]]
  top <- which(names == "layout")
  if (length(top) == 0L || max(top) == length(names)) return(draw())
  top <- max(top)
  below <- names[(top + 1L):length(names)]
  grid::upViewport(length(below))
  on.exit(grid::downViewport(do.call(grid::vpPath, as.list(below))))
  draw()
}

bottom_margin <- function(pt) {
  if (utils::packageVersion("ggplot2") >= "4.0.0") {
    margin_part <- get("margin_part", envir = asNamespace("ggplot2"))
    margin_part(b = pt)
  } else {
    ggplot2::margin(5.5, 5.5, pt, 5.5)
  }
}

# Arguments that would draw a mark nobody can read back are errors, not
# silent no-ops: fully transparent dots, dots of no size, no colour.
check_mark_style <- function(colour, alpha, size) {
  rgba <- tryCatch(grDevices::col2rgb(colour, alpha = TRUE), error = function(e) NULL)
  if (length(colour) != 1L || is.na(colour) || is.null(rgba) || rgba[4, 1] == 0) {
    stop("`colour` must be a single visible colour, e.g. \"grey30\" or \"white\".",
         call. = FALSE)
  }
  if (!is.numeric(alpha) || length(alpha) != 1L || !is.finite(alpha) ||
      alpha <= 0 || alpha > 1) {
    stop("`alpha` must be a number greater than 0 and at most 1.", call. = FALSE)
  }
  if (!is.numeric(size) || length(size) != 1L || !is.finite(size) || size <= 0) {
    stop("`size` must be a positive number (a dot diameter in mm).", call. = FALSE)
  }
  invisible(TRUE)
}
