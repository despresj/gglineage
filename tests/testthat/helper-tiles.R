synthetic_lattice <- function(n = 420, period = 7.3, phase = 2.2, contrast = 0.05, noise = 0.003, seed = 1) {
  set.seed(seed)
  g <- matrix(0.92, n, n) + stats::rnorm(n * n, 0, noise)
  idx <- round(phase + period * (0:floor((n - 2 - phase) / period))) + 1L
  bits <- matrix(stats::rbinom(length(idx)^2, 1, 0.5), length(idx))
  for (a in seq_along(idx)) for (b in seq_along(idx)) if (bits[a, b] == 1L) {
    rr <- idx[a] + 0:1
    cc <- idx[b] + 0:1
    g[rr, cc] <- g[rr, cc] - contrast
  }
  list(g = g, bits = bits)
}

tile_contrast <- function(img) {
  g <- as_gray(img)
  sample_votes(g, estimate_lattice(g))$contrast
}
