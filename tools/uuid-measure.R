# Robustness sweep for the UUID work: pass rate of extract_watermark() by
# pixel width x transform, for 8-character wm_id() frames and UUID frames.
#
# Usage (from the package root):
#   Rscript tools/uuid-measure.R [n_ids] [out.csv]
#
# Set GGLINEAGE_UUID_PROXY=1 to measure a 200-bit single-row frame using a
# 16-byte text ID (the frame geometry is identical to a single-row UUID),
# which works with the pre-UUID codec. Otherwise real UUIDs are used.

suppressPackageStartupMessages({
  library(ggplot2)
  pkgload::load_all(".", quiet = TRUE)
})
source("tests/testthat/helper-transforms.R")

args <- commandArgs(trailingOnly = TRUE)
n_ids <- if (length(args) >= 1) as.integer(args[1]) else 4L
out_csv <- if (length(args) >= 2) args[2] else file.path(tempdir(), "uuid-measure.csv")
proxy <- identical(Sys.getenv("GGLINEAGE_UUID_PROXY"), "1")

set.seed(20260929)
hex <- c(0:9, letters[1:6])
rand_uuid <- function() {
  x <- sample(hex, 32, replace = TRUE)
  x[13] <- "4"; x[17] <- sample(c("8", "9", "a", "b"), 1)
  paste0(paste(x[1:8], collapse = ""), "-", paste(x[9:12], collapse = ""), "-",
         paste(x[13:16], collapse = ""), "-", paste(x[17:20], collapse = ""), "-",
         paste(x[21:32], collapse = ""))
}
rand_text16 <- function() {
  # 16 bytes, never all-base32 (lowercase present), so it is a 200-bit frame.
  paste(sample(c(letters, 0:9), 16, replace = TRUE), collapse = "")
}

kinds <- list(
  short8 = list(make = function() wm_id(8), label = "wm_id(8), 112-bit row"),
  uuid = if (proxy) {
    list(make = rand_text16, label = "16-byte text (200-bit single-row proxy)")
  } else {
    list(make = rand_uuid, label = "UUID")
  }
)

plots <- list(
  scatter = ggplot(mtcars, aes(wt, mpg)) + geom_point(),
  legend = ggplot(mpg, aes(displ, hwy, colour = drv)) + geom_point() +
    facet_wrap(~year) + theme(legend.position = "bottom") +
    labs(title = "Fuel economy", caption = "Source: EPA")
)

widths <- c(1050, 800, 640, 552, 480, 430, 400, 360, 320, 300, 280, 260, 240, 220)
transforms <- list(
  resize = function(x, w) tf_resize_to_width(x, w),
  jpeg75 = function(x, w) tf_jpeg(tf_resize_to_width(x, w), 75),
  jpeg50 = function(x, w) tf_jpeg(tf_resize_to_width(x, w), 50),
  jpeg35 = function(x, w) tf_jpeg(tf_resize_to_width(x, w), 35),
  pad_jpeg50 = function(x, w) tf_jpeg(tf_pad(tf_resize_to_width(x, w), 40), 50),
  shot_chain = function(x, w) {
    # Retina screenshot with chrome, then shrunk to the target and JPEG'd.
    tf_jpeg(tf_resize_to_width(tf_pad(tf_resize(x, 2), 80), w + 80), 80)
  }
)

rows <- list()
t0 <- Sys.time()
for (kind in names(kinds)) {
  for (i in seq_len(n_ids)) {
    id <- kinds[[kind]]$make()
    expected <- if (kind == "uuid" && !proxy) tolower(id) else id
    for (pn in names(plots)) {
      img <- render_plot(plots[[pn]] + watermark_dots(id), width = 7, height = 5,
                         dpi = 150)
      for (w in widths) {
        for (tn in names(transforms)) {
          got <- extract_watermark(suppressWarnings(transforms[[tn]](img, w)))
          rows[[length(rows) + 1L]] <- data.frame(
            kind = kind, id = id, plot = pn, width = w, transform = tn,
            result = if (is.null(got)) "none" else if (identical(got, expected)) "exact" else "WRONG",
            stringsAsFactors = FALSE
          )
        }
      }
      cat(sprintf("[%s] %s %s %s done (%.0fs)\n", format(Sys.time(), "%H:%M:%S"),
                  kind, i, pn, as.numeric(Sys.time() - t0, units = "secs")))
    }
  }
}
res <- do.call(rbind, rows)
write.csv(res, out_csv, row.names = FALSE)

summ <- aggregate(cbind(pass = res$result == "exact", wrong = res$result == "WRONG") ~
                    kind + transform + width, res, sum)
summ$n <- aggregate(result ~ kind + transform + width, res, length)$result
summ <- summ[order(summ$kind, summ$transform, -summ$width), ]

cat("\n## Pass counts (exact / n) by width; any WRONG is flagged\n\n")
for (kind in names(kinds)) {
  cat(sprintf("\n### %s\n\n", kinds[[kind]]$label))
  cat("| transform |", paste(widths, collapse = " | "), "|\n")
  cat("|---|", paste(rep("---:", length(widths)), collapse = "|"), "|\n")
  for (tn in names(transforms)) {
    cells <- vapply(widths, function(w) {
      r <- summ[summ$kind == kind & summ$transform == tn & summ$width == w, ]
      if (nrow(r) == 0) return("-")
      paste0(r$pass, "/", r$n, if (r$wrong > 0) sprintf(" (%d WRONG)", r$wrong) else "")
    }, character(1))
    cat("|", tn, "|", paste(cells, collapse = " | "), "|\n")
  }
}
cat(sprintf("\nWrong IDs in total: %d of %d decodes\n", sum(res$result == "WRONG"), nrow(res)))
cat(sprintf("Wall time: %.0f s\n", as.numeric(Sys.time() - t0, units = "secs")))
cat("CSV:", out_csv, "\n")
