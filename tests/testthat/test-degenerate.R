# Degenerate inputs: every one must either decode, return NULL for a valid
# image with no mark, or fail with a message that says what is wrong. None
# may crash with an internal error, hang, or return a wrong ID.

test_that("malformed pixel arrays are rejected with a clear message", {
  expect_error(extract_watermark(matrix(NA_real_, 20, 20)), "missing")
  nan <- matrix(1, 20, 20); nan[3, 3] <- NaN
  expect_error(extract_watermark(nan), "missing")
  inf <- matrix(1, 20, 20); inf[3, 3] <- Inf
  expect_error(extract_watermark(inf), "infinite")
  expect_error(extract_watermark(matrix(200L, 20, 20)), "divide by 255")
  expect_error(extract_watermark(matrix(-0.5, 20, 20)), "\\[0, 1\\]")
  expect_error(extract_watermark(array(0.5, c(20, 20, 5))), "5 channels")
  for (bad in list(matrix(TRUE, 5, 5), matrix("a", 5, 5), runif(10),
                   array(0.5, c(4, 4, 3, 2)), data.frame(a = 1), list(1),
                   NULL, NA, NA_character_, character(), c("a.png", "b.png"),
                   as.raster(matrix(0.5, 4, 4)))) {
    expect_error(extract_watermark(bad), "single file path or a numeric pixel array")
  }
})

test_that("tiny, empty and uniform arrays return NULL quickly", {
  for (img in list(matrix(numeric(), 0, 0), matrix(numeric(), 0, 10),
                   matrix(0.5, 1, 1), matrix(runif(500), 1, 500),
                   matrix(runif(500), 500, 1), array(0.5, c(2, 2, 3)),
                   matrix(1, 300, 400), matrix(0, 300, 400),
                   array(0.5, c(50, 50, 2)), array(0, c(50, 50, 4)))) {
    expect_null(extract_watermark(img))
  }
})

test_that("bad files fail with a message naming the problem", {
  dir <- withr_tempfile("")
  dir.create(dir)
  expect_error(extract_watermark(dir), "directory")
  empty <- file.path(dir, "empty.png")
  file.create(empty)
  expect_error(extract_watermark(empty), "empty")
  expect_error(extract_watermark(file.path(dir, "missing.png")), "not found")

  good <- file.path(dir, "good.png")
  png::writePNG(array(1, c(40, 60, 3)), good)
  truncated <- file.path(dir, "truncated.png")
  writeBin(readBin(good, "raw", 60), truncated)
  expect_error(extract_watermark(truncated), "truncated or corrupt")
  junk <- file.path(dir, "junk.jpg")
  writeBin(c(as.raw(c(0xff, 0xd8)), as.raw(1:50)), junk)
  skip_if_not_installed("jpeg")
  expect_error(suppressWarnings(extract_watermark(junk)), "truncated or corrupt")
  gif <- file.path(dir, "x.gif")
  writeBin(charToRaw("GIF89a...."), gif)
  expect_error(extract_watermark(gif), "Unsupported image format")

  # Format is sniffed from the bytes, not the extension.
  misnamed <- file.path(dir, "actually-a.png.jpg")
  file.copy(good, misnamed)
  expect_null(extract_watermark(misnamed))
})

test_that("watermark arguments that could never be read back are errors", {
  expect_error(watermark_dots("A", alpha = 0), "alpha")
  expect_error(watermark_dots("A", alpha = 1.5), "alpha")
  expect_error(watermark_dots("A", alpha = NA), "alpha")
  expect_error(watermark_dots("A", size = 0), "size")
  expect_error(watermark_dots("A", size = -1), "size")
  expect_error(watermark_dots("A", colour = NA), "colour")
  expect_error(watermark_dots("A", colour = "transparent"), "colour")
  expect_error(watermark_dots("A", colour = c("red", "blue")), "colour")
  expect_error(watermark_dots("A", colour = "not-a-colour"), "colour")
  expect_error(watermark_tiles("A", alpha = 0), "alpha")
  expect_error(watermark_tiles("A", pitch = 0), "pitch")
  expect_error(add_watermark(1:3, "A"), "ggplot object")
  expect_no_error(watermark_dots("A", colour = "#FFFFFF80", alpha = 1, size = 5))
})

test_that("IDs with no visible characters are rejected; odd visible ones round-trip", {
  for (blank in c(" ", "   ", "\t", "\n", " ", "​", " ​ ")) {
    expect_error(watermark_dots(blank), "no visible characters")
  }
  for (id in c(" a ", "a\nb", "a\tb", "é", "\U0001F600",
               strrep("\U0001F600", 4), "0", "O", "IL1", "k7q2m9xd")) {
    expect_equal(decode_bits(encode_bits(id)), id)
  }
})

