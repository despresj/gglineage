# A/B a decoder change against a recorded sweep: re-run the same IDs, plot,
# widths and transforms as a CSV from tools/uuid-measure.R and print, per
# cell, the recorded result next to the new one.
#
# Usage: Rscript tools/uuid-ab.R before.csv [plot] [min_width]

suppressPackageStartupMessages({
  library(ggplot2)
  pkgload::load_all(".", quiet = TRUE)
})
source("tests/testthat/helper-transforms.R")
args <- commandArgs(trailingOnly = TRUE)
before <- read.csv(args[1], stringsAsFactors = FALSE)
plot_name <- if (length(args) >= 2) args[2] else "scatter"
min_width <- if (length(args) >= 3) as.integer(args[3]) else 360L
before <- before[before$plot == plot_name & before$width >= min_width, ]

plots <- list(
  scatter = ggplot(mtcars, aes(wt, mpg)) + geom_point(),
  legend = ggplot(mpg, aes(displ, hwy, colour = drv)) + geom_point() +
    facet_wrap(~year) + theme(legend.position = "bottom") +
    labs(title = "Fuel economy", caption = "Source: EPA")
)
transforms <- list(
  resize = function(x, w) tf_resize_to_width(x, w),
  jpeg75 = function(x, w) tf_jpeg(tf_resize_to_width(x, w), 75),
  jpeg50 = function(x, w) tf_jpeg(tf_resize_to_width(x, w), 50),
  jpeg35 = function(x, w) tf_jpeg(tf_resize_to_width(x, w), 35),
  pad_jpeg50 = function(x, w) tf_jpeg(tf_pad(tf_resize_to_width(x, w), 40), 50),
  shot_chain = function(x, w) {
    tf_jpeg(tf_resize_to_width(tf_pad(tf_resize(x, 2), 80), w + 80), 80)
  }
)

before$after <- NA_character_
for (id in unique(before$id)) {
  expected <- if (grepl("-.*-.*-", id)) tolower(id) else id
  img <- render_plot(plots[[plot_name]] + watermark_dots(id), width = 7, height = 5,
                     dpi = 150)
  sel <- which(before$id == id)
  for (i in sel) {
    got <- extract_watermark(suppressWarnings(transforms[[before$transform[i]]](img, before$width[i])))
    before$after[i] <- if (is.null(got)) "none" else if (identical(got, expected)) "exact" else "WRONG"
  }
  cat(id, "done\n")
}

cell <- function(r) {
  b <- sum(r$result == "exact")
  a <- sum(r$after == "exact")
  sprintf("%d>%d%s", b, a, if (any(r$after == "WRONG")) " WRONG" else "")
}
widths <- sort(unique(before$width), decreasing = TRUE)
for (kind in unique(before$kind)) {
  cat(sprintf("\n### %s (before>after, of %d)\n\n", kind, length(unique(before$id[before$kind == kind]))))
  cat("| transform |", paste(widths, collapse = " | "), "|\n")
  cat("|---|", paste(rep("---:", length(widths)), collapse = "|"), "|\n")
  for (tn in names(transforms)) {
    cells <- vapply(widths, function(w) {
      cell(before[before$kind == kind & before$transform == tn & before$width == w, ])
    }, character(1))
    cat("|", tn, "|", paste(cells, collapse = " | "), "|\n")
  }
}
cat(sprintf("\nTotals: before %d, after %d exact of %d; wrong after: %d\n",
            sum(before$result == "exact"), sum(before$after == "exact"), nrow(before),
            sum(before$after == "WRONG")))
