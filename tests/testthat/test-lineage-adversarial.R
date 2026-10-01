# Adversarial tests of what an ID attaches to. The ID belongs to the figure,
# not to rows of its data: whatever is done to the data before plotting, the
# watermark carries the same ID and leaves the data untouched, and whatever
# is done to the image afterwards, a decode names an ID that was drawn there
# or nothing.

lineage_id <- "6f1c9a2e-3b4d-4e8f-9a1b-2c3d4e5f6a7b"

# A frame with the column types and ugliness real data has: a human-visible
# key that repeats, missing values, factors, dates and times.
ugly_frame <- function() {
  set.seed(11)
  n <- 40
  data.frame(
    key = sample(c("north", "south", "east"), n, replace = TRUE),
    x = round(stats::runif(n, 0, 10), 2),
    y = stats::rnorm(n, 50, 10),
    grp = factor(sample(c("a", "b", "c"), n, replace = TRUE), levels = c("c", "b", "a", "unused")),
    day = as.Date("2026-01-01") + sample(0:90, n, replace = TRUE),
    when = as.POSIXct("2026-01-01 00:00", tz = "UTC") + sample(0:1e6, n),
    flag = sample(c(TRUE, FALSE, NA), n, replace = TRUE),
    stringsAsFactors = FALSE
  )
}

# Data operations that reshape, reorder, duplicate, coerce and perturb rows.
# Each returns a frame and the aesthetics to plot it with.
data_operations <- function() {
  d <- ugly_frame()
  xy <- ggplot2::aes(x, y)
  other <- data.frame(key = c("north", "south", "west"), region = c(1, 2, 3))
  list(
    shuffled = list(d[sample(nrow(d)), ], xy),
    filtered = list(d[d$x > 5, ], xy),
    empty = list(d[0, ], xy),
    single_row = list(d[1, ], xy),
    duplicated_rows = list(d[rep(1:5, each = 4), ], xy),
    duplicated_values = list(transform(d, x = 1, y = 1), xy),
    row_bound = list(rbind(d, d[sample(nrow(d)), ]), xy),
    # Many-to-one join, so rows multiply; unmatched keys drop or fill with NA.
    inner_join = list(merge(d, other, by = "key"), xy),
    outer_join = list(merge(d, other, by = "key", all = TRUE), xy),
    missing_values = list(transform(d, y = ifelse(seq_along(y) %% 3 == 0, NA, y)), xy),
    all_missing = list(transform(d, y = NA_real_), xy),
    numbers_as_text = list(transform(d, x = as.character(x)), xy),
    factor_axis = list(d, ggplot2::aes(grp, y)),
    character_axis = list(d, ggplot2::aes(key, y)),
    logical_axis = list(d, ggplot2::aes(flag, y)),
    date_axis = list(d, ggplot2::aes(day, y)),
    datetime_axis = list(d, ggplot2::aes(when, y)),
    columns_reordered = list(d[, rev(names(d))], xy),
    column_added = list(transform(d, z = x * y), xy),
    columns_dropped = list(d[, c("x", "y")], xy),
    columns_renamed = list(stats::setNames(d, sub("^x$", "dose", names(d))), ggplot2::aes(dose, y)),
    repeated_transforms = list(Reduce(function(acc, i) {
      acc <- acc[sample(nrow(acc)), ]
      acc <- rbind(acc, acc[acc$x > stats::median(acc$x), ])
      transform(acc, y = y + i)
    }, 1:5, d), xy),
    # Augmentation: three jittered descendants of every source row.
    augmented = list(transform(d[rep(seq_len(nrow(d)), each = 3), ],
                               x = x + stats::rnorm(3 * nrow(d), 0, 0.1)), xy),
    perturbed = list(transform(d, y = y * stats::runif(nrow(d), 0.9, 1.1)), xy),
    mixed_batch = list(merge(d[1:10, c("key", "x", "y")],
                             data.frame(key = "west", x = 3, y = 40, extra = "z"),
                             all = TRUE), xy),
    extreme_values = list(transform(d, y = c(-1e300, 1e300, rep(0, nrow(d) - 2))), xy)
  )
}

