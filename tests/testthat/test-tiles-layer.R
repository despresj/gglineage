test_that("tile_cells anchors cells to one device grid", {
  a <- tile_cells(0, 0, 24, 24, 2)
  expect_equal(nrow(a), 144L)
  expect_setequal(a$cell, 0:143)
  b <- tile_cells(5.1, 7.3, 10, 10, 2)
  both <- merge(a, b, by = c("gx", "gy"))
  expect_gt(nrow(both), 0L)
  expect_equal(both$cell.x, both$cell.y)
  expect_true(all(b$x_mm >= 5.1 & b$x_mm <= 15.1))
})

test_that("tile rows count downward on the page", {
  a <- tile_cells(0, 0, 24, 24, 2)
  expect_equal(a$cell[a$gx == 0 & a$gy == 11], 0L)
  expect_equal(a$cell[a$gx == 0 & a$gy == 0], 132L)
})

test_that("tile_cells returns no cells for a panel smaller than one pitch", {
  expect_equal(nrow(tile_cells(0.1, 0.1, 0.5, 0.5, 2)), 0L)
})

test_that("watermark_tiles() is added as the bottom layer", {
  p <- base_plot() + watermark_tiles("K7Q2M9XD")
  expect_s3_class(p, "ggplot")
  expect_length(p$layers, 2L)
  expect_s3_class(p$layers[[1]]$geom, "GeomWatermarkTiles")
})

test_that("the tiles do not change scales, ranges or data", {
  for (p in plot_zoo()) {
    before <- ggplot_build(p)
    after <- ggplot_build(p + watermark_tiles("K7Q2M9XD"))
    expect_equal(after$layout$panel_params[[1]]$x.range, before$layout$panel_params[[1]]$x.range)
    expect_equal(after$layout$panel_params[[1]]$y.range, before$layout$panel_params[[1]]$y.range)
    expect_equal(after$data[-1], before$data)
    expect_equal(nrow(after$layout$layout), nrow(before$layout$layout))
  }
})

test_that("invalid IDs fail at construction", {
  expect_error(watermark_tiles("thirteen-char"), "tiles hold at most 12 bytes")
  expect_error(watermark_tiles(""), "non-empty")
})

test_that("makeContent draws one circle per 1-cell inside the panel", {
  spec <- watermark_tiles("K7Q2M9XD")
  grDevices::pdf(NULL, width = 100 / 25.4, height = 100 / 25.4)
  on.exit(grDevices::dev.off())
  grid::pushViewport(grid::viewport(
    x = grid::unit(10, "mm"), y = grid::unit(20, "mm"),
    width = grid::unit(50, "mm"), height = grid::unit(40, "mm"), just = c("left", "bottom")
  ))
  kid <- grid::makeContent(tiles_grob(spec))$children[[1]]
  cells <- tile_cells(10, 20, 50, 40, spec$pitch)
  expect_equal(length(kid$x), sum(spec$bits[cells$cell + 1L]))
})

test_that("every plot in the zoo renders with tiles, including flipped and polar coords", {
  skip_if_no_raster()
  skip_on_cran()
  for (name in names(plot_zoo())) {
    expect_no_error(render_plot(plot_zoo()[[name]] + watermark_tiles("K7Q2M9XD"), dpi = 72))
  }
})
