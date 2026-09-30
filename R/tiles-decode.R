# Decode watermark_tiles(): fold every readable lattice point into one 12 x 12
# vote accumulator, find the tile offset from the sync cells, and accept an ID
# only if its CRC-16 passes. Tries the image, then its inverse (dark mode).

TILE_MAX_PX <- 2400L

fold_votes <- function(votes) {
  a <- factor((row(votes) - 1L) %% 12L, levels = 0:11)
  b <- factor((col(votes) - 1L) %% 12L, levels = 0:11)
  s <- tapply(as.vector(votes), list(a, b), sum)
  s[is.na(s)] <- 0
  matrix(as.numeric(s), 12L, 12L)
}

align_tiles <- function(votes, n = 3L) {
  F <- fold_votes(votes)
  sgn <- 2L * TILE_SYNC - 1L
  cands <- vector("list", 144L)
  k <- 0L
  for (oy in 0:11) for (ox in 0:11) {
    Tm <- F[((0:11 - oy) %% 12L) + 1L, ((0:11 - ox) %% 12L) + 1L]
    tv <- as.vector(t(Tm))
    k <- k + 1L
    cands[[k]] <- list(
      oy = oy, ox = ox,
      score = sum(tv[1:16] * sgn) - sum(tv[129:144] * sgn),
      bits = as.integer(tv > 0),
      votes = tv
    )
  }
  scores <- vapply(cands, function(cand) cand$score, numeric(1))
  cands[order(scores, decreasing = TRUE)[seq_len(n)]]
}

# Decode folded votes. Data and CRC cells with no net votes (no readable
# sample, or a tie) are tried both ways, up to `max_unknown` of them; with more
# than that the evidence is too thin and the answer is NULL. CRC-16 has
# Hamming distance 4, so a few free cells can fit a second valid codeword:
# every combination is tried and the ID is accepted only if it is the one and
# only ID that fits.
decode_tile_votes <- function(tv, max_unknown = 2L) {
  bits <- as.integer(tv > 0)
  unknown <- 16L + which(tv[17:128] == 0)
  if (length(unknown) > max_unknown) return(NULL)
  if (length(unknown) == 0L) return(decode_tile(bits))
  combos <- as.matrix(expand.grid(rep(list(0:1), length(unknown))))
  found <- character()
  for (i in seq_len(nrow(combos))) {
    bits[unknown] <- combos[i, ]
    id <- decode_tile(bits)
    if (!is.null(id)) found <- union(found, id)
  }
  if (length(found) == 1L) found else NULL
}

decode_tiles <- function(gray, debug = FALSE) {
  say <- function(...) if (isTRUE(debug)) message("tiles: ", sprintf(...))
  f <- as.integer(ceiling(max(dim(gray)) / TILE_MAX_PX))
  # A second pass at twice the downsampling covers pitches beyond the search
  # range (small figures above about 500 dpi, or a large `pitch`).
  for (ff in c(f, 2L * f)) {
    g <- block_downsample(gray, ff)
    if (min(dim(g)) < 64L) break
    if (ff > 1L) say("downsampled by %d to %d x %d px", ff, ncol(g), nrow(g))
    id <- decode_tiles_at(g, say)
    if (!is.null(id)) return(id)
  }
  NULL
}

decode_tiles_at <- function(gray, say) {
  # just changes sign and the local spread is unchanged.
  res8 <- box_mean(gray, 8L) - gray
  sd16 <- local_stats(gray, 16L)$sd
  vote_stats <- list()
  for (polarity in c("dark", "light")) {
    g <- if (polarity == "dark") gray else 1 - gray
    sgn <- if (polarity == "dark") 1 else -1
    for (remove_lines in c(FALSE, TRUE)) {
      how <- sprintf("%s dots%s", polarity, if (remove_lines) ", lines removed" else "")
      lat <- estimate_lattice(g, remove_lines, res = sgn * res8, sd16 = sd16)
      if (is.null(lat)) {
        say("%s: no lattice found", how)
        next
      }
      say("%s: pitch %.2f x %.2f px, phase (%.2f, %.2f), strength %.2f",
          how, lat$px, lat$py, lat$phase_x, lat$phase_y, lat$strength)
      r <- as.character(votes_radius(lat))
      if (is.null(vote_stats[[r]])) vote_stats[[r]] <- local_stats(gray, as.integer(r))
      s <- vote_stats[[r]]
      sv <- sample_votes(g, lat, s = list(res = sgn * s$res, sd = s$sd))
      if (is.null(sv)) {
        say("%s: too few readable cells", how)
        next
      }
      say("%s: readable %.0f%%, contrast %.3f, tiles folded %.1f",
          how, 100 * sv$known_frac, sv$contrast, sum(sv$votes != 0L) / 144)
      for (cand in align_tiles(sv$votes)) {
        id <- decode_tile_votes(cand$votes)
        say("offset (%d, %d), score %.0f: CRC %s", cand$oy, cand$ox, cand$score,
            if (is.null(id)) "failed" else "passed")
        if (!is.null(id)) return(id)
      }
    }
  }
  NULL
}
