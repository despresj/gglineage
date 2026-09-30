tile_votes <- function(id) matrix(2L * encode_tile(id) - 1L, 12, 12, byrow = TRUE)
tiled <- function(p = base_plot(), id = "K7Q2M9XD", ...) render_plot(p + watermark_tiles(id), ...)

test_that("align_tiles finds the offset of a shifted tile grid", {
  big <- tile_votes("K7Q2M9XD")[rep(1:12, 4), rep(1:12, 4)]
  best <- align_tiles(big[6:40, 4:44])[[1]]
  expect_equal(c(best$oy, best$ox), c(5L, 3L))
  expect_identical(decode_tile(best$bits), "K7Q2M9XD")
})

test_that("align_tiles tolerates erasures and some wrong votes", {
  big <- tile_votes("K7Q2M9XD")[rep(1:12, 4), rep(1:12, 4)]
  set.seed(3)
  n <- length(big)
  big[sample(n, round(0.3 * n))] <- 0L
  flip <- sample(which(big != 0L), round(0.07 * n))  # about 10% of readable votes
  big[flip] <- -big[flip]
  expect_identical(decode_tile_votes(align_tiles(big)[[1]]$votes), "K7Q2M9XD")
})

test_that("decode_tiles reads a clean render; extract_watermark falls back to it", {
  skip_if_no_raster()
  skip_on_cran()
  img <- tiled()
  expect_identical(decode_tiles(as_gray(img)), "K7Q2M9XD")
  expect_identical(extract_watermark(img), "K7Q2M9XD")
})

test_that("decode_tiles returns NULL on unwatermarked and dots-only images", {
  skip_if_no_raster()
  skip_on_cran()
  expect_null(decode_tiles(as_gray(render_plot(base_plot()))))
  expect_null(decode_tiles(as_gray(render_plot(base_plot() + watermark_dots("K7Q2M9XD")))))
})

test_that("dark mode and white tiles on a dark plot decode via the polarity retry", {
  skip_if_no_raster()
  skip_on_cran()
  expect_identical(extract_watermark(tf_invert(tiled())), "K7Q2M9XD")
  dark <- base_plot() + theme_dark() +
    theme(plot.background = element_rect(fill = "grey10"), panel.background = element_rect(fill = "grey20"))
  img <- render_plot(dark + watermark_tiles("K7Q2M9XD", colour = "white"))
  expect_identical(extract_watermark(img), "K7Q2M9XD")
})

test_that("dots and tiles with different IDs: strip wins, tiles still readable", {
  skip_if_no_raster()
  skip_on_cran()
  img <- render_plot(base_plot() + watermark_tiles("TILE-2") + watermark_dots("STRIP-1"))
  expect_identical(extract_watermark(img), "STRIP-1")
  expect_identical(decode_tiles(as_gray(img)), "TILE-2")
})

test_that("debug output reports the tile stages", {
  skip_if_no_raster()
  skip_on_cran()
  img <- tiled()
  msgs <- paste(capture_messages(extract_watermark(img, debug = TRUE)), collapse = "")
  expect_match(msgs, "tiles: .*pitch")
  expect_match(msgs, "tiles: .*CRC passed")
})

test_that("large images are downsampled before tile decoding", {
  skip_if_no_raster()
  skip_on_cran()
  img <- tiled(width = 12, height = 12, dpi = 300)
  expect_message(decode_tiles(as_gray(img), debug = TRUE), "tiles: downsampled by 2")
})

test_that("up to 2 cells with no net votes are resolved by the CRC", {
  tv <- 2 * encode_tile("K7Q2M9XD") - 1
  tv[c(20L, 110L)] <- 0
  expect_identical(decode_tile_votes(tv), "K7Q2M9XD")
})

test_that("more than 2 cells with no net votes give NULL, not a guess", {
  tv <- 2 * encode_tile("K7Q2M9XD") - 1
  tv[c(20L, 55L, 110L)] <- 0
  expect_null(decode_tile_votes(tv))
})

test_that("free cells that fit another codeword never yield a wrong ID", {
  # Reviewer repro: with these six cells free, a second valid codeword fits.
  tv <- 2 * encode_tile("K7Q2M9XD") - 1
  tv[c(19L, 26L, 59L, 79L, 87L, 89L)] <- 0
  got <- decode_tile_votes(tv)
  expect_true(is.null(got) || identical(got, "K7Q2M9XD"), label = format(got))
  # Random free cells: never a wrong ID, whatever the count.
  set.seed(11)
  for (i in 1:300) {
    tv <- 2 * encode_tile("JD-2026-0928") - 1
    tv[16L + sample(112L, 4L)] <- 0
    got <- decode_tile_votes(tv)
    expect_true(is.null(got) || identical(got, "JD-2026-0928"), label = format(got))
  }
})

test_that("IDs whose tile has an all-0 or all-1 line still decode", {
  skip_if_no_raster()
  skip_on_cran()
  for (x in c("RquBUGs", "tiV:m7U_IM")) {
    expect_identical(extract_watermark(render_plot(base_plot() + watermark_tiles(x))), x, info = x)
  }
})

test_that("a pitch beyond the search range decodes on the downsampled retry", {
  skip_if_no_raster()
  skip_on_cran()
  # 4.5 x 4 in at 520 dpi: 3 mm is 61 px, past the 60 px search limit, and
  # the image is too small to be downsampled up front.
  img <- tiled(width = 4.5, height = 4, dpi = 520)
  msgs <- paste(capture_messages(got <- decode_tiles(as_gray(img), debug = TRUE)), collapse = "")
  expect_identical(got, "K7Q2M9XD")
  expect_match(msgs, "downsampled by 2")
})
