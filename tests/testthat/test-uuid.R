# UUIDs: accepted forms, normalisation, errors, generation, and recovery of
# all 128 bits from rendered pixels.

v4 <- "f47ac10b-58cc-4372-a567-0e02b2c3d479"
v7 <- "0192b6e4-9c3a-7d1e-8f2a-3c4d5e6f7a8b"
uuid_re <- "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"

test_that("canonical UUIDs are accepted in either case and returned lowercase", {
  expect_equal(parse_id(v4)$kind, "uuid")
  expect_equal(parse_id(v4)$id, v4)
  expect_equal(parse_id(toupper(v4))$id, v4)
  expect_equal(parse_id(v7)$id, v7)
  expect_equal(parse_id("F47AC10B-58cc-4372-A567-0e02B2C3D479")$id, v4)
  expect_equal(check_id(toupper(v7)), v7)
})

test_that("braces and the urn:uuid: prefix are stripped", {
  expect_equal(parse_id(paste0("{", v4, "}"))$id, v4)
  expect_equal(parse_id(paste0("{", toupper(v4), "}"))$id, v4)
  expect_equal(parse_id(paste0("urn:uuid:", v4))$id, v4)
  expect_equal(parse_id(paste0("URN:UUID:", toupper(v4)))$id, v4)
})

test_that("nil and max UUIDs are carried as they are", {
  nil <- "00000000-0000-0000-0000-000000000000"
  max <- "ffffffff-ffff-ffff-ffff-ffffffffffff"
  expect_equal(parse_id(nil)$id, nil)
  expect_equal(parse_id(max)$id, max)
  expect_equal(assemble_uuid(parse_frame(encode_rows(nil)[[1]]),
                             parse_frame(encode_rows(nil)[[2]])), nil)
  expect_equal(assemble_uuid(parse_frame(encode_rows(max)[[1]]),
                             parse_frame(encode_rows(max)[[2]])), max)
})

test_that("malformed UUIDs are rejected with a specific reason", {
  expect_error(parse_id(gsub("-", "", v4)), "no hyphens")
  expect_error(parse_id(sub("9$", "g", v4)), "other than hexadecimal")
  expect_error(parse_id(substr(v4, 1, 35)), "31 hexadecimal digits")
  expect_error(parse_id(paste0(v4, "0")), "33 hexadecimal digits")
  expect_error(parse_id("f47ac10-b58cc-4372-a567-0e02b2c3d479"), "hyphens in the wrong places")
  expect_error(parse_id(paste0(" ", v4)), "whitespace")
  expect_error(parse_id(paste0(v4, "\n")), "whitespace")
  expect_error(parse_id(paste0("{", v4)), "at most 16 bytes")
  # Long strings that don't resemble a UUID get the plain size message.
  expect_error(parse_id(strrep("a", 17)), "17 bytes.*Use a short ID")
  expect_error(parse_id(strrep("a", 36)), "36 bytes.*Use a short ID")
  expect_error(watermark_dots(gsub("-", "", v4)), "8-4-4-4-12")
})

test_that("short text is never mistaken for a UUID", {
  for (id in c("f47ac10b", "f47a-c10b", "0e02b2c3d479", "ffffffffffffffff")) {
    expect_equal(parse_id(id)$kind, "text")
    expect_equal(parse_id(id)$id, id)
  }
})

test_that("wm_uuid() makes version 4 UUIDs by default", {
  u <- wm_uuid()
  expect_match(u, uuid_re)
  expect_equal(substr(u, 15, 15), "4")
  expect_true(substr(u, 20, 20) %in% c("8", "9", "a", "b"))
  expect_equal(anyDuplicated(replicate(500, wm_uuid())), 0L)
})

test_that("wm_uuid(version = 7) is time-ordered and stamped with the current time", {
  before <- floor(as.numeric(Sys.time()) * 1000)
  u <- wm_uuid(version = 7)
  after <- floor(as.numeric(Sys.time()) * 1000)
  expect_match(u, uuid_re)
  expect_equal(substr(u, 15, 15), "7")
  expect_true(substr(u, 20, 20) %in% c("8", "9", "a", "b"))
  stamp <- strtoi(substring(gsub("-", "", u), c(1, 5, 9), c(4, 8, 12)), 16L)
  ms <- ((stamp[1] * 65536) + stamp[2]) * 65536 + stamp[3]
  expect_gte(ms, before - 1)
  expect_lte(ms, after + 1)
  later <- wm_uuid(version = 7)
  expect_true(later >= u)
  expect_error(wm_uuid(version = 1), "4 or 7")
  expect_error(wm_uuid(version = "4"), "4 or 7")
})

test_that("random bytes come from the OS where it offers them", {
  skip_if_not(file.exists("/dev/urandom"))
  a <- os_random_bytes(16L)
  b <- os_random_bytes(16L)
  expect_type(a, "raw")
  expect_length(a, 16L)
  expect_false(identical(a, b))
})

test_that("the uuid package, when installed, supplies random bytes", {
  skip_if_not_installed("uuid")
  bytes <- uuid_package_bytes(40L)
  expect_type(bytes, "raw")
  expect_length(bytes, 40L)
  expect_gt(length(unique(bytes)), 10L)
})

test_that("the private stream leaves the session's RNG state exactly as it was", {
  set.seed(99)
  before <- get(".Random.seed", globalenv())
  expected <- runif(2)
  set.seed(99)
  a <- private_stream_bytes(16L)
  b <- private_stream_bytes(16L)
  expect_identical(get(".Random.seed", globalenv()), before)
  expect_equal(runif(2), expected)
  expect_length(a, 16L)
  expect_false(identical(a, b))
})

