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
#' and end sync patterns, header and 32-bit checksum all agree, so false
#' positives are vanishingly rare. A UUID is spread over two such rows, one
#' above the other; each row is checked on its own and against the whole
#' UUID, so a UUID is returned only when both of its rows are read, and
#' halves of two different UUIDs (charts stacked in a report, say) are never
#' joined. Tiles are voted on across every visible copy and accepted only if
#' their CRC-16 passes for exactly one ID.
#'
#' @param image Path to a PNG or JPEG file, or a numeric array of pixel
#'   intensities in `[0, 1]` (height x width, optionally x channels), as
#'   returned by [png::readPNG()] or [jpeg::readJPEG()].
#' @param debug If `TRUE`, report which rows decoded and the estimated bit
#'   pitch, or each stage of the tile decoder.
#'
#' @return The embedded ID as a plain string, or `NULL` if no valid code was
#'   found. Text IDs come back exactly as given. UUIDs come back in canonical
#'   lowercase form (`xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`), and only a UUID
#'   has that form: text IDs are at most 16 bytes, so the two cannot be
#'   confused. Nothing else is returned: the dots carry the ID and nothing
#'   more, so what the ID *means* (the script, data and run behind the plot)
#'   is whatever you recorded against it when you saved the plot.
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
  if (anyNA(gray)) {
    stop("`image` has missing (NA) pixel values.", call. = FALSE)
  }
  found <- find_watermark(gray)
  if (is.null(found)) {
    if (debug) message("No dot strip found in ", nrow(gray), " rows; trying tiles")
    return(decode_tiles(gray, debug))
  }
  if (debug) {
    if (found$kind == "uuid") {
      message(sprintf(
        "Decoded UUID from rows %d and %d of %d (%s); 2 x %d bits at %.2f px/bit",
        found$row, found$partner_row, nrow(gray),
        row_mode(c(found$rows_averaged, found$partner_rows_averaged)),
        found$n_bits, found$pitch
      ))
    } else {
      message(sprintf(
        "Decoded row %d of %d (%s); %d bits at %.2f px/bit",
        found$row, nrow(gray), row_mode(found$rows_averaged),
        found$n_bits, found$pitch
      ))
    }
  }
  found$id
}

row_mode <- function(rows_averaged) {
  paste(ifelse(rows_averaged > 1, "3-row average", "single row"), collapse = " + ")
}

# Scan rows from the bottom up. A dot spans several rows, so the second pass
# averages each row with its neighbours, keeping the dots while cancelling
# compression noise. The last pass handles images too small or compressed for
# the dots to be picked out individually. A text frame is the answer; half a
# UUID is only an answer once the other half of the same UUID is found next
# to it, otherwise the scan goes on (the half may belong to a chart whose
# other row was cropped away, with another chart's code further up).
find_watermark <- function(gray) {
  n <- nrow(gray)
  failed <- character()
  accept <- function(found) {
    if (found$frame$kind == "text") {
      return(c(found, kind = "text", id = found$frame$id))
    }
    # The same row is usually read several times (a dot spans several pixel
    # rows); look for its partner once.
    key <- paste(found$frame$half, paste(found$frame$bytes, collapse = ""),
                 found$frame$pair)
    if (key %in% failed) return(NULL)
    result <- pair_uuid(gray, found)
    if (is.null(result)) failed <<- c(failed, key)
    result
  }
  for (r in rev(seq_len(n))) {
    found <- decode_row(gray[r, ])
    if (!is.null(found)) {
      result <- accept(c(found, row = r, rows_averaged = 1L))
      if (!is.null(result)) return(result)
    }
  }
  for (r in rev(seq_len(max(0L, n - 2L))) + 1L) {
    found <- decode_row(colMeans(gray[(r - 1L):(r + 1L), , drop = FALSE]))
    if (!is.null(found)) {
      result <- accept(c(found, row = r, rows_averaged = 3L))
      if (!is.null(result)) return(result)
    }
  }
  find_at_figure_geometry(gray, accept)
}

# A found UUID half joined with its partner row, or NULL.
pair_uuid <- function(gray, found) {
  partner <- find_partner(gray, found)
  if (is.null(partner)) return(NULL)
  c(found,
    kind = "uuid",
    id = partner$id,
    partner_row = partner$row,
    partner_rows_averaged = partner$rows_averaged)
}

