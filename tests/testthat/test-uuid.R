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


# ---- passed around: multi-hop sharing chains --------------------------------
# Pure-R stand-ins for what happens to a screenshot as it travels: shown on a
# web page and screenshotted (page colour around it, 1x/2x/3x), cropped back
# to the chart, recompressed by a chat app (fit to a width, JPEG). The chart's
# box is tracked through every hop so crops land on it. tools/
# uuid-sharing-hammer.R runs the same idea through real Chrome, sips, ffmpeg
# and libwebp.

share_state <- function(img) list(img = img, box = c(1, 1, dim(img)[2], dim(img)[1]))

hop_screenshot <- function(st, chart_px, scale = 1, page = 1) {
  img <- tf_resize_to_width(st$img, chart_px * scale / (st$box[3] - st$box[1] + 1) * dim(st$img)[2])
  s <- dim(img)[2] / dim(st$img)[2]
  off <- round(c(24, 96) * scale)
  w <- max(round(1280 * scale), dim(img)[2] + 2 * off[1])
  out <- array(page, c(dim(img)[1] + off[2] + off[1], w, 3))
  out[off[2] + seq_len(dim(img)[1]), off[1] + seq_len(dim(img)[2]), ] <- img[, , 1:3]
  list(img = out, box = c(off[1] + (st$box[c(1, 3)] - 1) * s + 1, off[2] + (st$box[c(2, 4)] - 1) * s + 1)[c(1, 3, 2, 4)])
}

hop_crop_to_chart <- function(st, margin = 12) {
  b <- round(st$box)
  x <- max(1, b[1] - margin):min(dim(st$img)[2], b[3] + margin)
  y <- max(1, b[2] - margin):min(dim(st$img)[1], b[4] + margin)
  list(img = st$img[y, x, , drop = FALSE], box = st$box - c(x[1] - 1, y[1] - 1, x[1] - 1, y[1] - 1))
}

hop_platform <- function(st, max_w, quality) {
  s <- min(1, max_w / dim(st$img)[2])
  img <- if (s < 1) tf_resize(st$img, s) else st$img
  list(img = tf_jpeg(img, quality), box = st$box * s)
}

chart_width <- function(st) st$box[3] - st$box[1]

test_that("UUIDs survive being passed around: screenshot, crop, recompress, repeat", {
  skip_if_no_raster()
  skip_if_not_installed("jpeg")
  skip_on_cran()
  chains <- list(
    "dark page 800px -> X -> crop -> email -> retina shot on white -> halved" = function(st) {
      st <- hop_screenshot(st, 800, page = 0.05)
      st <- hop_platform(st, 1200, 85)
      st <- hop_crop_to_chart(st)
      st <- hop_platform(st, 1024, 75)
      st <- hop_screenshot(st, 640, scale = 2, page = 1)
      hop_platform(st, dim(st$img)[2] / 2, 92)
    },
    "phone @3x -> iMessage-ish -> WhatsApp -> grey page 640px -> JPEG 60" = function(st) {
      st <- hop_screenshot(st, 342, scale = 3, page = 1)
      st <- hop_platform(st, 4000, 80)
      st <- hop_platform(st, 1600, 70)
      st <- hop_screenshot(st, 640, page = 0.94)
      hop_platform(st, 4000, 60)
    },
    "retina 2x -> Slack -> X -> crop -> Teams -> email" = function(st) {
      st <- hop_screenshot(st, 640, scale = 2, page = 0.1)
      st <- hop_platform(st, 1600, 88)
      st <- hop_platform(st, 1200, 85)
      st <- hop_crop_to_chart(st, margin = 4)
      st <- hop_platform(st, 800, 75)
      hop_platform(st, 1024, 75)
    },
    "five screenshots of screenshots on alternating pages" = function(st) {
      for (i in 1:5) {
        st <- hop_screenshot(st, c(800, 640, 720, 560, 600)[i], scale = c(1, 2, 1, 2, 1)[i],
                             page = c(1, 0.08, 0.94, 0.15, 1)[i])
        st <- hop_platform(st, 1600, 85)
      }
      st
    }
  )
  # Fixed UUIDs (wm_uuid() draws from the OS, so set.seed() can't pin it).
  fixed <- c("4" = "6f1c9a2e-3b4d-4e8f-9a1b-2c3d4e5f6a7b",
             "7" = "01928f4a-7b3c-7d2e-9f10-a1b2c3d4e5f6")
  for (plot_name in c("light", "dark")) {
    for (version in c(4, 7)) {
      id <- fixed[[as.character(version)]]
      p <- if (plot_name == "light") base_plot() + watermark_dots(id) else
        base_plot() + theme_dark() + theme(plot.background = element_rect(fill = "grey10")) +
          watermark_dots(id, colour = "white")
      start <- share_state(render_plot(p))
      for (name in names(chains)) {
        st <- chains[[name]](start)
        expect_gte(chart_width(st), 480)
        expect_identical(extract_watermark(st$img), id,
                         label = sprintf("%s v%d: %s (chart %d px)", plot_name, version, name,
                                         round(chart_width(st))))
      }
    }
  }
})

