#' Recover a dot watermark from an image
#'
#' Scans an image for the dot code written by [watermark_dots()] and decodes
#' it; if no strip is found, looks for the tiles written by
#' [watermark_tiles()]. Works on the original file, screenshots, and
#' recompressed or rescaled copies. The strip needs the bottom of the figure
#' intact; tiles survive crops that keep about two tiles across in each
#' direction of open panel. Rotated images are not supported. When a plot
#' carries both, the strip's ID is returned.
#'
#' Every row of the image is a candidate; a row is accepted only if its start
#' and end sync patterns, length byte and CRC-8 checksum all agree, so false
#' positives are vanishingly rare. Tiles are voted on across every visible
#' copy and accepted only if the CRC-16 passes for exactly one ID.
#'
#' @param image Path to a PNG or JPEG file, or a numeric array of pixel
#'   intensities in `[0, 1]` (height x width, optionally x channels), as
#'   returned by [png::readPNG()] or [jpeg::readJPEG()].
#' @param debug If `TRUE`, report which row decoded and the estimated bit
#'   pitch, or each stage of the tile decoder.
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
  for (r in rev(seq_len(nrow(gray)))) {
    found <- decode_row(gray[r, ])
    if (!is.null(found)) {
      if (debug) {
        message(sprintf(
          "Decoded row %d of %d; %d bits at %.2f px/bit",
          r, nrow(gray), found$n_bits, found$pitch
        ))
      }
      return(found$id)
    }
  }
  if (debug) message("No dot strip found in ", nrow(gray), " rows; trying tiles")
  decode_tiles(gray, debug)
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
  dev <- abs(signal - stats::runmed(signal, k, endrule = "median"))
  # Dots cover roughly a third of the row, so a high quantile sits inside
  # them while ignoring a few extreme pixels (borders, stray text).
  peak <- stats::quantile(dev, 0.85, names = FALSE)
  if (peak < 0.01) return(NULL)
  threshold <- peak / 2

  runs <- rle(dev > threshold)
  ends <- cumsum(runs$lengths)
  starts <- ends - runs$lengths + 1L
  on <- runs$values
  if (sum(on) < 9L) return(NULL)
  centers <- (starts[on] + ends[on]) / 2

  # The start sync puts a dot on every other bit: 8 evenly spaced dots. Lock
  # onto the first such run, skipping stray marks such as a plot border.
  for (i in seq_len(min(6L, length(centers) - 8L))) {
    gaps <- diff(centers[i:(i + 7L)])
    if (all(abs(gaps - stats::median(gaps)) <= 0.25 * stats::median(gaps) + 1)) {
      found <- decode_frame(centers[i:length(centers)], dev, threshold,
                            stats::median(gaps) / 2)
      if (!is.null(found)) return(found)
    }
  }
  NULL
}

decode_frame <- function(centers, dev, threshold, pitch) {
  if (!is.finite(pitch) || pitch < 1.5) return(NULL)
  left <- centers[1]

  try_frame <- function(right, n) {
    xs <- left + (seq_len(n) - 1) * (right - left) / (n - 1)
    id <- decode_bits(sample_bits(dev, xs, threshold, pitch))
    if (is.null(id)) NULL else list(id = id, n_bits = n, pitch = (right - left) / (n - 1))
  }

  # Normal case: the last dot on the row closes the frame.
  right <- centers[length(centers)]
  k <- round(((right - left) / pitch + 1 - 48) / 8)
  for (kk in unique(pmin(pmax(k + c(0L, -1L, 1L), 1L), max_id_bytes))) {
    found <- try_frame(right, frame_bits(kk))
    if (!is.null(found)) return(found)
  }

  # Fallback: other marks share the row (a plot border, a corner label), so
  # try each frame length, closing it on each dot near where it should end.
  # The pitch estimate is only good to a fraction of a pixel, so the window
  # grows with frame length.
  for (kk in seq_len(max_id_bytes)) {
    n <- frame_bits(kk)
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

sample_bits <- function(dev, xs, threshold, pitch) {
  half <- max(0L, floor(pitch * 0.15))
  n <- length(dev)
  vapply(xs, function(x) {
    idx <- round(x) + (-half:half)
    idx <- idx[idx >= 1L & idx <= n]
    as.integer(max(dev[idx]) > threshold)
  }, integer(1))
}