# The other row of a UUID sits directly above the first half (drawn lowest)
# or below the second, at the same horizontal geometry. The rows are 2.2 mm
# apart and a bit pitch is 0.92 / 135 of the figure width, so the gap is
# 323 / (width in mm) pitches: under 16 for any figure wider than 20 mm. Read it at that geometry, nearest rows first, without
# locating its dots afresh. Only a row whose pair check agrees with the
# found half is accepted, so a neighbouring chart's code is passed over.
find_partner <- function(gray, found) {
  n <- nrow(gray)
  w <- ncol(gray)
  k <- background_window(w)
  want <- 3L - found$frame$half
  reach <- ceiling(16 * found$pitch) + 3
  # Row 1 is drawn below row 2, and images are never flipped.
  rows <- if (want == 2L) found$row - seq_len(reach) else found$row + seq_len(reach)
  rows <- rows[rows >= 2L & rows <= n - 1L]
  for (r in rows) {
    for (span in list(r, (r - 1L):(r + 1L))) {
      signal <- colMeans(gray[span, , drop = FALSE])
      # Cheap gate on the median background before the exact one.
      fast <- found$polarity * (signal - local_background(signal, k))
      if (!syncs_agree(fast, found$left, found$right, found$n_bits)) next
      oriented <- oriented_signal(signal, k, found$polarity)
      hit <- decode_geometry(oriented, found$left, found$right, found$n_bits,
                             accept = function(frame) {
                               frame$kind == "uuid" && frame$half == want &&
                                 !is.null(join_halves(found$frame, frame))
                             })
      if (!is.null(hit)) {
        return(c(hit, id = join_halves(found$frame, hit$frame), row = r,
                 rows_averaged = length(span)))
      }
    }
  }
  NULL
}

join_halves <- function(a, b) {
  halves <- list(a, b)[order(c(a$half, b$half))]
  assemble_uuid(halves[[1]], halves[[2]])
}

# watermark_dots() puts the first and last dots at fixed fractions of the
# figure width, in a row just above its bottom edge. Any rescaled or
# recompressed copy of the saved file keeps those proportions, so read the
# frame exactly where it must be instead of locating dots one by one. This
# works on images too degraded for that search, but not on screenshots padded
# with extra pixels; those rely on the passes above.
find_at_figure_geometry <- function(gray, accept) {
  n <- nrow(gray)
  w <- ncol(gray)
  k <- background_window(w)
  if (n < 3L || k < 3L) return(NULL)
  left <- dots_inset * w + 0.5
  right <- (1 - dots_inset) * w + 0.5
  pitches <- (right - left) / (frame_lengths - 1)
  # Start-sync positions (all 16 bits) for every candidate frame length at
  # once; the dots are the odd rows.
  start_x <- outer(0:15, pitches) + left
  on_bit <- sync_start == 1L

  # The dot row sits a few millimetres above the bottom edge.
  for (r in rev(seq(max(2L, floor(0.88 * n)), n - 1L))) {
    for (rows in list(r, (r - 1L):(r + 1L))) {
      signal <- colMeans(gray[rows, , drop = FALSE])
      # Blank rows (most of any margin) can't hold a frame.
      diff <- signal - local_background(signal, k)
      if (stats::quantile(abs(diff), 0.95, names = FALSE) < 0.005) next
      start <- matrix(
        stats::approx(seq_len(w), diff, xout = start_x, rule = 2)$y,
        nrow = 16L
      )
      contrast <- colMeans(start[on_bit, , drop = FALSE]) -
        colMeans(start[!on_bit, , drop = FALSE])
      polarity <- ifelse(contrast < 0, -1, 1)
      # Cheap gate, as in decode_frame(): skip lengths whose start sync does
      # not read as alternating on/off (13 of 16), before paying for the
      # accurate background. Noisy rows otherwise cost seconds each.
      agree <- vapply(seq_along(frame_lengths), function(i) {
        v <- polarity[i] * start[, i]
        cut <- (mean(v[on_bit]) + mean(v[!on_bit])) / 2
        sum((v > cut) == on_bit)
      }, numeric(1))
      candidates <- which(agree >= 13L)
      oriented <- list()
      # Rank lengths by how strongly their start sync reads, best first.
      for (i in candidates[order(abs(contrast[candidates]), decreasing = TRUE)]) {
        key <- as.character(polarity[i])
        if (is.null(oriented[[key]])) {
          oriented[[key]] <- oriented_signal(signal, k, polarity[i])
        }
        found <- decode_geometry(oriented[[key]], left, right, frame_lengths[i])
        if (!is.null(found)) {
          result <- accept(c(found, polarity = polarity[i], row = r,
                             rows_averaged = length(rows)))
          if (!is.null(result)) return(result)
        }
      }
    }
  }
  NULL
}

