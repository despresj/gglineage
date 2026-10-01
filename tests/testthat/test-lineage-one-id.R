# One figure, one ID. A plot that carried two different IDs (a strip and a
# second strip, or a strip and tiles) could be traced to either, and a file
# whose metadata named one ID while its dots carried another would send a
# lookup to the wrong record. These are errors, never silent.

uuid_a <- "5d0c7e7a-3f4b-4c55-a1d2-9e8f7a6b5c4d"
uuid_b <- "a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d"

test_that("a second, different ID on a plot is an error, for every combination", {
  ids <- list(text = "RUN-42", packed = "K7Q2M9XD", uuid = uuid_a)
  others <- list(text = "RUN-43", packed = "ZZZZZZZZ", uuid = uuid_b)
  for (a in names(ids)) {
    p <- base_plot() + watermark_dots(ids[[a]])
    for (b in names(others)) {
      expect_error(p + watermark_dots(others[[b]]), "already carries",
                   label = paste(a, "then", b))
      expect_error(add_watermark(p, others[[b]]), "already carries")
    }
  }
  # Tiles and strip in either order.
  expect_error(base_plot() + watermark_tiles("TILE-A") + watermark_dots("DOTS-B"),
               "already carries")
  expect_error(base_plot() + watermark_dots("DOTS-B") + watermark_tiles("TILE-A"),
               "already carries")
  expect_error(base_plot() + watermark_tiles("TILE-A") + watermark_tiles("TILE-B"),
               "already carries")
  # The message names both IDs.
  expect_error(base_plot() + watermark_dots("RUN-42") + watermark_dots("RUN-43"),
               "RUN-42.*RUN-43")
})

test_that("the same ID again changes nothing; strip plus tiles with one ID is fine", {
  p <- base_plot() + watermark_dots("RUN-42")
  again <- p + watermark_dots("RUN-42")
  expect_length(again$layers, length(p$layers))
  # A UUID is compared in canonical form, whatever case or wrapping it came in.
  u <- base_plot() + watermark_dots(uuid_a)
  expect_length((u + watermark_dots(toupper(uuid_a)))$layers, length(u$layers))
  expect_length((u + watermark_dots(paste0("{", uuid_a, "}")))$layers, length(u$layers))
  both <- base_plot() + watermark_tiles("RUN-42") + watermark_dots("RUN-42")
  expect_length(both$layers, 3L)
  expect_no_error(ggplotGrob(both))
})

test_that("plot_watermark_id() reports the ID a plot carries", {
  expect_null(plot_watermark_id(base_plot()))
  expect_null(plot_watermark_id(NULL))
  expect_identical(plot_watermark_id(base_plot() + watermark_dots(toupper(uuid_a))), uuid_a)
  expect_identical(plot_watermark_id(base_plot() + watermark_tiles("T1")), "T1")
  # Visible text is not an ID.
  expect_null(plot_watermark_id(base_plot() + watermark_text("DRAFT")))
})

test_that("ggsave_watermark() never writes metadata that disagrees with the dots", {
  skip_if_no_raster()
  file <- tempfile(fileext = ".png")
  on.exit(unlink(file))
  marked <- base_plot() + watermark_dots("RUN-42")
  # A different ID is refused before anything is written, with or without dots.
  expect_error(ggsave_watermark(file, marked, id = "OTHER-7", width = 5, height = 4, dpi = 100),
               "already carries")
  expect_error(ggsave_watermark(file, marked, id = "OTHER-7", dots = FALSE,
                                width = 5, height = 4, dpi = 100),
               "already carries")
  expect_error(ggsave_watermark(file, base_plot() + watermark_tiles("TILE-A"), id = "SAVE-B",
                                width = 5, height = 4, dpi = 100),
               "already carries")
  expect_false(file.exists(file))
  # Without an ID, the plot's own is used, so file, metadata and dots agree.
  id <- ggsave_watermark(file, marked, width = 5, height = 4, dpi = 100)
  expect_identical(id, "RUN-42")
  expect_identical(read_watermark_metadata(file)$id, "RUN-42")
  expect_identical(extract_watermark(file), "RUN-42")
  # Tiles-only plot: the strip gets the tiles' ID.
  id <- ggsave_watermark(file, base_plot() + watermark_tiles("TILE-A"),
                         width = 6, height = 5, dpi = 120)
  expect_identical(id, "TILE-A")
  expect_identical(extract_watermark(file), "TILE-A")
  # Same ID given explicitly, in another case for a UUID.
  u <- base_plot() + watermark_dots(uuid_a)
  id <- ggsave_watermark(file, u, id = toupper(uuid_a), width = 7, height = 5, dpi = 150)
  expect_identical(id, uuid_a)
  expect_identical(read_watermark_metadata(file)$id, uuid_a)
  expect_identical(extract_watermark(file), uuid_a)
  # dots = FALSE on an already marked plot still records the plot's ID.
  id <- ggsave_watermark(file, marked, dots = FALSE, width = 5, height = 4, dpi = 100)
  expect_identical(read_watermark_metadata(file)$id, "RUN-42")
  expect_identical(extract_watermark(file), "RUN-42")
})

test_that("metadata that could not be read back as written is refused up front", {
  file <- tempfile(fileext = ".png")
  on.exit(unlink(file))
  save <- function(metadata) {
    ggsave_watermark(file, base_plot(), id = "A1", metadata = metadata,
                     width = 4, height = 3, dpi = 72)
  }
  # PNG keywords hold 79 bytes; ours carry a 10-byte prefix.
  expect_error(save(stats::setNames(list("v"), strrep("k", 70))), "69 bytes")
  expect_error(save(list(a = "1", a = "2")), "more than once")
  expect_error(save(list(a = list(b = 1))), "vector")
  expect_error(save(list(f = function() 1)), "vector")
  expect_false(file.exists(file))
  skip_if_no_raster()
  save(stats::setNames(list("v"), strrep("k", 69)))
  expect_identical(read_watermark_metadata(file)[[strrep("k", 69)]], "v")
})
