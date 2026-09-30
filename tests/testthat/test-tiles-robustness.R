id <- "K7Q2M9XD"

tile_base <- local({
  cache <- list()
  function(key, p = base_plot(), ...) {
    if (is.null(cache[[key]])) cache[[key]] <<- render_plot(p + watermark_tiles(id), ...)
    cache[[key]]
  }
})

expect_id <- function(img, info = NULL) expect_identical(extract_watermark(img), id, info = info)

tile_must_pass <- c(
  "Original PNG", "PNG re-save", "JPEG quality 95", "JPEG quality 75",
  "Downscale to 75%", "Downscale to 50%", "Crop top 30%",
  "Pad with light UI chrome", "Pad with dark UI chrome",
  "Screenshot chain (2x, pad, 0.5x, JPEG 80)", "Inverted (dark mode)",
  "Crop bottom 5%", "Crop left 10%"
)

for (tf in stress_transforms()) {
  local({
    tf <- tf
    test_that(sprintf("tiles, %s: %s", tf$group, tf$name), {
      skip_if_no_raster()
  skip_on_cran()
      skip_if_not_installed("jpeg")
      skip_on_cran()
      set.seed(1)
      got <- extract_watermark(suppressWarnings(tf$f(tile_base("scatter"))))
      if (tf$name %in% tile_must_pass) {
        expect_equal(got, id)
      } else {
        expect_true(is.null(got) || identical(got, id),
                    label = sprintf("decoded %s as %s", id, format(got)))
      }
    })
  })
}

test_that("tiles: sizes and resolutions", {
  skip_if_no_raster()
  skip_on_cran()
  for (s in list(c(7, 5, 72), c(7, 5, 96), c(7, 5, 150), c(7, 5, 300), c(10, 4, 300))) {
    expect_id(render_plot(base_plot() + watermark_tiles(id), width = s[1], height = s[2], dpi = s[3]),
              paste(s, collapse = " x "))
  }
  # Figures under about 5 x 4 in hold too few 36 mm tiles; the documented
  # remedy is a smaller pitch.
  expect_id(render_plot(base_plot() + watermark_tiles(id, pitch = 2, size = 0.7), width = 4, height = 4, dpi = 150),
            "4 x 4 x 150, pitch 2")
})

test_that("tiles: JPEG 85 and a real .jpg from ggsave", {
  skip_if_no_raster()
  skip_on_cran()
  skip_if_not_installed("jpeg")
  skip_on_cran()
  expect_id(tf_jpeg(tile_base("scatter"), 85), "q85")
  file <- tempfile(fileext = ".jpg")
  on.exit(unlink(file))
  ggsave(file, base_plot() + watermark_tiles(id), width = 7, height = 5, dpi = 150, quality = 75)
  expect_id(file, "ggsave jpg")
})

test_that("tiles: crops that keep at least 40% of the panel", {
  skip_if_no_raster()
  skip_on_cran()
  img <- tile_base("scatter")
  cases <- list(
    bottom = list(bottom = 0.25), top = list(top = 0.25),
    left = list(left = 0.25), right = list(right = 0.25),
    all = list(top = 0.15, bottom = 0.15, left = 0.15, right = 0.15),
    corner = list(top = 0.3, left = 0.3)
  )
  for (nm in names(cases)) expect_id(do.call(tf_crop, c(list(img), cases[[nm]])), nm)
})

test_that("tiles: every zoo plot except polar decodes; polar never decodes wrongly", {
  skip_if_no_raster()
  skip_on_cran()
  zoo <- plot_zoo()
  for (nm in setdiff(names(zoo), "polar")) expect_id(render_plot(zoo[[nm]] + watermark_tiles(id)), nm)
  got <- extract_watermark(render_plot(zoo$polar + watermark_tiles(id)))
  expect_true(is.null(got) || identical(got, id))
})

test_that("tiles: themes and backgrounds", {
  skip_if_no_raster()
  skip_on_cran()
  themes <- list(
    grey = theme_grey(), bw = theme_bw(), minimal = theme_minimal(), dark = theme_dark(),
    grey_bg = theme(plot.background = element_rect(fill = "grey92", colour = NA))
  )
  for (nm in names(themes)) expect_id(render_plot(base_plot() + themes[[nm]] + watermark_tiles(id)), nm)
})

test_that("tiles: transparent-background PNG", {
  skip_if_no_raster()
  skip_on_cran()
  file <- tempfile(fileext = ".png")
  on.exit(unlink(file))
  ggsave(file, base_plot() + watermark_tiles(id), width = 7, height = 5, dpi = 150, bg = "transparent")
  expect_id(file)
})

test_that("tiles: 30 random IDs of 1 to 12 characters", {
  skip_if_no_raster()
  skip_on_cran()
  for (i in 1:30) {
    x <- wm_id(1 + (i - 1) %% 12)
    expect_identical(extract_watermark(render_plot(base_plot() + watermark_tiles(x), dpi = 96)), x, info = x)
  }
})

test_that("tiles: default dots are at most 6% darker than white", {
  skip_if_no_raster()
  skip_on_cran()
  blank <- ggplot(data.frame(x = 0:1, y = 0:1), aes(x, y)) + geom_blank() + theme_void() +
    theme(plot.background = element_rect(fill = "white", colour = NA))
  expect_lte(tile_contrast(render_plot(blank + watermark_tiles(id), dpi = 300)), 0.06)
})

test_that("tiles: a 3600 px image decodes in under 60 seconds", {
  skip_if_no_raster()
  skip_on_cran()
  img <- render_plot(base_plot() + watermark_tiles(id), width = 12, height = 12, dpi = 300)
  elapsed <- system.time(got <- extract_watermark(img))[["elapsed"]]
  expect_identical(got, id)
  expect_lt(elapsed, 60)
})

test_that("tiles: documented limits never return a wrong ID", {
  skip_if_no_raster()
  skip_on_cran()
  raster <- ggplot(faithfuld, aes(waiting, eruptions, fill = density)) + geom_raster()
  black <- base_plot() + theme(panel.background = element_rect(fill = "black"))
  for (p in list(raster = raster, black = black)) {
    got <- extract_watermark(render_plot(p + watermark_tiles(id)))
    expect_true(is.null(got) || identical(got, id))
  }
})

test_that("tiles: a crop keeping about 75 mm square of open panel decodes", {
  skip_if_no_raster()
  skip_on_cran()
  img <- tile_base("scatter")
  px <- round(75 / 25.4 * 150)
  # Upper-left of the panel, clear of the axis text.
  expect_id(img[60:(60 + px - 1), 150:(150 + px - 1), , drop = FALSE], "75 mm crop")
})