read_image <- function(image) {
  if (is.numeric(image) && length(dim(image)) %in% 2:3) return(check_pixels(image))
  if (!is.character(image) || length(image) != 1L || is.na(image)) {
    stop("`image` must be a single file path or a numeric pixel array.",
         call. = FALSE)
  }
  if (dir.exists(image)) {
    stop("`image` is a directory, not an image file: ", image, call. = FALSE)
  }
  if (!file.exists(image)) stop("File not found: ", image, call. = FALSE)
  if (file.size(image) == 0) stop("File is empty: ", image, call. = FALSE)

  magic <- readBin(image, "raw", 4L)
  read <- function(reader, format) {
    tryCatch(reader(image), error = function(e) {
      stop("Could not read ", format, " file ", image, " (",
           conditionMessage(e), "). Is it truncated or corrupt?", call. = FALSE)
    })
  }
  if (identical(magic, as.raw(c(0x89, 0x50, 0x4e, 0x47)))) {
    return(read(png::readPNG, "PNG"))
  }
  if (identical(magic[1:2], as.raw(c(0xff, 0xd8)))) {
    if (!requireNamespace("jpeg", quietly = TRUE)) {
      stop("Reading JPEG files needs the jpeg package: install.packages(\"jpeg\")",
           call. = FALSE)
    }
    return(read(jpeg::readJPEG, "JPEG"))
  }
  stop("Unsupported image format (expected PNG or JPEG): ", image,
       ". Convert it first, e.g. with `sips -s format png` or ffmpeg.",
       call. = FALSE)
}

# Validate a user-supplied pixel array: intensities in [0, 1], height x width
# with 1 (gray), 2 (gray + alpha), 3 (RGB) or 4 (RGBA) channels. File readers
# already guarantee this; arrays from elsewhere often come as 0-255.
check_pixels <- function(img) {
  if (length(dim(img)) == 3L && !dim(img)[3] %in% 1:4) {
    stop("`image` has ", dim(img)[3], " channels; expected 1 (gray), 2 (gray + ",
         "alpha), 3 (RGB) or 4 (RGBA).", call. = FALSE)
  }
  if (anyNA(img)) stop("`image` has missing (NA) pixel values.", call. = FALSE)
  if (any(is.infinite(img))) {
    stop("`image` has infinite pixel values.", call. = FALSE)
  }
  if (length(img) > 0L) {
    range <- range(img)
    if (range[1] < -1e-6 || range[2] > 1 + 1e-6) {
      stop("`image` pixel values must be in [0, 1]; these run from ",
           format(range[1]), " to ", format(range[2]), ".",
           if (range[2] <= 255 && range[1] >= 0) " For 0-255 data, divide by 255.",
           call. = FALSE)
    }
  }
  img
}

as_gray <- function(img) {
  if (length(dim(img)) == 2L) return(img)
  ch <- dim(img)[3]
  layer <- function(i) img[, , i, drop = FALSE][, , 1L]
  gray <- if (ch >= 3L) {
    0.299 * layer(1L) + 0.587 * layer(2L) + 0.114 * layer(3L)
  } else {
    layer(1L)
  }
  if (ch %in% c(2L, 4L)) {
    # Composite transparency over white, as a viewer would.
    alpha <- layer(ch)
    gray <- gray * alpha + (1 - alpha)
  }
  matrix(gray, dim(img)[1], dim(img)[2])
}

decode_row <- function(signal) {
  # Compare each pixel with its neighbourhood rather than the whole row, so
  # flat regions of another shade (screenshot borders, UI chrome) are not
  # mistaken for dots.
  k <- background_window(length(signal))
  if (k < 3L) return(NULL)
  diff <- signal - local_background(signal, k)
  dev <- abs(diff)
  # Dots usually cover about a third of the row, so the 85th percentile sits
  # inside them while ignoring borders, stray text and screenshot chrome
  # (which can fill a tenth of the row). On large figures the dots, capped at
  # their maximum size, cover far less, the 85th percentile is plain
  # background, and the 95th is needed instead.
  peak <- stats::quantile(dev, 0.85, names = FALSE)
  if (peak < 0.01) peak <- stats::quantile(dev, 0.95, names = FALSE)
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
  # Oriented rows are costly and the same for every lock attempt.
  oriented <- list()
  orient <- function(polarity) {
    key <- as.character(polarity)
    if (is.null(oriented[[key]])) {
      oriented[[key]] <<- oriented_signal(signal, k, polarity)
    }
    oriented[[key]]
  }
  for (i in seq_len(min(6L, length(centers) - 8L))) {
    gaps <- diff(centers[i:(i + 7L)])
    if (all(abs(gaps - stats::median(gaps)) <= 0.25 * stats::median(gaps) + 1)) {
      found <- decode_frame(centers[i:length(centers)], diff, orient,
                            stats::median(gaps) / 2)
      if (!is.null(found)) return(found)
    }
  }
  NULL
}

