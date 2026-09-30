# Find the tile lattice in a grey image and read each lattice point as a vote:
# +1 (dot), -1 (no dot) or 0 (unreadable: data, text or edges nearby).

TILE_UNKNOWN_SD <- 0.04



# Spectral peaks of a profile: detrend (slower than the longest pitch), take
# an 8x zero-padded FFT, and keep local maxima well above the median power.
spectrum_peaks <- function(x, min_lag = 3, max_lag = 60, n_peaks = 5L) {
  n <- length(x)
  max_lag <- min(max_lag, floor(n / 3))
  if (max_lag < min_lag + 2) return(NULL)
  x <- x - as.vector(box_mean(matrix(x, 1L), as.integer(max_lag)))
  if (all(abs(x) < 1e-12)) return(NULL)
  N <- 2^ceiling(log2(8 * n))
  P <- Mod(stats::fft(c(x, rep(0, N - n))))^2
  k <- seq.int(ceiling(N / max_lag), floor(N / min_lag))
  pk <- P[k + 1]
  top <- which(diff(sign(diff(pk))) == -2) + 1
  strength <- pk[top] / stats::median(pk)
  keep <- order(strength, decreasing = TRUE)[seq_len(min(n_peaks, length(top)))]
  keep <- keep[strength[keep] >= 25]
  if (!length(keep)) return(NULL)
  list(x = x, period = N / k[top[keep]], strength = strength[keep])
}

# Refine a period on a fine grid of Fourier magnitude, then read its phase.
refine_period <- function(x, p, window = 0.02) {
  t <- seq_along(x) - 1
  if (window > 0) p <- grid_peak(function(q) Mod(sum(x * exp(-2i * pi * t / q)))^2, p, window)
  z <- sum(x * exp(-2i * pi * t / p))
  list(period = p, phase = (-Arg(z) / (2 * pi) * p) %% p)
}

# One pitch fitted to both profiles: each axis's power is normalised so the
# longer axis doesn't dominate.
refine_joint <- function(x, y, p, window = 0.02) {
  tx <- seq_along(x) - 1
  ty <- seq_along(y) - 1
  px <- function(q) Mod(sum(x * exp(-2i * pi * tx / q)))^2
  py <- function(q) Mod(sum(y * exp(-2i * pi * ty / q)))^2
  nx <- px(p)
  ny <- py(p)
  grid_peak(function(q) px(q) / nx + py(q) / ny, p, window)
}

# Maximise f on a fine grid within +/- window of p, with a parabolic finish.
grid_peak <- function(f, p, window) {
  grid <- seq(p * (1 - window), p * (1 + window), length.out = 201)
  m <- vapply(grid, f, numeric(1))
  j <- which.max(m)
  q <- grid[j]
  if (j > 1L && j < length(grid)) {
    den <- m[j - 1L] - 2 * m[j] + m[j + 1L]
    if (den < 0) q <- q + (grid[2] - grid[1]) * max(-0.5, min(0.5, 0.5 * (m[j - 1L] - m[j + 1L]) / den))
  }
  q
}

period_phase <- function(x, min_lag = 3, max_lag = 60) {
  sp <- spectrum_peaks(x, min_lag, max_lag)
  if (is.null(sp)) return(NULL)
  c(refine_period(sp$x, sp$period[1]), strength = sp$strength[1])
}

# Pitch search uses a fixed radius-8 background and only near-flat pixels:
# data, text and gridlines leave box-filter halos whose spacing tracks the
# radius, not the lattice, so their neighbourhoods are masked out. Flatness is
# judged over a wider window (radius 16) so that at high resolution the dots
# themselves stay a small share of it.
TILE_FLAT_SD <- 0.015

estimate_lattice <- function(g, remove_lines = FALSE,
                             res = box_mean(g, 8L) - g,
                             sd16 = local_stats(g, 16L)$sd) {
  # Gridlines and their halos run the full width or height of the panel, which
  # is exactly what row and column profiles sum; dots are sparse along any
  # line, so removing each row's and column's median keeps them. It helps
  # busy grids (theme_dark) and hurts facet gaps, so the decoder tries both.
  if (remove_lines) {
    res <- res - apply(res, 1, stats::median)
    res <- t(t(res) - apply(res, 2, stats::median))
  }
  flat <- sd16 < TILE_FLAT_SD
  act <- pmin(pmax(res, 0), 0.04) * flat
  sx <- spectrum_peaks(colSums(act))
  sy <- spectrum_peaks(rowSums(act))
  if (is.null(sx) || is.null(sy)) return(NULL)
  # The lattice is square: pick the strongest pair of column and row peaks
  # whose periods agree within 3%. Bars and other one-directional repeats
  # only show up on one axis.
  score <- outer(sx$strength, sy$strength)
  score[abs(log(outer(sx$period, sy$period, "/"))) > log(1.03)] <- 0
  if (max(score) == 0) return(NULL)
  best <- which(score == max(score), arr.ind = TRUE)[1, ]
  cx <- refine_period(sx$x, sx$period[best[1]])
  cy <- refine_period(sy$x, sy$period[best[2]])
  # A short axis spans few periods and refines poorly. When the axes agree
  # (no anisotropic resize), fit one pitch to both profiles.
  if (abs(log(cx$period / cy$period)) < log(1.01)) {
    p <- refine_joint(sx$x, sy$x, (cx$period + cy$period) / 2)
    cx <- refine_period(sx$x, p, window = 0)
    cy <- refine_period(sy$x, p, window = 0)
  }
  list(px = cx$period, py = cy$period, phase_x = cx$phase, phase_y = cy$phase,
       strength = min(sx$strength[best[1]], sy$strength[best[2]]))
}