test_that("random sharing chains never yield a wrong UUID, even far past the limits", {
  skip_if_no_raster()
  skip_if_not_installed("jpeg")
  skip_on_cran()
  set.seed(77)
  id <- wm_uuid()
  start <- share_state(render_plot(base_plot() + watermark_dots(id)))
  for (trial in 1:12) {
    st <- start
    for (h in seq_len(sample(2:6, 1))) {
      st <- switch(sample(c("shot", "crop", "platform"), 1),
        shot = hop_screenshot(st, sample(c(200, 300, 400, 640), 1),
                              scale = sample(c(1, 2), 1), page = runif(1)),
        crop = hop_crop_to_chart(st, margin = sample(0:20, 1)),
        platform = hop_platform(st, sample(c(480, 800, 1200), 1), sample(c(30, 50, 70), 1)))
    }
    got <- extract_watermark(st$img)
    expect_true(is.null(got) || identical(got, id),
                label = sprintf("trial %d decoded %s", trial, format(got)))
  }
})

# ---- repair -----------------------------------------------------------------

# Erase chosen dots (1 bits) from one row of a lossless UUID chart: precise,
# known bit damage for testing repair_uuid_row().
erase_dots <- function(img, found, row_y, bits_to_erase, keep = 0) {
  n <- found$n_bits
  xs <- bit_positions(found$left, found$right, n)
  half_w <- max(2, ceiling(found$pitch * 0.5))
  for (b in bits_to_erase) {
    cols <- max(1, round(xs[b]) - half_w):min(dim(img)[2], round(xs[b]) + half_w)
    # The reported row is one the dots were read on, not their centre:
    # cover a full dot either way, short of the other row (~13 px away).
    rows <- max(1, row_y - 7L):min(dim(img)[1], row_y + 7L)
    # keep = 0 erases the dot; keep = 0.45 leaves it faint and ambiguous.
    img[rows, cols, ] <- 1 - keep * (1 - img[rows, cols, ])
  }
  img
}

test_that("a UUID row with a few lost or faded dots is repaired exactly", {
  skip_if_no_raster()
  skip_on_cran()
  set.seed(31)
  # A fixed UUID, so the damaged bits are the same every run; this one once
  # exposed a pair-check edge case.
  id <- "c0a214cb-66ec-4141-b77e-282a8fbfcb9c"
  img <- render_plot(base_plot() + watermark_dots(id), width = 7, height = 5, dpi = 150)
  found <- find_watermark(as_gray(img))
  expect_identical(found$id, id)
  rows <- encode_rows(id)
  # Damage the partner row (the one found second), in its payload and checks.
  partner_half <- found$frame$half
  victim <- rows[[3L - partner_half]]
  ones <- which(victim == 1L)
  ones <- ones[ones >= 25L & ones <= 120L]
  # Erased dots read as confident zeros (a mark painted over them): up to
  # two anywhere are repaired.
  for (k in 1:2) {
    for (trial in 1:3) {
      damaged <- erase_dots(img, found, found$partner_row, sample(ones, k))
      expect_identical(extract_watermark(damaged), id,
                       label = sprintf("%d erased dots, trial %d", k, trial))
    }
  }
  # Faded dots read ambiguously, as compression damage does: up to four.
  for (k in 3:4) {
    for (trial in 1:3) {
      damaged <- erase_dots(img, found, found$partner_row, sample(ones, k), keep = 0.45)
      expect_identical(extract_watermark(damaged), id,
                       label = sprintf("%d faded dots, trial %d", k, trial))
    }
  }
})

test_that("heavily damaged UUID rows give NULL, never a wrong UUID", {
  skip_if_no_raster()
  skip_on_cran()
  set.seed(32)
  id <- "9d2e7b14-5a3c-4f8e-b1d6-7c0a2e4f9b3d"
  img <- render_plot(base_plot() + watermark_dots(id), width = 7, height = 5, dpi = 150)
  found <- find_watermark(as_gray(img))
  rows <- encode_rows(id)
  for (trial in 1:10) {
    damaged <- img
    for (which_row in c("row", "partner_row")) {
      half <- if (which_row == "row") found$frame$half else 3L - found$frame$half
      ones <- which(rows[[half]] == 1L)
      ones <- ones[ones >= 25L & ones <= 120L]
      damaged <- erase_dots(damaged, found, found[[which_row]], sample(ones, sample(4:12, 1)))
    }
    got <- extract_watermark(damaged)
    expect_true(is.null(got) || identical(got, id),
                label = sprintf("trial %d decoded %s", trial, format(got)))
  }
})