test_that("a plain plot with a UUID watermark keeps its scales and data", {
  p <- base_plot()
  before <- ggplot_build(p)
  after <- ggplot_build(p + watermark_dots(v4))
  expect_equal(after$layout$panel_params[[1]]$x.range,
               before$layout$panel_params[[1]]$x.range)
  expect_equal(after$data[seq_along(before$data)], before$data)
})

test_that("all 128 bits come back from the pixels, lowercase, as a plain string", {
  skip_if_no_raster()
  for (input in c(v4, toupper(v7), paste0("{", toupper(v4), "}"))) {
    expected <- tolower(uuid_body(input))
    got <- extract_watermark(render_plot(base_plot() + watermark_dots(input)))
    expect_identical(got, expected)
    expect_null(attributes(got))
  }
})

test_that("UUIDs round-trip on other plot types, sizes and dark backgrounds", {
  skip_if_no_raster()
  skip_on_cran()
  zoo <- plot_zoo()
  for (name in c("facets_discrete", "legend_bottom", "polar", "void")) {
    got <- extract_watermark(render_plot(zoo[[name]] + watermark_dots(v4)))
    expect_identical(got, v4, label = name)
  }
  for (s in list(c(4, 3, 150), c(7, 5, 72), c(12, 4, 100), c(4, 8, 120))) {
    img <- render_plot(base_plot() + watermark_dots(v7),
                       width = s[1], height = s[2], dpi = s[3])
    expect_identical(extract_watermark(img), v7, label = paste(s, collapse = " x "))
  }
  dark <- base_plot() +
    theme_dark() +
    theme(plot.background = element_rect(fill = "grey10")) +
    watermark_dots(v4, colour = "white")
  expect_identical(extract_watermark(render_plot(dark)), v4)
})

test_that("visible text stays clear of both dot rows", {
  skip_if_no_raster()
  for (pos in c("bottomright", "bottomleft")) {
    stamp <- watermark_text("CONFIDENTIAL — do not share", position = pos,
                            alpha = 0.8)
    expect_identical(extract_watermark(render_plot(base_plot() + stamp + watermark_dots(v4))),
                     v4, label = pos)
    expect_identical(extract_watermark(render_plot(base_plot() + watermark_dots(v4) + stamp)),
                     v4, label = pos)
  }
})

test_that("half a UUID is never returned", {
  skip_if_no_raster()
  img <- render_plot(base_plot() + watermark_dots(v4))
  h <- dim(img)[1]
  # The lower row sits 2.4 mm (14 px at 150 dpi) above the bottom edge and
  # the upper one 2.2 mm higher. Painting over either leaves one valid row.
  lower <- img
  lower[(h - 22):h, , ] <- 1
  upper <- img
  upper[(h - 34):(h - 23), , ] <- 1
  expect_identical(extract_watermark(img), v4)
  expect_null(extract_watermark(lower))
  expect_null(extract_watermark(upper))
  expect_null(extract_watermark(tf_crop(img, bottom = 0.03)))
})

test_that("UUIDs survive representative sharing, and fail cleanly past the limits", {
  skip_if_no_raster()
  skip_if_not_installed("jpeg")
  img <- render_plot(base_plot() + watermark_dots(v4))
  survives <- list(
    "JPEG 50" = function(x) tf_jpeg(x, 50),
    "half size" = function(x) tf_resize(x, 0.5),
    "640 px + JPEG 50" = function(x) tf_jpeg(tf_resize_to_width(x, 640), 50),
    "552 px padded + JPEG 50" = function(x) tf_jpeg(tf_pad(tf_resize_to_width(x, 552), 40), 50),
    "inverted" = tf_invert
  )
  for (name in names(survives)) {
    expect_identical(extract_watermark(survives[[name]](img)), v4, label = name)
  }
  past <- list(
    "300 px + JPEG 50" = function(x) tf_jpeg(tf_resize_to_width(x, 300), 50),
    "crop left 10%" = function(x) tf_crop(x, left = 0.1),
    "rotate 90" = tf_rotate90
  )
  for (name in names(past)) {
    got <- extract_watermark(past[[name]](img))
    expect_true(is.null(got) || identical(got, v4), label = name)
  }
})

test_that("UUID stress sweep never returns a wrong UUID", {
  skip_if_no_raster()
  skip_if_not_installed("jpeg")
  skip_on_cran()
  set.seed(5)
  for (i in 1:3) {
    id <- wm_uuid()
    img <- render_plot(base_plot() + watermark_dots(id), dpi = 120)
    for (tf in stress_transforms()) {
      got <- extract_watermark(suppressWarnings(tf$f(img)))
      expect_true(is.null(got) || identical(got, id),
                  label = sprintf("%s decoded %s as %s", tf$name, id, format(got)))
    }
  }
})

test_that("ggsave_watermark() stores and returns the canonical UUID", {
  skip_if_no_raster()
  file <- withr_tempfile(".png")
  id <- ggsave_watermark(file, base_plot(), id = toupper(v4),
                         width = 6, height = 4, dpi = 120)
  expect_identical(id, v4)
  expect_identical(read_watermark_metadata(file)$id, v4)
  expect_identical(extract_watermark(file), v4)
})

test_that("debug output names both rows of a UUID", {
  skip_if_no_raster()
  img <- render_plot(base_plot() + watermark_dots(v4), dpi = 100)
  expect_message(extract_watermark(img, debug = TRUE), "Decoded UUID from rows")
})