test_that("the watermark carries the same ID whatever was done to the data", {
  spec <- unclass(watermark_dots(lineage_id))
  for (name in names(data_operations())) {
    op <- data_operations()[[name]]
    p <- ggplot2::ggplot(op[[1]], op[[2]]) + ggplot2::geom_point() + watermark_dots(lineage_id)
    expect_identical(plot_watermark_id(p), lineage_id, label = name)
    layer <- p$layers[[length(p$layers)]]
    expect_identical(layer$geom_params$spec$rows, spec$rows, label = name)
  }
})

test_that("the watermark never alters, reorders or drops the data's rows", {
  for (name in names(data_operations())) {
    op <- data_operations()[[name]]
    p <- ggplot2::ggplot(op[[1]], op[[2]]) + ggplot2::geom_point()
    before <- suppressWarnings(ggplot2::ggplot_build(p))
    after <- suppressWarnings(ggplot2::ggplot_build(p + watermark_dots("TILES-1") +
                                                      watermark_tiles("TILES-1")))
    # Tiles go underneath (first layer), the strip on top (last).
    expect_equal(after$data[[2]], before$data[[1]], label = name)
    expect_identical(nrow(after$plot$data), nrow(op[[1]]), label = name)
    expect_identical(after$plot$data, op[[1]], label = name)
  }
})

test_that("every reshaped plot decodes to its own ID", {
  skip_if_no_raster()
  skip_on_cran()
  ops <- data_operations()
  for (name in names(ops)) {
    p <- ggplot2::ggplot(ops[[name]][[1]], ops[[name]][[2]]) + ggplot2::geom_point() +
      watermark_dots(lineage_id)
    img <- suppressWarnings(render_plot(p))
    expect_identical(extract_watermark(img), lineage_id, label = name)
  }
})

test_that("plots of the same data with different IDs keep their own IDs", {
  skip_if_no_raster()
  skip_on_cran()
  d <- ugly_frame()
  ids <- c("RUN-1", "RUN-2", "6ba7b810-9dad-11d1-80b4-00c04fd430c8", "RUN-1 ")
  # The same rows, shuffled differently for each plot.
  imgs <- lapply(ids, function(id) {
    render_plot(ggplot2::ggplot(d[sample(nrow(d)), ], ggplot2::aes(x, y)) +
                  ggplot2::geom_point() + watermark_dots(id), width = 6, height = 4, dpi = 100)
  })
  got <- vapply(imgs, function(img) extract_watermark(img) %||% NA_character_, "")
  # Exactly as given: "RUN-1 " (trailing space) is not "RUN-1".
  expect_identical(got, ids)
})

test_that("a plot derived from a watermarked plot carries the same ID, as documented", {
  p <- base_plot() + watermark_dots("RUN-42")
  derived <- list(
    relabelled = p + ggplot2::labs(title = "Another figure"),
    new_data = p + transform(mtcars, mpg = rev(mpg)),
    new_layer = p + ggplot2::geom_smooth(method = "lm", formula = y ~ x),
    rethemed = p + ggplot2::theme_bw()
  )
  for (name in names(derived)) {
    expect_identical(plot_watermark_id(derived[[name]]), "RUN-42", label = name)
    # ...so saving one under a new ID is refused rather than split.
    expect_error(ggsave_watermark(tempfile(fileext = ".png"), derived[[name]], id = "RUN-43"),
                 "already carries", label = name)
  }
})

test_that("IDs of the wrong type are refused, not coerced", {
  bad <- list(numeric = 42, integer = 42L, factor = factor("RUN-1"), logical = TRUE,
              missing = NA_character_, empty = character(), two = c("A", "B"),
              list = list("A"), date = as.Date("2026-01-01"), null = NULL,
              raw = charToRaw("A"))
  for (name in names(bad)) {
    expect_error(watermark_dots(bad[[name]]), "single non-empty string", label = name)
    expect_error(watermark_tiles(bad[[name]]), "single non-empty string", label = name)
  }
  expect_error(ggsave_watermark(tempfile(fileext = ".png"), base_plot(), id = factor("X")),
               "single non-empty string")
})

