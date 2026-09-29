test_that("watermark_dots() is an ordinary + component", {
  p <- base_plot() + watermark_dots("RUN-42")
  expect_s3_class(p, "ggplot")
  expect_no_error(ggplotGrob(p))
  expect_s3_class(add_watermark(base_plot(), "RUN-42"), "ggplot")
})

test_that("the watermark does not change scales, ranges or data", {
  for (p in plot_zoo()) {
    before <- ggplot_build(p)
    after <- ggplot_build(p + watermark_dots("RUN-42"))
    expect_equal(after$layout$panel_params[[1]]$x.range,
                 before$layout$panel_params[[1]]$x.range)
    expect_equal(after$layout$panel_params[[1]]$y.range,
                 before$layout$panel_params[[1]]$y.range)
    expect_equal(after$data[seq_along(before$data)], before$data)
    expect_equal(nrow(after$layout$layout), nrow(before$layout$layout))
  }
})

test_that("invalid IDs fail at construction, not at render time", {
  expect_error(watermark_dots(strrep("a", 20)), "bytes")
  expect_error(base_plot() + watermark_dots(""), "non-empty")
})

test_that("dots round-trip on every plot type", {
  skip_if_no_raster()
  for (name in names(plot_zoo())) {
    p <- plot_zoo()[[name]] + watermark_dots("K7Q2M9XD")
    expect_equal(extract_watermark(render_plot(p)), "K7Q2M9XD", label = name)
  }
})

test_that("dots round-trip across sizes and resolutions", {
  skip_if_no_raster()
  sizes <- list(c(4, 3, 150), c(7, 5, 72), c(7, 5, 300), c(12, 4, 100),
                c(4, 8, 120), c(10, 6, 96))
  for (s in sizes) {
    img <- render_plot(base_plot() + watermark_dots("K7Q2M9XD"),
                       width = s[1], height = s[2], dpi = s[3])
    expect_equal(extract_watermark(img), "K7Q2M9XD",
                 label = paste(s, collapse = " x "))
  }
})

test_that("random IDs of every length round-trip", {
  skip_if_no_raster()
  skip_on_cran()
  for (n in c(1, 4, 8, 12, 16)) {
    for (i in 1:3) {
      id <- wm_id(n)
      img <- render_plot(base_plot() + watermark_dots(id), dpi = 120)
      expect_equal(extract_watermark(img), id)
    }
  }
})

test_that("light dots work on dark backgrounds", {
  skip_if_no_raster()
  p <- base_plot() +
    theme_dark() +
    theme(plot.background = element_rect(fill = "grey10")) +
    watermark_dots("K7Q2M9XD", colour = "white")
  expect_equal(extract_watermark(render_plot(p)), "K7Q2M9XD")
})

test_that("dots coexist with a visible corner stamp in the same row", {
  skip_if_no_raster()
  p <- base_plot() +
    watermark_text("CONFIDENTIAL — do not share", position = "bottomright") +
    watermark_dots("K7Q2M9XD")
  expect_equal(extract_watermark(render_plot(p)), "K7Q2M9XD")
})

test_that("unwatermarked plots and blank images decode to NULL", {
  skip_if_no_raster()
  for (p in plot_zoo()) expect_null(extract_watermark(render_plot(p, dpi = 100)))
  expect_null(extract_watermark(array(1, c(200, 300, 3))))
  set.seed(7)
  expect_null(extract_watermark(array(runif(200 * 300), c(200, 300))))
})