sample_votes <- function(g, lat, unknown_sd = TILE_UNKNOWN_SD, s = NULL) {
  if (is.null(s)) s <- local_stats(g, votes_radius(lat))
  xs <- lat$phase_x + lat$px * (0:floor((ncol(g) - 1 - lat$phase_x) / lat$px))
  ys <- lat$phase_y + lat$py * (0:floor((nrow(g) - 1 - lat$phase_y) / lat$py))
  ci <- pmin(ncol(g), as.integer(round(xs)) + 1L)
  ri <- pmin(nrow(g), as.integer(round(ys)) + 1L)
  v <- s$res[ri, ci, drop = FALSE]
  known <- s$sd[ri, ci, drop = FALSE] < unknown_sd
  if (sum(known) < 2L * 144L) return(NULL)
  t <- stats::median(v[known])
  for (i in 1:20) {
    hi <- v[known & v > t]
    lo <- v[known & v <= t]
    if (!length(hi) || !length(lo)) return(NULL)
    t <- (mean(hi) + mean(lo)) / 2
  }
  # A sample far outside both clusters is not a dot or an empty cell but
  # something else under it: a bright gridline, or the edge of dark data.
  lo_m <- mean(v[known & v <= t])
  hi_m <- mean(v[known & v > t])
  half <- (hi_m - lo_m) / 2
  known <- known & v > lo_m - half & v < hi_m + half
  # Gridlines: an image row or column whose median residual is far from zero
  # is a line across the panel (dots cover only a fraction of any row).
  # Lattice samples within a dot radius of one can't be read.
  w <- max(1L, as.integer(round(0.2 * min(lat$px, lat$py))))
  near_line <- function(line, idx) {
    vapply(idx, function(i) any(line[max(1L, i - w):min(length(line), i + w)]), logical(1))
  }
  known[near_line(abs(apply(s$res, 1, stats::median)) > half, ri), ] <- FALSE
  known[, near_line(abs(apply(s$res, 2, stats::median)) > half, ci)] <- FALSE
  votes <- ifelse(known, ifelse(v > t, 1L, -1L), 0L)
  # Only regions that look like tiles (about half dots) vote.
  ones <- box_mean((votes == 1L) * 1, 6L)
  kn <- box_mean(known * 1, 6L)
  dens <- ifelse(kn > 0, ones / kn, 0)
  votes[dens < 0.25 | dens > 0.75] <- 0L
  # A margin one or two lattice lines wide borrows density from the panel
  # beside it, so also drop (almost) constant lattice rows and columns, but
  # only the outer two readable lines on each side: an interior line can
  # legitimately repeat a tile row or column that is all 0 or all 1.
  line_ok <- function(ones, n) {
    k <- pmax(1, 0.03 * n)
    n < 8 | (ones > k & ones < n - k)
  }
  outer_lines <- function(n) {
    idx <- which(n > 0)
    if (length(idx) == 0L) return(integer())
    unique(c(utils::head(idx, 2L), utils::tail(idx, 2L)))
  }
  n_row <- rowSums(votes != 0L)
  n_col <- colSums(votes != 0L)
  bad_row <- intersect(outer_lines(n_row), which(!line_ok(rowSums(votes == 1L), n_row)))
  bad_col <- intersect(outer_lines(n_col), which(!line_ok(colSums(votes == 1L), n_col)))
  votes[bad_row, ] <- 0L
  votes[, bad_col] <- 0L
  storage.mode(votes) <- "integer"
  list(
    votes = votes,
    known_frac = mean(votes != 0L),
    contrast = stats::median(v[known & v > t]),
    separation = mean(v[known & v > t]) - mean(v[known & v <= t])
  )
}

votes_radius <- function(lat) max(2L, as.integer(round(min(lat$px, lat$py))))