test_that("text IDs keep case, spacing and Unicode form exactly", {
  ids <- c("run-42", "RUN-42", " RUN-42", "RUN-42 ", "résumé", "résumé",
           "図表-1", "a\tb", "0O1Il")
  rows <- lapply(ids, encode_rows)
  decoded <- vapply(rows, decode_rows, "")
  expect_identical(decoded, ids)
  # Every pair is told apart: no two of these share a code.
  expect_identical(length(unique(lapply(rows, unlist))), length(ids))
  # Precomposed and decomposed accents are different IDs, byte for byte.
  expect_false(identical(charToRaw(decoded[5]), charToRaw(decoded[6])))
})

test_that("a saved plot object round-trips through saveRDS and keeps its ID", {
  skip_if_no_raster()
  p <- base_plot() + watermark_dots(lineage_id)
  rds <- tempfile(fileext = ".rds")
  on.exit(unlink(rds))
  # Under pkgload the namespace is not an installed package; R warns so.
  suppressWarnings(saveRDS(p, rds))
  q <- readRDS(rds)
  expect_identical(plot_watermark_id(q), lineage_id)
  # The one-ID rule survives serialisation too.
  expect_error(q + watermark_dots("RUN-1"), "already carries")
  expect_identical(extract_watermark(render_plot(q)), lineage_id)
})

test_that("a mixed batch of files maps every file to its own ID", {
  skip_if_no_raster()
  skip_on_cran()
  set.seed(12)
  dir <- tempfile("batch")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE))
  ids <- c("K7Q2M9XD", "K7Q2M9XE", "run-42", "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
           "6ba7b810-9dad-11d1-80b4-00c04fd430c9", "図-7", "RUN-42")
  d <- ugly_frame()
  manifest <- do.call(rbind, lapply(seq_along(ids), function(i) {
    # Same data, same title, every time: only the ID tells the files apart.
    p <- ggplot2::ggplot(d[sample(nrow(d)), ], ggplot2::aes(x, y)) + ggplot2::geom_point() +
      ggplot2::labs(title = "Figure 1")
    file <- file.path(dir, sprintf("plot-%02d.png", sample(100, 1) + i * 100))
    id <- ggsave_watermark(file, p, id = ids[i], width = 6, height = 4, dpi = 100)
    data.frame(file = file, id = id, stringsAsFactors = FALSE)
  }))
  # Copies under new names, and a JPEG re-encode (metadata lost), join the batch.
  copy <- file.path(dir, "copy-of-3.png")
  file.copy(manifest$file[3], copy)
  jpg <- file.path(dir, "reencoded-5.jpg")
  jpeg::writeJPEG(png::readPNG(manifest$file[5])[, , 1:3], jpg, quality = 0.85)
  expected <- rbind(manifest, data.frame(file = c(copy, jpg), id = manifest$id[c(3, 5)]))
  files <- sample(expected$file)
  decoded <- data.frame(file = files,
                        decoded = vapply(files, function(f) extract_watermark(f) %||% NA_character_, ""),
                        meta = vapply(files, function(f) read_watermark_metadata(f)$id %||% NA_character_, ""),
                        stringsAsFactors = FALSE)
  joined <- merge(expected, decoded, by = "file")
  expect_identical(nrow(joined), nrow(expected))
  expect_identical(joined$decoded, joined$id)
  is_jpg <- grepl("\\.jpg$", joined$file)
  expect_identical(joined$meta[!is_jpg], joined$id[!is_jpg])
  expect_true(all(is.na(joined$meta[is_jpg])))
})

# ---- image surgery -----------------------------------------------------------

test_that("mirrored, flipped and rotated copies give NULL, not a misread", {
  skip_if_no_raster()
  skip_on_cran()
  for (id in c(lineage_id, "K7Q2M9XD")) {
    img <- render_plot(base_plot() + watermark_dots(id), width = 6, height = 4, dpi = 100)
    w <- dim(img)[2]
    h <- dim(img)[1]
    for (name in c("mirror", "flip", "rot180", "rot90")) {
      out <- switch(name,
        mirror = img[, w:1, , drop = FALSE],
        flip = img[h:1, , , drop = FALSE],
        rot180 = img[h:1, w:1, , drop = FALSE],
        rot90 = tf_rotate90(img))
      got <- extract_watermark(out)
      expect_true(is.null(got) || identical(got, id),
                  label = sprintf("%s of %s decoded %s", name, id, format(got)))
    }
  }
})

