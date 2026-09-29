#' Recover a dot watermark from an image
#'
#' Scans an image for the dot code written by [watermark_dots()] and decodes
#' it. Works on the original file, screenshots, and recompressed or rescaled
#' copies, as long as the bottom strip of the figure is intact and the image
#' is not rotated.
#'
#' Every row of the image is a candidate; a row is accepted only if its start
#' and end sync patterns, header and 32-bit checksum all agree, so false
#' positives are vanishingly rare.
#'
#' @param image Path to a PNG or JPEG file, or a numeric array of pixel
#'   intensities in `[0, 1]` (height x width, optionally x channels), as
#'   returned by [png::readPNG()] or [jpeg::readJPEG()].
#' @param debug If `TRUE`, report which row decoded and the estimated bit
#'   pitch.
#'
#' @return The embedded ID, or `NULL` if no valid code was found.
#' @export
#' @examples
#' library(ggplot2)
#' p <- ggplot(mtcars, aes(wt, mpg)) + geom_point()
#'
#' file <- tempfile(fileext = ".png")
#' ggsave(file, add_watermark(p, "RUN-42"), width = 6, height = 4, dpi = 150)
#' extract_watermark(file)
extract_watermark <- function(image, debug = FALSE) {
  gray <- as_gray(read_image(image))
  found <- find_watermark(gray)
  if (debug) {
    if (is.null(found)) {
      message("No valid watermark found in ", nrow(gray), " rows")
    } else {
      message(sprintf(
        "Decoded row %d of %d (%s); %d bits at %.2f px/bit",
        found$row, nrow(gray),
        if (found$rows_averaged > 1) "3-row average" else "single row",
        found$n_bits, found$pitch
      ))
    }
  }
  found$id
}

# Scan rows from the bottom up. A dot spans several rows, so the second pass
# averages each row with its neighbours, keeping the dots while cancelling
# compression noise. The last pass handles images too small or compressed for
# the dots to be picked out individually.
find_watermark <- function(gray) {
  n <- nrow(gray)
  for (r in rev(seq_len(n))) {
    found <- decode_row(gray[r, ])
    if (!is.null(found)) return(c(found, row = r, rows_averaged = 1L))
  }
  for (r in rev(seq_len(max(0L, n - 2L))) + 1L) {
    found <- decode_row(colMeans(gray[(r - 1L):(r + 1L), , drop = FALSE]))
    if (!is.null(found)) return(c(found, row = r, rows_averaged = 3L))
  }
  find_at_figure_geometry(gray)
}

# watermark_dots() puts the first and last dots at fixed fractions of the
# figure width, in a row just above its bottom edge. Any rescaled or
# recompressed copy of the saved file keeps those proportions, so read the
# frame exactly where it must be instead of locating dots one by one. This
# works on images too degraded for that search, but not on screenshots padded
# with extra pixels; those rely on the passes above.
find_at_figure_geometry <- function(gray) {
  n <- nrow(gray)
  w <- ncol(gray)
  k <- 2L * (w %/% 16L) + 1L
  if (n < 3L || k < 3L) return(NULL)
  left <- dots_inset * w + 0.5
  right <- (1 - dots_inset) * w + 0.5
  pitches <- (right - left) / (frame_lengths - 1)
  # Start-sync dot positions for every candidate frame length at once.
  sync_x <- outer(2 * (0:7), pitches) + left

  # The dot row sits a few millimetres above the bottom edge.
  for (r in rev(seq(max(2L, floor(0.88 * n)), n - 1L))) {
    for (rows in list(r, (r - 1L):(r + 1L))) {
      signal <- colMeans(gray[rows, , drop = FALSE])
      # Blank rows (most of any margin) can't hold a frame.
      fast <- signal - local_background(signal, k)
      if (stats::quantile(abs(fast), 0.85, names = FALSE) < 0.005) next
      diff <- signal - local_background(signal, k, exact = TRUE)
      sync_dots <- matrix(
        stats::approx(seq_len(w), diff, xout = sync_x, rule = 2)$y,
        nrow = 8L
      )
      polarity <- ifelse(colMeans(sync_dots) < 0, -1, 1)
      # Rank lengths by how strongly their start sync reads, best first.
      for (i in order(abs(colMeans(sync_dots)), decreasing = TRUE)) {
        found <- decode_geometry(polarity[i] * diff, left, right, frame_lengths[i])
        if (!is.null(found)) {
          return(c(found, row = r, rows_averaged = length(rows)))
        }
      }
    }
  }
  NULL
}

