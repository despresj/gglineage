# Bit-error profile near the decoding limit, to decide whether forward error
# correction is worth its bits. For each transformed image, sample the frame
# at its known geometry (the decoder's own sampler, all edge nudges, rows
# around the true dot row) and report the smallest Hamming distance to the
# true frame. If failures near the cliff show a few wrong bits, a small
# BCH/RS code would rescue them; if they show dozens, it would not.
#
# Usage: Rscript tools/uuid-bit-errors.R [n_ids]

suppressPackageStartupMessages({
  library(ggplot2)
  pkgload::load_all(".", quiet = TRUE)
})
source("tests/testthat/helper-transforms.R")
args <- commandArgs(trailingOnly = TRUE)
n_ids <- if (length(args) >= 1) as.integer(args[1]) else 3L
set.seed(7)

frames <- list(
  bits112 = function() wm_id(8),
  bits200 = function() paste(sample(c(letters, 0:9), 16, replace = TRUE), collapse = "")
)
widths <- c(800, 700, 640, 600, 552, 520, 480, 430, 400, 360, 320)
transforms <- list(
  resize = function(x, w) tf_resize_to_width(x, w),
  jpeg50 = function(x, w) tf_jpeg(tf_resize_to_width(x, w), 50),
  jpeg35 = function(x, w) tf_jpeg(tf_resize_to_width(x, w), 35)
)

# Smallest Hamming distance between the sampled frame and `bits`, over rows
# near the true dot row, single and 3-row signals, and every edge nudge.
min_errors <- function(img, bits, dpi_scale) {
  gray <- as_gray(img)
  n <- nrow(gray)
  w <- ncol(gray)
  k <- 2L * (w %/% 16L) + 1L
  nb <- length(bits)
  left <- dots_inset * w + 0.5
  right <- (1 - dots_inset) * w + 0.5
  true_row <- n - dots_offset_mm / 25.4 * 150 * dpi_scale + 0.5
  best <- Inf
  where <- NULL
  for (r in max(2, floor(true_row) - 3):min(n - 1, ceiling(true_row) + 3)) {
    for (rows in list(r, (r - 1L):(r + 1L))) {
      signal <- colMeans(gray[rows, , drop = FALSE])
      diff <- signal - local_background(signal, k, exact = TRUE)
      sync <- sample_signal(diff, left + 2 * ((right - left) / (nb - 1)) * (0:7),
                            (right - left) / (nb - 1))
      if (mean(sync) < 0) diff <- -diff  # orient so dots read positive
      for (dl in edge_nudges) for (dr in edge_nudges) {
        xs <- (left + dl) + (seq_len(nb) - 1) * (right + dr - left - dl) / (nb - 1)
        v <- sample_signal(diff, xs, (right + dr - left - dl) / (nb - 1))
        read <- slice_bits(v)
        if (is.null(read)) next
        e <- sum(read != bits)
        if (e < best) {
          best <- e
          where <- which(read != bits)
        }
      }
    }
  }
  list(errors = best, where = where)
}

out <- list()
for (fk in names(frames)) {
  for (i in seq_len(n_ids)) {
    id <- frames[[fk]]()
    bits <- encode_bits(id)
    img <- render_plot(ggplot(mtcars, aes(wt, mpg)) + geom_point() + watermark_dots(id),
                       width = 7, height = 5, dpi = 150)
    for (w in widths) for (tn in names(transforms)) {
      t_img <- suppressWarnings(transforms[[tn]](img, w))
      got <- extract_watermark(t_img)
      me <- min_errors(t_img, bits, w / 1050)
      out[[length(out) + 1L]] <- data.frame(
        frame = fk, id = i, width = w, transform = tn,
        decoded = !is.null(got) && identical(got, id),
        wrong = !is.null(got) && !identical(got, id),
        min_errors = me$errors,
        err_in_payload = sum(me$where > 24 & me$where <= length(bits) - 48),
        stringsAsFactors = FALSE
      )
    }
    cat(fk, i, "done\n")
  }
}
res <- do.call(rbind, out)
write.csv(res, file.path(tempdir(), "uuid-bit-errors.csv"), row.names = FALSE)
cat("\n## Minimum bit errors at the true geometry (per id: decoded? errors)\n\n")
for (fk in names(frames)) for (tn in names(transforms)) {
  cat(sprintf("\n%s / %s\n", fk, tn))
  cat("| width |", paste(sprintf("id%d", seq_len(n_ids)), collapse = " | "), "|\n")
  cat("|---|", paste(rep("---", n_ids), collapse = "|"), "|\n")
  for (w in widths) {
    r <- res[res$frame == fk & res$transform == tn & res$width == w, ]
    cells <- sprintf("%s %s", ifelse(r$decoded, "ok", ifelse(r$wrong, "WRONG", "fail")),
                     ifelse(is.finite(r$min_errors), r$min_errors, "-"))
    cat("|", w, "|", paste(cells, collapse = " | "), "|\n")
  }
}
cat("\nCSV:", file.path(tempdir(), "uuid-bit-errors.csv"), "\n")
