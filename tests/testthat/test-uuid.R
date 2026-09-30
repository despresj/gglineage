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
  # Ordered by millisecond; within one millisecond the order is random.
  Sys.sleep(0.005)
  later <- wm_uuid(version = 7)
  expect_true(later > u)
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

test_that("openssl, when installed, supplies random bytes", {
  skip_if_not_installed("openssl")
  a <- openssl_random_bytes(40L)
  expect_type(a, "raw")
  expect_length(a, 40L)
  expect_false(identical(a, openssl_random_bytes(40L)))
})

test_that("with no secure source, IDs are refused rather than made weakly", {
  local_mocked_bindings(os_random_bytes = function(n) NULL,
                        openssl_random_bytes = function(n) NULL)
  expect_error(wm_uuid(), "No secure source of random numbers")
  expect_error(wm_id(), "openssl")
})

test_that("Windows-like systems fall back to openssl", {
  skip_if_not_installed("openssl")
  local_mocked_bindings(os_random_bytes = function(n) NULL)
  expect_match(wm_uuid(), uuid_re)
  expect_equal(anyDuplicated(replicate(200, wm_uuid())), 0L)
})

test_that("IDs never touch the session's random number generator", {
  set.seed(99)
  before <- get(".Random.seed", globalenv())
  expected <- runif(2)
  set.seed(99)
  a <- wm_uuid()
  b <- wm_id()
  expect_identical(get(".Random.seed", globalenv()), before)
  expect_equal(runif(2), expected)
  # And set.seed() does not make them repeat.
  set.seed(1)
  x <- wm_uuid()
  set.seed(1)
  expect_false(identical(x, wm_uuid()))
})