decode_frame <- function(centers, diff, orient, pitch) {
  if (!is.finite(pitch) || pitch < 1.5) return(NULL)
  left <- centers[1]

  # Dots can be darker or lighter than the background (dark themes). Orient
  # the signal so dots are positive, judging by the start sync's dots.
  sync_dots <- sample_signal(diff, left + 2 * pitch * (0:7), pitch)
  polarity <- if (mean(sync_dots) < 0) -1 else 1

  # Cheap check before any frame search, on the fast signal: the start sync
  # itself must read as alternating on/off. Evenly spaced clusters turn up
  # by chance in noisy rows (textures, photos, dense data), and without this
  # check each one costs the accurate background and a search over every
  # frame length. 13 of 16 matches the agreement decode_geometry() demands
  # of both syncs (26 of 32).
  start <- polarity * sample_signal(diff, left + (0:15) * pitch, pitch)
  cut <- (mean(start[sync_start == 1L]) + mean(start[sync_start == 0L])) / 2
  if (sum((start > cut) == (sync_start == 1L)) < 13L) return(NULL)
  oriented <- orient(polarity)

  try_frame <- function(right, n) {
    found <- decode_geometry(oriented, left, right, n)
    if (!is.null(found)) c(found, polarity = polarity)
  }

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
    # The nearest few are enough; in a dense row every cluster is "nearby".
    for (right in utils::head(nearby[order(abs(nearby - predicted))], 3L)) {
      found <- try_frame(right, n)
      if (!is.null(found)) return(found)
    }
  }
  NULL
}

# Read an n-bit frame whose first and last dots sit near `left` and `right`.
# `signal` is oriented so dots are positive. `accept`, if given, must also
# approve the parsed frame before the search stops.
decode_geometry <- function(signal, left, right, n, accept = NULL) {
  pitch <- (right - left) / (n - 1)
  # Cheap gate: the 32 known sync bits must mostly read correctly before
  # spending time on the rest of the frame.
  if (!syncs_agree(signal, left, right, n)) return(NULL)
  # Frame edges are only known to about half a pixel, which is a whole bit's
  # worth of drift on small images. Nudge both edges in quarter-pixel steps
  # until the checksum agrees. The syncs and header of every nudge are read
  # in one pass (a column each); the rest of a frame is read only where
  # those are exactly right, which a regular pattern such as a dotted grid
  # line never is (its header reads 0x55 or 0xAA).
  dl <- rep(edge_nudges, each = length(edge_nudges))
  dr <- rep(edge_nudges, times = length(edge_nudges))
  step <- (right + dr - left - dl) / (n - 1)
  xs <- outer(seq_len(n) - 1, step) + rep(left + dl, each = n)
  idx <- sync_index(n)
  lead <- c(idx, 17:24)
  v <- matrix(sample_signal(signal, xs[lead, , drop = FALSE], pitch), nrow = length(lead))
  on <- colMeans(v[which(sync_bits == 1L), , drop = FALSE])
  off <- colMeans(v[which(sync_bits == 0L), , drop = FALSE])
  threshold <- (on + off) / 2
  bits <- v > rep(threshold, each = length(lead))
  header <- colSums(bits[33:40, , drop = FALSE] * 2L^(0:7))
  plausible <- on > off &
    colSums(bits[1:32, , drop = FALSE] == sync_bits) == 32L &
    header %in% frame_headers(n)
  for (j in which(plausible)) {
    frame <- parse_frame(as.integer(sample_signal(signal, xs[, j], pitch) > threshold[j]))
    if (!is.null(frame) && (is.null(accept) || accept(frame))) {
      return(list(frame = frame, n_bits = n, pitch = step[j],
                  left = left + dl[j], right = right + dr[j]))
    }
  }
  NULL
}

