# Local image statistics for decode_tiles(). Everything is pure R on a grey
# matrix; box means come from 2-D cumulative sums with replicated edges.

box_mean <- function(g, r) {
  n <- nrow(g)
  m <- ncol(g)
  k <- 2L * r + 1L
  p <- g[c(rep(1L, r), seq_len(n), rep(n, r)), c(rep(1L, r), seq_len(m), rep(m, r)), drop = FALSE]
  S <- p
  for (j in seq_len(ncol(S))) S[, j] <- cumsum(S[, j])
  for (i in seq_len(nrow(S))) S[i, ] <- cumsum(S[i, ])
  S0 <- rbind(0, cbind(0, S))
  i <- seq_len(n)
  j <- seq_len(m)
  (S0[i + k, j + k, drop = FALSE] - S0[i, j + k, drop = FALSE] -
     S0[i + k, j, drop = FALSE] + S0[i, j, drop = FALSE]) / k^2
}

local_stats <- function(g, r) {
  mu <- box_mean(g, r)
  list(res = mu - g, sd = sqrt(pmax(box_mean(g * g, r) - mu * mu, 0)))
}

block_downsample <- function(g, f) {
  if (f <= 1L) return(g)
  n2 <- nrow(g) %/% f
  m2 <- ncol(g) %/% f
  g <- g[seq_len(n2 * f), seq_len(m2 * f), drop = FALSE]
  a <- rowsum(g, rep(seq_len(n2), each = f), reorder = FALSE)
  unname(t(rowsum(t(a), rep(seq_len(m2), each = f), reorder = FALSE)) / f^2)
}