read_image <- function(image) {
  if (is.numeric(image) && length(dim(image)) %in% 2:3) return(image)
  if (!is.character(image) || length(image) != 1L) {
    stop("`image` must be a file path or a numeric pixel array.", call. = FALSE)
  }
  if (!file.exists(image)) stop("File not found: ", image, call. = FALSE)

  magic <- readBin(image, "raw", 4L)
  if (identical(magic, as.raw(c(0x89, 0x50, 0x4e, 0x47)))) {
    return(png::readPNG(image))
  }
  if (identical(magic[1:2], as.raw(c(0xff, 0xd8)))) {
    if (!requireNamespace("jpeg", quietly = TRUE)) {
      stop("Reading JPEG files needs the jpeg package: install.packages(\"jpeg\")",
           call. = FALSE)
    }
    return(jpeg::readJPEG(image))
  }
  stop("Unsupported image format (expected PNG or JPEG): ", image, call. = FALSE)
}

as_gray <- function(img) {
  if (length(dim(img)) == 2L) return(img)
  ch <- dim(img)[3]
  gray <- if (ch >= 3L) {
    0.299 * img[, , 1] + 0.587 * img[, , 2] + 0.114 * img[, , 3]
  } else {
    img[, , 1]
  }
  if (ch %in% c(2L, 4L)) {
    # Composite transparency over white, as a viewer would.
    alpha <- img[, , ch]
    gray <- gray * alpha + (1 - alpha)
  }
  gray
}

decode_row <- function(signal) {
  # Compare each pixel with its neighbourhood rather than the whole row, so
  # flat regions of another shade (screenshot borders, UI chrome) are not
  # mistaken for dots.
  k <- 2L * (length(signal) %/% 16L) + 1L
  if (k < 3L) return(NULL)
  dev <- abs(signal - local_background(signal, k))
  # Dots cover roughly a third of the row, so a high quantile sits inside
  # them while ignoring a few extreme pixels (borders, stray text).
  peak <- stats::quantile(dev, 0.85, names = FALSE)
  if (peak < 0.01) return(NULL)

  # Coarse pass: find dot-like runs. These only locate the frame; bits are
  # read afterwards by sub-pixel sampling.
  runs <- rle(dev > peak / 2)
  ends <- cumsum(runs$lengths)
  starts <- ends - runs$lengths + 1L
  on <- runs$values
  if (sum(on) < 9L) return(NULL)
  centers <- (starts[on] + ends[on]) / 2

  # The start sync puts a dot on every other bit: 8 evenly spaced dots. Lock
  # onto the first such run, skipping stray marks such as a plot border.
  exact <- NULL
  for (i in seq_len(min(6L, length(centers) - 8L))) {
    gaps <- diff(centers[i:(i + 7L)])
    if (all(abs(gaps - stats::median(gaps)) <= 0.25 * stats::median(gaps) + 1)) {
      if (is.null(exact)) exact <- signal - local_background(signal, k, exact = TRUE)
      found <- decode_frame(centers[i:length(centers)], exact,
                            stats::median(gaps) / 2)
      if (!is.null(found)) return(found)
    }
  }
  NULL
}