# Header bytes a frame of n bits could carry.
frame_headers <- function(n) {
  c(if ((n - 72L) %% 8L == 0L) (n - 72L) %/% 8L,
    if ((n - 72L) %% 5L == 0L) 128L + (n - 72L) %/% 5L,
    if (n == frame_bits(8L * uuid_row_bytes)) header_uuid)
}

bit_positions <- function(left, right, n) left + (seq_len(n) - 1) * (right - left) / (n - 1)

# Do at least 26 of the 32 sync bits read correctly at this geometry?
syncs_agree <- function(signal, left, right, n) {
  pitch <- (right - left) / (n - 1)
  sync <- sample_signal(signal, bit_positions(left, right, n)[sync_index(n)], pitch)
  on <- mean(sync[sync_bits == 1L])
  off <- mean(sync[sync_bits == 0L])
  on > off && sum((sync > (on + off) / 2) == sync_bits) >= 26L
}

# The neighbourhood a pixel is compared against: about an eighth of the row,
# a dozen or so bits, always odd.
background_window <- function(width) 2L * (width %/% 16L) + 1L

# Running median of the row: the local background used to find dots. It is
# only a locator. Inside a dense run of 1 bits the median drifts to the dot
# level, so bits are not read against it (see oriented_signal).
local_background <- function(signal, k) {
  stats::runmed(signal, k, endrule = "constant")
}

# The row oriented so dots read positive, measured against the background on
# the dots' far side: the running maximum of the row for dots darker than
# the paper (polarity -1), the running minimum for lighter ones. Unlike a
# median this cannot drift into a dense run of dots, since any window a
# dozen bits wide still holds a gap. Windows shrink towards the row's ends.
oriented_signal <- function(signal, k, polarity) {
  # The background is the running extreme on the side away from the dots.
  # Cap excursions on that side first: a plot border (ggplot2 draws a white
  # one by default, invisible only on white plots) or any bright mark would
  # otherwise hold the extreme for k / 2 pixels and hide the sync dots.
  # The cap tracks the row's own noise: tight on a clean PNG, where even a
  # few hundredths would rival faint dots, looser under JPEG noise.
  median <- local_background(signal, k)
  slack <- max(0.005, 3 * stats::mad(signal - median, constant = 1))
  capped <- if (polarity < 0) pmin(signal, median + slack) else pmax(signal, median - slack)
  polarity * (signal - running_extreme(capped, k, if (polarity < 0) pmax else pmin))
}

running_extreme <- function(x, k, extreme) {
  # Centred sliding min/max over k values (truncated at the ends), in linear
  # time: van Herk / Gil-Werman block prefix and suffix scans. Equivalent to
  # combining each value with its neighbours at distance 1..k %/% 2, which
  # costs O(n * k) and dominated decoding time on noisy images.
  n <- length(x)
  h <- min(k %/% 2L, n - 1L)
  if (h < 1L) return(x)
  is_min <- identical(extreme, pmin)
  pad <- if (is_min) Inf else -Inf
  scan <- if (is_min) cummin else cummax
  w <- 2L * h + 1L
  y <- c(rep(pad, h), x, rep(pad, h))
  blocks <- (length(y) + w - 1L) %/% w
  y <- matrix(c(y, rep(pad, blocks * w - length(y))), nrow = w)
  prefix <- as.vector(apply(y, 2, scan))
  suffix <- as.vector(apply(y[w:1, , drop = FALSE], 2, scan)[w:1, , drop = FALSE])
  i <- seq_len(n)
  extreme(suffix[i], prefix[i + w - 1L])
}

edge_nudges <- c(0, -0.25, 0.25, -0.5, 0.5, -0.75, 0.75, -1, 1)
sync_bits <- c(sync_start, sync_end)
sync_index <- function(n) c(1:16, (n - 15L):n)

# Mean of the signal across the middle of each dot, linearly interpolated
# between pixels so fractional bit positions are read accurately.
sample_signal <- function(signal, xs, pitch) {
  n <- length(signal)
  at <- function(pos) {
    pos <- pmin(pmax(pos, 1), n)
    i <- floor(pos)
    f <- pos - i
    signal[i] * (1 - f) + signal[i + (i < n)] * f
  }
  as.vector(at(xs - 0.2 * pitch) + at(xs) + at(xs + 0.2 * pitch)) / 3
}

