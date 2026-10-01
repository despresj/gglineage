# Width floors by ID length: the narrowest width at which a 7 x 5 in figure
# shrunk losslessly, or shrunk then saved at JPEG quality 50, still decodes
# (that width and every wider one, in 10 px steps). Reported as the worst
# case over random IDs of each kind on two plot types. README.Rmd quotes
# these numbers under "Longer IDs need more width".
#
# Usage (from the package root):
#   Rscript tools/id-length-floors.R [n_ids]
#
# Result on 2026-10-01 (4 IDs x 2 plots per kind; worst case, all trials):
#   wm_id 8        lossless 130 px (120-130)  JPEG 50 290 px (280-290)
#   wm_id 12       lossless 150 px (140-150)  JPEG 50 360 px (350-360)
#   wm_id 16       lossless 170 px (170)      JPEG 50 430 px (390-430)
#   text 16 bytes  lossless 230 px (220-230)  JPEG 50 560 px (540-560)
#   UUID           lossless 160 px (150-160)  JPEG 50 350 px (310-350)

suppressPackageStartupMessages({
  library(ggplot2)
  pkgload::load_all(".", quiet = TRUE)
})
source("tests/testthat/helper-transforms.R")
source("tests/testthat/helper-plots.R")

args <- commandArgs(trailingOnly = TRUE)
n_ids <- if (length(args) >= 1) as.integer(args[1]) else 4L

floor_w <- function(img, id, f = identity) {
  fw <- NA
  for (w in seq(600, 100, by = -10)) {
    got <- extract_watermark(suppressWarnings(f(tf_resize_to_width(img, w))))
    if (!identical(got, id)) break
    fw <- w
  }
  fw
}

set.seed(7)
rand_text <- function(n) {
  paste(sample(c(letters, LETTERS, 0:9, "-", " "), n, TRUE), collapse = "")
}
kinds <- list(
  "wm_id 8" = function() wm_id(8),
  "wm_id 12" = function() wm_id(12),
  "wm_id 16" = function() wm_id(16),
  "text 16 bytes" = function() rand_text(16),
  "UUID" = function() wm_uuid()
)
plots <- list(
  scatter = ggplot(mtcars, aes(wt, mpg)) + geom_point(),
  base = base_plot()
)

for (k in names(kinds)) {
  lossless <- jpeg50 <- integer()
  for (i in seq_len(n_ids)) {
    for (p in plots) {
      id <- kinds[[k]]()
      img <- render_plot(p + watermark_dots(id))
      lossless <- c(lossless, floor_w(img, id))
      jpeg50 <- c(jpeg50, floor_w(img, id, function(x) tf_jpeg(x, 50)))
    }
  }
  cat(sprintf("%-14s lossless %d px (%s)  JPEG 50 %d px (%s)\n", k,
              max(lossless), paste(range(lossless), collapse = "-"),
              max(jpeg50), paste(range(jpeg50), collapse = "-")))
}
