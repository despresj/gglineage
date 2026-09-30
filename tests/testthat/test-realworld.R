# Real tools, real bytes: the fast subset of tools/realworld-hammer.R. Each
# test skips when its tool is missing (ffmpeg, cwebp/dwebp, sips, pdftoppm,
# headless Chrome), and none run on CRAN. Promised cases must decode exactly;
# everything else must decode exactly or return NULL, never a wrong ID.

rw_ids <- list(id8 = "K7Q2M9XD", uuid = "f47ac10b-58cc-4372-a567-0e02b2c3d479")

# Save a 7 x 5 in, 150 dpi (1050 x 750 px) scatter carrying `wm`.
rw_source <- function(wm = list(), ext = ".png", transparent = FALSE, env = parent.frame()) {
  p <- Reduce(`+`, wm, base_plot())
  if (transparent) {
    p <- p + ggplot2::theme(plot.background = ggplot2::element_rect(fill = "transparent", colour = NA))
  }
  file <- withr_tempfile(ext, env = env)
  ggplot2::ggsave(file, p, width = 7, height = 5, dpi = 150,
                  bg = if (transparent) "transparent" else "white")
  file
}

expect_exact_or_null <- function(got, id, label) {
  expect_true(is.null(got) || identical(got, id),
              label = sprintf("%s decoded %s as %s", label, id, format(got)))
}

test_that("ffmpeg: 4:2:0 JPEG, scaling filters and chat-app chains decode exactly", {
  skip_on_cran()
  skip_if_no_raster()
  skip_if_not_installed("jpeg")
  skip_if(!rw_has("ffmpeg"), "ffmpeg not installed")
  for (id in rw_ids) {
    src <- rw_source(list(watermark_dots(id)))
    out <- function(ext) withr_tempfile(ext, env = parent.frame())
    jpg <- out(".jpg")
    rw_ffmpeg_jpeg(src, jpg, 5)                                   # ~quality 85
    expect_equal(extract_watermark(jpg), id, label = "ffmpeg JPEG -q:v 5")
    for (flags in c("lanczos", "area", "neighbor")) {
      png <- out(".png")
      rw_ffmpeg_scale(src, png, 640, flags)
      expect_equal(extract_watermark(png), id, label = paste("scale 640", flags))
    }
    # Slack-like: fit 1024 wide, JPEG ~q85, then re-encoded.
    a <- out(".jpg")
    b <- out(".jpg")
    rw_ffmpeg_jpeg(src, a, 4, vf = "scale='min(1024,iw)':-2")
    rw_ffmpeg_jpeg(a, b, 4)
    expect_equal(extract_watermark(b), id, label = "Slack chain")
  }
})

test_that("transparent PNGs decode on white and dark-mode backgrounds", {
  skip_on_cran()
  skip_if_no_raster()
  skip_if(!rw_has("ffmpeg"), "ffmpeg not installed")
  src <- rw_source(list(watermark_dots(rw_ids$id8)), transparent = TRUE)
  expect_equal(extract_watermark(src), rw_ids$id8)
  for (colour in c("0xffffff", "0x1a1d21", "0x000000")) {
    out <- withr_tempfile(".png")
    rw_ffmpeg_composite(src, out, colour)
    expect_equal(extract_watermark(out), rw_ids$id8, label = paste("on", colour))
  }
})

test_that("WebP (cwebp/dwebp) round trips decode exactly", {
  skip_on_cran()
  skip_if_no_raster()
  skip_if(!rw_has("cwebp") || !rw_has("dwebp"), "libwebp tools not installed")
  for (id in rw_ids) {
    src <- rw_source(list(watermark_dots(id)))
    out <- withr_tempfile(".png")
    rw_webp(src, out, 75)
    expect_equal(extract_watermark(out), id)
  }
})