decode_frame <- function(centers, diff, pitch) {
  if (!is.finite(pitch) || pitch < 1.5) return(NULL)
  left <- centers[1]

  # Dots can be darker or lighter than the background (dark themes). Orient
  # the signal so dots are positive, judging by the start sync's dots.
  sync_dots <- sample_signal(diff, left + 2 * pitch * (0:7), pitch)
  signal <- if (mean(sync_dots) < 0) -diff else diff

  try_frame <- function(right, n) decode_geometry(signal, left, right, n)

  # Normal case: the last dot on the row closes the frame.
  right <- centers[length(centers)]
  estimate <- (right - left) / pitch + 1
  for (n in utils::head(frame_lengths[order(abs(frame_lengths - estimate))], 5L)) {
    found <- try_frame(right, n)
    if (!is.null(found)) return(found)
  }

  # Fallback: other marks share the row (a plot border, a corner label), so
  # try each frame length, closing it on each dot near where it should end.
  # The pitch estimate is only good to a fraction of a pixel, so the window
  # grows with frame length.
  for (n in frame_lengths) {
    predicted <- left + (n - 1) * pitch
    window <- 0.03 * (n - 1) * pitch + pitch
    nearby <- centers[abs(centers - predicted) <= window]
    for (right in nearby[order(abs(nearby - predicted))]) {
      found <- try_frame(right, n)
      if (!is.null(found)) return(found)
    }
  }
  NULL
}

# Read an n-bit frame whose first and last dots sit near `left` and `right`.
# `signal` is oriented so dots are positive.
decode_geometry <- function(signal, left, right, n) {
  pitch <- (right - left) / (n - 1)
  at <- function(l, r) l + (seq_len(n) - 1) * (r - l) / (n - 1)
  # Cheap gate: the 32 known sync bits must mostly read correctly before
  # spending time on the rest of the frame.
  sync <- sample_signal(signal, at(left, right)[sync_index(n)], pitch)
  on <- mean(sync[sync_bits == 1L])
  off <- mean(sync[sync_bits == 0L])
  if (!(on > off) || sum((sync > (on + off) / 2) == sync_bits) < 26L) {
    return(NULL)
  }
  # Frame edges are only known to about half a pixel, which is a whole bit's
  # worth of drift on small images. Nudge both edges in quarter-pixel steps
  # until the checksum agrees.
  for (dl in edge_nudges) {
    for (dr in edge_nudges) {
      bits <- slice_bits(sample_signal(signal, at(left + dl, right + dr), pitch))
      id <- if (is.null(bits)) NULL else decode_bits(bits)
      if (!is.null(id)) {
        return(list(id = id, n_bits = n,
                    pitch = (right + dr - left - dl) / (n - 1),
                    left = left + dl, right = right + dr))
      }
    }
  }
  NULL
}

# Running median of the row, used as its local background. The exact version
# shrinks the window towards the row's ends, reading the background from the
# plain margin beside the frame, which keeps the syncs accurate; it is slow,
# so the scan uses the fast version and switches only for rows that look
# like they hold a frame.
local_background <- function(signal, k, exact = FALSE) {
  stats::runmed(signal, k, endrule = if (exact) "median" else "constant")
}

edge_nudges <- c(0, -0.25, 0.25, -0.5, 0.5, -0.75, 0.75, -1, 1)
sync_bits <- c(sync_start, sync_end)
sync_index <- function(n) c(1:16, (n - 15L):n)

# Mean of the signal across the middle of each dot, linearly interpolated
# between pixels so fractional bit positions are read accurately.
sample_signal <- function(signal, xs, pitch) {
  n <- length(signal)
  pos <- outer(xs, c(-0.2, 0, 0.2) * pitch, `+`)
  pos[] <- pmin(pmax(pos, 1), n)
  i <- floor(pos)
  f <- pos - i
  vals <- signal[i] * (1 - f) + signal[pmin(i + 1, n)] * f
  rowMeans(matrix(vals, nrow = length(xs)))
}

# Threshold halfway between the levels the known sync bits actually read at,
# so contrast lost to compression or rescaling is measured, not assumed.
slice_bits <- function(v) {
  known <- v[sync_index(length(v))]
  on <- mean(known[sync_bits == 1L])
  off <- mean(known[sync_bits == 0L])
  if (!(on > off)) return(NULL)
  as.integer(v > (on + off) / 2)
}
