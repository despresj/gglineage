test_that("ggsave_watermark() writes dots and metadata to PNG", {
  skip_if_no_raster()
  file <- withr_tempfile(".png")
  id <- ggsave_watermark(
    file, base_plot() + labs(title = "MPG vs weight"),
    metadata = list(script = "analysis/fig1.R", commit = "a1b2c3d"),
    width = 6, height = 4, dpi = 120
  )
  expect_match(id, "^[0-9A-Z]{8}$")
  expect_equal(extract_watermark(file), id)

  meta <- read_watermark_metadata(file)
  expect_equal(meta$id, id)
  expect_equal(meta$title, "MPG vs weight")
  expect_equal(meta$script, "analysis/fig1.R")
  expect_equal(meta$commit, "a1b2c3d")
  expect_match(meta$created, "^\\d{4}-\\d{2}-\\d{2}T")
  expect_match(meta$software, "ggplot2")
})

test_that("metadata-only saves skip the dots", {
  skip_if_no_raster()
  file <- withr_tempfile(".png")
  id <- ggsave_watermark(file, base_plot(), id = "META-ONLY", dots = FALSE,
                         width = 6, height = 4, dpi = 100)
  expect_null(extract_watermark(file))
  expect_equal(read_watermark_metadata(file)$id, "META-ONLY")
})

test_that("metadata is lost by re-encoding but the dots survive", {
  skip_if_no_raster()
  skip_if_not_installed("jpeg")
  file <- withr_tempfile(".png")
  id <- ggsave_watermark(file, base_plot(), width = 6, height = 4, dpi = 120)
  shared <- withr_tempfile(".png")
  png::writePNG(tf_jpeg(png::readPNG(file), 80), shared)
  expect_equal(read_watermark_metadata(shared), list())
  expect_equal(extract_watermark(shared), id)
})

test_that("non-PNG outputs keep the dots and warn about metadata", {
  skip_if_no_raster()
  skip_if_not_installed("jpeg")
  file <- withr_tempfile(".jpg")
  expect_warning(
    id <- ggsave_watermark(file, base_plot(), metadata = list(a = "b"),
                           width = 6, height = 4, dpi = 120),
    "only embedded in PNG"
  )
  expect_equal(extract_watermark(file), id)
  expect_equal(read_watermark_metadata(file), list())
})

test_that("argument errors are clear", {
  file <- withr_tempfile(".png")
  expect_error(ggsave_watermark(file, base_plot(), metadata = list("x")), "named")
  expect_error(ggsave_watermark(file, base_plot(), id = strrep("a", 30)), "bytes")
  expect_error(read_watermark_metadata("nope.png"), "not found")
  expect_error(extract_watermark("nope.png"), "not found")
  txt <- withr_tempfile(".txt")
  writeLines("hello", txt)
  expect_error(extract_watermark(txt), "Unsupported")
})

test_that("`path` in ... is honoured for the metadata as well as the image", {
  skip_if_no_raster()
  dir <- tempfile("figs")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  id <- ggsave_watermark("fig.png", base_plot(), path = dir,
                         width = 4, height = 3, dpi = 100)
  file <- file.path(dir, "fig.png")
  expect_false(file.exists("fig.png"))
  expect_identical(read_watermark_metadata(file)$id, id)
  expect_identical(extract_watermark(file), id)
})

test_that("metadata can't overwrite the reserved fields", {
  file <- withr_tempfile(".png")
  expect_error(ggsave_watermark(file, base_plot(), metadata = list(id = "x")),
               "reserved field name `id`")
  expect_error(ggsave_watermark(file, base_plot(),
                                metadata = list(created = 1, software = 2)),
               "`created`, `software`")
  expect_false(file.exists(file))
})