test_that("macOS sips: HEIC, JPEG and resampling decode exactly", {
  skip_on_cran()
  skip_if_no_raster()
  skip_if_not_installed("jpeg")
  skip_if(!rw_has("sips"), "sips (macOS) not available")
  src <- rw_source(list(watermark_dots(rw_ids$id8)))
  heic <- withr_tempfile(".png")
  rw_sips_heic(src, heic)
  expect_equal(extract_watermark(heic), rw_ids$id8, label = "HEIC")
  jpg <- withr_tempfile(".jpg")
  rw_sips_jpeg(src, jpg, 50)
  expect_equal(extract_watermark(jpg), rw_ids$id8, label = "sips JPEG q50")
  small <- withr_tempfile(".png")
  small_jpg <- withr_tempfile(".jpg")
  rw_sips_resample(src, small, 640)
  rw_sips_jpeg(small, small_jpg, 60)
  expect_equal(extract_watermark(small_jpg), rw_ids$id8, label = "640 px + JPEG q60")
})

test_that("PDF rasterised by pdftoppm decodes exactly", {
  skip_on_cran()
  skip_if_no_raster()
  skip_if(!rw_has("pdftoppm"), "pdftoppm not installed")
  for (id in rw_ids) {
    pdf <- rw_source(list(watermark_dots(id)), ext = ".pdf")
    out <- withr_tempfile(".png")
    rw_pdftoppm(pdf, out, 110)
    expect_equal(extract_watermark(out), id)
  }
})

test_that("headless Chrome screenshots of a web page decode exactly", {
  skip_on_cran()
  skip_if_no_raster()
  chrome <- rw_chrome()
  skip_if(!nzchar(chrome), "headless Chrome not found (set CHROME_BIN)")
  dots <- rw_source(list(watermark_dots(rw_ids$id8)))
  uuid <- rw_source(list(watermark_dots(rw_ids$uuid)))
  tiles <- rw_source(list(watermark_tiles(rw_ids$id8)))
  shot <- function(src, ...) {
    out <- withr_tempfile(".png", env = parent.frame())
    rw_chrome_shot(src, out, aspect = 5 / 7, chrome = chrome, ...)
    out
  }
  expect_equal(extract_watermark(shot(dots, css_width = 640, dpr = 1)), rw_ids$id8)
  expect_equal(extract_watermark(shot(uuid, css_width = "100%", dpr = 2, bg = "#0d1117")),
               rw_ids$uuid)
  expect_equal(extract_watermark(shot(tiles, css_width = 640, dpr = 1)), rw_ids$id8)
  # A chart that fills little of a wide screenshot: the strip is not always
  # found there (see tools/realworld-report.md), but it is never misread.
  expect_exact_or_null(extract_watermark(shot(dots, css_width = 360, dpr = 2)),
                       rw_ids$id8, "360 px chart in a 2560 px retina screenshot")
})

test_that("crops: tiles survive losing the strip; nothing decodes wrongly", {
  skip_on_cran()
  skip_if_no_raster()
  plot_both <- base_plot() + watermark_tiles(rw_ids$id8) + watermark_dots(rw_ids$id8)
  src <- withr_tempfile(".png")
  ggplot2::ggsave(src, plot_both, width = 7, height = 5, dpi = 150, bg = "white")
  box <- rw_panel_boxes(plot_both, 7, 5, 150)[1, ]
  img <- png::readPNG(src)
  expect_equal(extract_watermark(rw_crop(img, box)), rw_ids$id8, label = "tight panel crop")
  cut <- img[seq_len(round(0.96 * nrow(img))), , , drop = FALSE]
  expect_equal(extract_watermark(cut), rw_ids$id8, label = "strip cut off")

  dots_only <- png::readPNG(rw_source(list(watermark_dots(rw_ids$id8))))
  expect_null(extract_watermark(dots_only[seq_len(round(0.96 * nrow(dots_only))), , ,
                                          drop = FALSE]))
})

test_that("an unwatermarked chart through real pipelines decodes to NULL", {
  skip_on_cran()
  skip_if_no_raster()
  src <- rw_source()
  expect_null(extract_watermark(src))
  if (rw_has("ffmpeg")) {
    jpg <- withr_tempfile(".jpg")
    rw_ffmpeg_jpeg(src, jpg, 10, vf = "scale=640:-2")
    expect_null(extract_watermark(jpg))
  }
})