test_that("forked workers make different IDs", {
  skip_on_os("windows")
  skip_on_cran()
  ids <- unlist(parallel::mclapply(1:4, function(i) wm_uuid(), mc.cores = 2))
  expect_equal(anyDuplicated(ids), 0L)
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

# Several codes in one image: stacked or copied charts, or a row painted over
# with another chart's. Each UUID row fits only the other row of its own
# UUID, so the answer is one of the UUIDs present, or nothing; never a mix.

stack_rows <- function(top, bottom) {
  out <- array(0, c(dim(top)[1] + dim(bottom)[1], dim(top)[2], dim(top)[3]))
  out[seq_len(dim(top)[1]), , ] <- top
  out[dim(top)[1] + seq_len(dim(bottom)[1]), , ] <- bottom
  out
}

test_that("a row of one UUID transplanted under the other half of another is rejected", {
  skip_if_no_raster()
  a <- "0f6c5a0e-8a53-4b0c-9d51-5f2a0b3e7c11"
  b <- "c3e1d2a4-7b6f-4e21-8c9d-0a1b2c3d4e5f"
  ia <- render_plot(base_plot() + watermark_dots(a))
  ib <- render_plot(base_plot() + watermark_dots(b))
  h <- dim(ia)[1]
  # At 150 dpi the lower row (bytes 1-8) is centred 14 px above the bottom
  # edge and the upper row (bytes 9-16) 27 px; the two plots are identical
  # apart from the dots, so the rows line up exactly.
  lower <- (h - 20):h
  upper <- (h - 33):(h - 21)
  a_over_b <- ia
  a_over_b[lower, , ] <- ib[lower, , ]
  b_over_a <- ia
  b_over_a[upper, , ] <- ib[upper, , ]
  expect_null(extract_watermark(a_over_b))
  expect_null(extract_watermark(b_over_a))
  expect_null(extract_watermark(tf_jpeg(a_over_b, 80)))
  # Same surgery with the matching row is harmless.
  same <- ia
  same[lower, , ] <- ia[lower, , ]
  expect_identical(extract_watermark(same), a)
})

test_that("stacked strip charts decode to one of their own UUIDs, never a mix", {
  skip_if_no_raster()
  strip <- ggplot2::ggplot(ggplot2::economics, ggplot2::aes(date, unemploy)) +
    ggplot2::geom_line() +
    ggplot2::theme_minimal() +
    ggplot2::theme(plot.background = ggplot2::element_rect(fill = "white", colour = NA),
                   axis.title = ggplot2::element_blank())
  ids <- c("5d0c7e7a-3f4b-4c55-a1d2-9e8f7a6b5c4d",
           "a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d",
           "9f8e7d6c-5b4a-4938-a726-15f4e3d2c1b0")
  imgs <- lapply(ids, function(id) {
    render_plot(strip + watermark_dots(id), width = 12, height = 0.6, dpi = 100)
  })
  stack <- stack_rows(stack_rows(imgs[[1]], imgs[[2]]), imgs[[3]])
  n <- dim(stack)[1]
  expect_identical(extract_watermark(stack), ids[3])
  # Crop the bottom chart's lower row away: its upper row must not be joined
  # to the lower row of the chart above, which is the nearest one that is
  # intact. The middle chart is then the answer.
  expect_identical(extract_watermark(stack[1:(n - 13), , ]), ids[2])
  expect_identical(extract_watermark(tf_jpeg(stack[1:(n - 13), , ], 75)), ids[2])
  # Cut through the middle chart's upper row as well.
  got <- extract_watermark(stack[1:(n - 13 - 60 - 20), , ])
  expect_true(is.null(got) || identical(got, ids[1]))
})

test_that("thin charts whose rows sit within reach of each other never mix", {
  skip_if_no_raster()
  skip_on_cran()
  # Charts 0.45 in tall: the lower row of the bottom chart is close enough
  # to the upper row of the chart above that only the pair check separates
  # them.
  thin <- ggplot2::ggplot(mtcars, ggplot2::aes(wt, mpg)) +
    ggplot2::geom_line() +
    ggplot2::theme_void() +
    ggplot2::theme(plot.background = ggplot2::element_rect(fill = "white", colour = NA))
  set.seed(21)
  for (i in 1:4) {
    a <- format_uuid(as.raw(sample(0:255, 16, replace = TRUE)))
    b <- format_uuid(as.raw(sample(0:255, 16, replace = TRUE)))
    ia <- render_plot(thin + watermark_dots(a), width = 12, height = 0.45, dpi = 100)
    ib <- render_plot(thin + watermark_dots(b), width = 12, height = 0.45, dpi = 100)
    st <- stack_rows(ia, ib)
    n <- dim(st)[1]
    hb <- dim(ib)[1]
    # Erase the bottom chart's upper row (bytes 9-16), leaving its lower row
    # directly below the other chart's rows.
    erased <- st
    erased[(n - 21):(n - 13), , ] <- 1
    for (img in list(st, erased, st[1:(n - 12), , ], tf_jpeg(erased, 70))) {
      got <- extract_watermark(img)
      expect_true(is.null(got) || got %in% c(a, b),
                  label = sprintf("decoded %s from %s over %s", format(got), a, b))
    }
    expect_identical(extract_watermark(erased), a)
  }
})

test_that("narrow, high-resolution figures keep both rows within reach", {
  skip_if_no_raster()
  # The rows are 2.2 mm apart, which is more bit pitches the narrower the
  # figure: about 8.5 at 1.5 in wide, 12.7 at 1 in.
  for (s in list(c(1.5, 1.2, 600), c(1, 0.8, 600))) {
    img <- render_plot(base_plot() + watermark_dots(v4),
                       width = s[1], height = s[2], dpi = s[3])
    expect_identical(extract_watermark(img), v4, label = paste(s, collapse = " x "))
  }
})

test_that("pixel arrays with missing values are refused clearly", {
  x <- matrix(1, 50, 50)
  x[3, 3] <- NA
  expect_error(extract_watermark(x), "missing")
  expect_null(extract_watermark(array(1, c(1, 300, 3))))
  expect_null(extract_watermark(array(1, c(300, 1, 3))))
})

