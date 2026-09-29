test_that("every position renders without touching the data", {
  for (pos in c("center", "tile", "bottomright", "bottomleft", "topright", "topleft")) {
    p <- base_plot() + watermark_text("DRAFT", position = pos)
    expect_no_error(ggplotGrob(p))
    expect_equal(
      ggplot_build(p)$layout$panel_params[[1]]$x.range,
      ggplot_build(base_plot())$layout$panel_params[[1]]$x.range
    )
  }
})

test_that("the stamp is actually drawn onto the image", {
  skip_if_no_raster()
  plain <- render_plot(base_plot(), dpi = 72)
  for (pos in c("center", "tile", "topleft")) {
    stamped <- render_plot(base_plot() + watermark_text("DRAFT", position = pos),
                           dpi = 72)
    expect_gt(sum(abs(stamped - plain) > 0.05), 20, label = pos)
  }
})

test_that("text never enters the dot band, in any position or order", {
  skip_if_no_raster()
  for (pos in c("center", "tile", "bottomright", "bottomleft")) {
    stamp <- watermark_text("CONFIDENTIAL \u2014 do not share", position = pos,
                            alpha = 0.8)
    a <- base_plot() + stamp + watermark_dots("K7Q2M9XD")
    b <- base_plot() + watermark_dots("K7Q2M9XD") + stamp
    expect_equal(extract_watermark(render_plot(a)), "K7Q2M9XD", label = pos)
    expect_equal(extract_watermark(render_plot(b)), "K7Q2M9XD", label = pos)
  }
})

test_that("facets get a single stamp, not one per panel", {
  skip_if_no_raster()
  facetted <- ggplot(mpg, aes(displ, hwy)) + geom_point() + facet_wrap(~drv)
  once <- render_plot(facetted + watermark_text("X", position = "topleft",
                                                   alpha = 1, colour = "red"),
                      dpi = 72)
  red <- once[, , 1] > 0.9 & once[, , 2] < 0.2 & once[, , 3] < 0.2
  cols <- which(colSums(red) > 0)
  expect_lt(diff(range(cols)), 40)
})

test_that("bad arguments are caught", {
  expect_error(watermark_text(c("a", "b")), "single string")
  expect_error(watermark_text("a", position = "middle"))
})