test_that("watermarks decode from every common PNG and JPEG pixel format", {
  skip_if_no_raster()
  skip_on_cran()
  skip_if(Sys.which("ffmpeg") == "", "ffmpeg not available")
  src <- withr_tempfile(".png")
  ggsave(src, base_plot() + watermark_dots("K7Q2M9XD"), width = 7, height = 5, dpi = 150)
  formats <- list(c("rgb48be", "png"), c("pal8", "png"), c("ya8", "png"),
                  c("gray", "png"), c("gray16be", "png"), c("gray", "jpg"),
                  c("yuvj444p", "jpg"), c("yuvj420p", "jpg"))
  for (fmt in formats) {
    out <- withr_tempfile(paste0(".", fmt[2]))
    system2("ffmpeg", c("-loglevel", "error", "-y", "-i", src, "-pix_fmt", fmt[1],
                        if (fmt[2] == "jpg") c("-q:v", "3"), out))
    expect_equal(extract_watermark(out), "K7Q2M9XD", label = paste(fmt, collapse = " "))
  }
})

test_that("coloured and mid-tone backgrounds decode with the default dots", {
  skip_if_no_raster()
  for (fill in c("grey50", "#d62728", "#1f77b4", "#2ca02c", "grey20", "black")) {
    p <- base_plot() + theme(plot.background = element_rect(fill = fill)) +
      watermark_dots("K7Q2M9XD")
    expect_equal(extract_watermark(render_plot(p)), "K7Q2M9XD", label = fill)
  }
})

test_that("large figures decode (dots are sparse relative to the row)", {
  skip_if_no_raster()
  skip_on_cran()
  for (s in list(c(20, 15, 150), c(40, 30, 72), c(16, 4, 150))) {
    img <- render_plot(base_plot() + watermark_dots("K7Q2M9XD"),
                       width = s[1], height = s[2], dpi = s[3])
    expect_equal(extract_watermark(img), "K7Q2M9XD", label = paste(s, collapse = "x"))
  }
  # Sparse dots and a dark screenshot border pull the decoder's contrast
  # estimate in opposite directions; both at once must still work.
  big <- render_plot(base_plot() + watermark_dots("K7Q2M9XD"), width = 20, height = 15, dpi = 150)
  expect_equal(extract_watermark(tf_pad(big, 150, fill = 0.12)), "K7Q2M9XD")
})

test_that("degenerate plots still carry the mark", {
  skip_if_no_raster()
  plots <- list(
    empty = ggplot(),
    zero_rows = ggplot(mtcars[0, ], aes(wt, mpg)) + geom_point(),
    rug = ggplot(faithful, aes(eruptions, waiting)) + geom_point() + geom_rug(sides = "b"),
    many_keys = ggplot(mpg, aes(displ, hwy, colour = model)) + geom_point() +
      theme(legend.position = "bottom")
  )
  for (name in names(plots)) {
    img <- render_plot(plots[[name]] + watermark_dots("K7Q2M9XD"))
    expect_equal(extract_watermark(img), "K7Q2M9XD", label = name)
  }
})

test_that("figures too small to hold the code return NULL, not a wrong ID", {
  skip_if_no_raster()
  for (s in list(c(0.5, 0.5, 300), c(1, 1, 72), c(7, 5, 10))) {
    img <- render_plot(base_plot() + watermark_dots("K7Q2M9XD"),
                       width = s[1], height = s[2], dpi = s[3])
    expect_null(extract_watermark(img), label = paste(s, collapse = "x"))
  }
})

test_that("rendering works on vector devices and inside other layouts", {
  p <- base_plot() + watermark_dots("K7Q2M9XD")
  # PDF is built into R; SVG would need svglite, which isn't a dependency.
  f <- withr_tempfile(".pdf")
  expect_no_error(ggsave(f, p, width = 5, height = 4))
  expect_gt(file.size(f), 0)
  skip_if_no_raster()
  f <- withr_tempfile(".png")
  grDevices::png(f, 1400, 1000, res = 150)
  grid::pushViewport(grid::viewport(x = 0.25, width = 0.5))
  grid::grid.draw(ggplotGrob(p))
  grid::popViewport()
  grDevices::dev.off()
  expect_equal(extract_watermark(f), "K7Q2M9XD")
})

test_that("noise never decodes, and doesn't take forever", {
  skip_on_cran()
  set.seed(99)
  for (i in 1:3) {
    img <- array(stats::runif(300 * 420 * 3), c(300, 420, 3))
    elapsed <- system.time(got <- extract_watermark(img))[["elapsed"]]
    expect_null(got)
    expect_lt(elapsed, 30)
  }
})

test_that("frames with valid syncs but random payloads are rejected", {
  skip_on_cran()
  set.seed(5)
  for (n in c(112, 120, 136, 200)) {
    hits <- vapply(1:3000, function(i) {
      frame <- sample(0:1, n, replace = TRUE)
      frame[1:16] <- sync_start
      frame[(n - 15):n] <- sync_end
      !is.null(decode_bits(frame))
    }, logical(1))
    expect_false(any(hits), label = paste("frame length", n))
  }
})