test_that("rows of UUIDs that share a half are never joined across charts", {
  skip_if_no_raster()
  skip_on_cran()
  a <- "5d0c7e7a-3f4b-4c55-a1d2-9e8f7a6b5c4d"
  same_first <- "5d0c7e7a-3f4b-4c55-ffff-000000000000"
  same_second <- "00000000-0000-0000-a1d2-9e8f7a6b5c4d"
  ia <- render_plot(base_plot() + watermark_dots(a), width = 5, height = 3.5)
  h <- dim(ia)[1]
  # At 150 dpi the lower row is about 14 px above the bottom, the upper 27.
  lower <- (h - 20):h
  upper <- (h - 33):(h - 21)
  expect_identical(extract_watermark(ia), a)
  for (other in c(same_first, same_second)) {
    io <- render_plot(base_plot() + watermark_dots(other), width = 5, height = 3.5)
    for (band in list(lower, upper)) {
      mixed <- ia
      mixed[band, , ] <- io[band, , ]
      expect_null(extract_watermark(mixed), label = paste(other, "band", band[1]))
    }
  }
})

test_that("charts side by side or blended decode to one of their own IDs", {
  skip_if_no_raster()
  skip_on_cran()
  a <- "5d0c7e7a-3f4b-4c55-a1d2-9e8f7a6b5c4d"
  b <- "5d0c7e7a-3f4b-4c55-ffff-000000000000"
  ia <- render_plot(base_plot() + watermark_dots(a), width = 6, height = 4, dpi = 100)
  ib <- render_plot(base_plot() + watermark_dots(b), width = 6, height = 4, dpi = 100)
  it <- render_plot(base_plot() + watermark_dots("RUN-42"), width = 6, height = 4, dpi = 100)
  cases <- list(
    "a | b" = list(fuzz_join(ia, ib, FALSE), c(a, b)),
    "b | a" = list(fuzz_join(ib, ia, FALSE), c(a, b)),
    "text | a" = list(fuzz_join(it, ia, FALSE), c(a, "RUN-42")),
    "a | small b" = list(fuzz_join(ia, tf_resize(ib, 0.5), FALSE), c(a, b)),
    "a over b, JPEG" = list(tf_jpeg(fuzz_join(ia, ib, TRUE), 60), c(a, b)),
    "2 x 2 grid" = list(fuzz_join(fuzz_join(ia, ib, FALSE), fuzz_join(it, ia, FALSE), TRUE),
                        c(a, b, "RUN-42")),
    "70/30 blend" = list(0.7 * ia[, , 1:3] + 0.3 * ib[, , 1:3], c(a, b)),
    "70/30 blend with text" = list(0.7 * ia[, , 1:3] + 0.3 * it[, , 1:3], c(a, "RUN-42"))
  )
  for (name in names(cases)) {
    got <- extract_watermark(cases[[name]][[1]])
    expect_true(is.null(got) || got %in% cases[[name]][[2]],
                label = sprintf("%s decoded %s", name, format(got)))
  }
  # Side by side, each chart cut out on its own decodes exactly.
  both <- fuzz_join(ia, ib, FALSE)
  w <- dim(ia)[2]
  expect_identical(extract_watermark(both[, seq_len(w), ]), a)
  expect_identical(extract_watermark(both[, w + seq_len(w), ]), b)
})

test_that("the same UUID on several stacked charts decodes to that UUID", {
  skip_if_no_raster()
  skip_on_cran()
  img <- render_plot(base_plot() + watermark_dots(lineage_id), width = 6, height = 3, dpi = 100)
  stacked <- fuzz_join(fuzz_join(img, img, TRUE), img, TRUE)
  expect_identical(extract_watermark(stacked), lineage_id)
})
