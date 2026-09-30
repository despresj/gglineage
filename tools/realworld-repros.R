# Minimal reproductions of the decoder limits found by
# tools/realworld-hammer.R, in pure R (no external tools), so they can be
# re-run while fixing R/extract.R and R/tiles-decode.R.
#
# Usage (from the package root): Rscript tools/realworld-repros.R

suppressPackageStartupMessages({
  library(ggplot2)
  pkgload::load_all(".", quiet = TRUE, helpers = FALSE)
})
source("tests/testthat/helper-transforms.R")

timed <- function(label, expr) {
  t <- system.time(v <- expr)[["elapsed"]]
  cat(sprintf("%-58s %6.2fs  %s\n", label, t, if (is.null(v)) "NULL" else v))
}

# 1. A chart that is a small part of a wide screenshot. The chart's pixels
#    are identical in every row below; only the blank canvas to its right
#    grows. The strip decoder's background window is a fixed fraction of the
#    *image* width (background_window(), R/extract.R), so once the chart is
#    less than roughly a third of the image the strip is no longer found.
#    Headless Chrome hits this with a 360-480 px chart on a 1280 px page, or
#    any chart under ~1/3 of a retina screenshot.
cat("\n1. Strip: 720 px chart on a white canvas of growing width\n")
img <- render_plot(ggplot(mtcars, aes(wt, mpg)) + geom_point() +
                     watermark_dots("K7Q2M9XD"))
chart <- tf_resize_to_width(img, 720)
on_canvas <- function(chart, width) {
  out <- array(1, c(nrow(chart) + 100, width, 3))
  out[50 + seq_len(nrow(chart)), 48 + seq_len(ncol(chart)), ] <- chart
  out
}
for (w in c(816, 1280, 1600, 2000, 2100, 2200, 2300, 2400, 2560)) {
  timed(sprintf("720 px chart in %d px canvas (%.2f of width)", w, 720 / w),
        extract_watermark(on_canvas(chart, w)))
}
chart_full <- img
for (w in c(2800, 3000, 3200, 3600)) {
  timed(sprintf("1050 px chart in %d px canvas (%.2f of width)", w, 1050 / w),
        extract_watermark(on_canvas(chart_full, w)))
}

# 2. Tiles on a facet_grid() whose panels are each smaller than ~70 mm.
#    Lossless, uncropped: the panels together cover 176 x 127 mm, but each is
#    ~50 x 42 mm, and the tiles never decode.
cat("\n2. Tiles on facets\n")
facets <- ggplot(mpg, aes(displ, hwy)) + geom_point() + facet_grid(drv ~ cyl)
timed("facet_grid 3x4, 9x6 in @150 dpi, tiles", extract_watermark(
  render_plot(facets + watermark_tiles("RUN-42"), width = 9, height = 6)))
timed("facet_wrap 1x2, 9x5 in @150 dpi, tiles", extract_watermark(
  render_plot(ggplot(mpg, aes(displ, hwy)) + geom_point() + facet_wrap(~year) +
                watermark_tiles("RUN-42"), width = 9, height = 5)))

# 2b. Tiles, lossless and uncropped, on an open 184 x 101 mm panel: a
#     theme_minimal() date line chart with 5-year breaks. Fails for "RUN-42"
#     but not for "K7Q2M9XD", and not with default breaks or theme_grey().
cat("\n2b. Tiles on a minimal date line chart (lossless)\n")
dates <- ggplot(economics, aes(date, unemploy)) + geom_line() +
  scale_x_date(date_breaks = "5 years", date_labels = "%Y") + theme_minimal()
for (id in c("RUN-42", "K7Q2M9XD")) {
  timed(sprintf("dates, theme_minimal, 5y breaks, 8x4.5 in, tiles %s", id),
        extract_watermark(render_plot(dates + watermark_tiles(id), width = 8, height = 4.5)))
}

# 2c. Tiles: white tiles on a dark chart. With grey25 grid lines the chart
#     decodes alone but not once it sits in a wider canvas (Chrome retina
#     screenshots hit this); with theme_minimal()'s default light grid lines
#     on the dark panel it doesn't decode even alone, lossless.
cat("\n2c. White tiles on a dark chart\n")
dark <- ggplot(mtcars, aes(wt, mpg)) + geom_point(colour = "#7fdbff") + theme_minimal() +
  theme(plot.background = element_rect(fill = "#121212", colour = NA),
        panel.background = element_rect(fill = "#1e1e1e", colour = NA))
dark_grid <- dark + theme(panel.grid = element_line(colour = "grey25"))
img_grid <- render_plot(dark_grid + watermark_tiles("K7Q2M9XD", colour = "white"))
timed("dark chart, grey25 grid, 1050 px alone", extract_watermark(img_grid))
timed("same pixels on 2560 px white canvas", extract_watermark(on_canvas(img_grid, 2560)))
timed("dark chart, default light grid, 1050 px alone", extract_watermark(
  render_plot(dark + watermark_tiles("K7Q2M9XD", colour = "white"))))

# 3. Time to return NULL. With no strip the decoder falls through to the tile
#    search, which is slow on large or busy images.
cat("\n3. Time to NULL (no watermark at all)\n")
timed("7x5 in @150 dpi scatter (1050 px)", extract_watermark(
  render_plot(ggplot(mtcars, aes(wt, mpg)) + geom_point())))
timed("facet_grid 3x4, 9x6 in @150 dpi (1350 px)", extract_watermark(
  render_plot(facets, width = 9, height = 6)))
timed("facet_grid 3x4, 9x6 in @300 dpi (2700 px)", extract_watermark(
  render_plot(facets, width = 9, height = 6, dpi = 300)))
timed("14x10 in @300 dpi scatter (4200 px), tiles present", extract_watermark(
  render_plot(ggplot(mtcars, aes(wt, mpg)) + geom_point() + watermark_tiles("K7Q2M9XD"),
              width = 14, height = 10, dpi = 300)))
