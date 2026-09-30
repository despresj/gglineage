# How far apart should a UUID's two dot rows be? Pass rate of UUID decodes by
# row gap (mm) at a few pixel widths, resized and JPEG'd. The gap is set in
# the loaded namespace, so this runs against the package source in place.
#
# Usage: Rscript tools/uuid-row-gap.R [n_ids]

suppressPackageStartupMessages({
  library(ggplot2)
  pkgload::load_all(".", quiet = TRUE)
})
source("tests/testthat/helper-transforms.R")
args <- commandArgs(trailingOnly = TRUE)
n_ids <- if (length(args) >= 1) as.integer(args[1]) else 4L

gaps <- c(1.6, 2.2, 2.8)
widths <- c(480, 400, 360, 320, 300, 280, 260)
transforms <- list(
  jpeg50 = function(x, w) tf_jpeg(tf_resize_to_width(x, w), 50),
  jpeg35 = function(x, w) tf_jpeg(tf_resize_to_width(x, w), 35),
  pad_jpeg50 = function(x, w) tf_jpeg(tf_pad(tf_resize_to_width(x, w), 40), 50)
)
ids <- replicate(n_ids, wm_uuid())
p <- ggplot(mtcars, aes(wt, mpg)) + geom_point()
ns <- asNamespace("gglineage")
unlockBinding("dots_row_gap_mm", ns)

rows <- list()
for (gap in gaps) {
  assign("dots_row_gap_mm", gap, envir = ns)
  for (id in ids) {
    img <- render_plot(p + watermark_dots(id), width = 7, height = 5, dpi = 150)
    for (w in widths) for (tn in names(transforms)) {
      got <- extract_watermark(transforms[[tn]](img, w))
      rows[[length(rows) + 1L]] <- data.frame(
        gap = gap, id = id, width = w, transform = tn,
        result = if (is.null(got)) "none" else if (identical(got, id)) "exact" else "WRONG"
      )
    }
  }
  cat("gap", gap, "done\n")
}
res <- do.call(rbind, rows)
cat("\n## UUID pass counts by row gap (exact / n)\n")
for (tn in names(transforms)) {
  cat(sprintf("\n%s\n\n| gap (mm) |", tn), paste(widths, collapse = " | "), "|\n")
  cat("|---|", paste(rep("---:", length(widths)), collapse = "|"), "|\n")
  for (gap in gaps) {
    cells <- vapply(widths, function(w) {
      r <- res[res$gap == gap & res$transform == tn & res$width == w, ]
      sprintf("%d/%d%s", sum(r$result == "exact"), nrow(r),
              if (any(r$result == "WRONG")) " WRONG" else "")
    }, character(1))
    cat("|", gap, "|", paste(cells, collapse = " | "), "|\n")
  }
}
cat(sprintf("\nWrong IDs: %d of %d\n", sum(res$result == "WRONG"), nrow(res)))
