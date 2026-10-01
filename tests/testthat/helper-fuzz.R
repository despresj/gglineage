# Randomised stress for the lineage invariant: a decode returns an ID that
# was really drawn in the image, or NULL. Never a mix of two IDs, never an
# ID nobody drew. tools/lineage-fuzz-campaign.R runs the same generators at
# scale.

# Number of fuzz trials: `default` unless GGLINEAGE_FUZZ_N scales it up (a
# campaign) or the tests run on CRAN (a token few).
fuzz_n <- function(default, cran = max(1L, default %/% 10L)) {
  n <- suppressWarnings(as.integer(Sys.getenv("GGLINEAGE_FUZZ_N", "")))
  if (!is.na(n) && n > 0L) return(max(n, cran))
  if (is_cran()) cran else default
}

fuzz_seed <- function(default) {
  s <- suppressWarnings(as.integer(Sys.getenv("GGLINEAGE_FUZZ_SEED", "")))
  if (is.na(s)) default else s
}

# A random ID of a random kind: a UUID, a packable base32 ID, or UTF-8 text
# of 1-16 bytes (ASCII, accented, CJK and emoji characters).
random_id <- function() {
  switch(sample(c("uuid", "packed", "text"), 1L, prob = c(0.45, 0.25, 0.3)),
    uuid = format_uuid(as.raw(sample(0:255, 16L, replace = TRUE))),
    packed = paste(sample(base32_alphabet, sample(1:16, 1L), replace = TRUE), collapse = ""),
    text = {
      pool <- c(letters, LETTERS, 0:9, "-", "_", ".", " ", "/", "é", "ß",
                "図", "表", "\U0001F4CA")
      repeat {
        id <- paste(sample(pool, sample(1:10, 1L), replace = TRUE), collapse = "")
        n <- nchar(id, type = "bytes")
        if (n <= 16L && grepl("[^ ]", id)) break
      }
      id
    })
}

# Random bit vector -> parsed result, the way the decoder joins rows: the text
# ID, the UUID both rows agree on, or NULL.
decode_rows <- function(rows) {
  frames <- lapply(rows, parse_frame)
  if (any(vapply(frames, is.null, logical(1)))) return(NULL)
  if (length(frames) == 1L) {
    return(if (frames[[1]]$kind == "text") frames[[1]]$id)
  }
  if (frames[[1]]$kind != "uuid" || frames[[2]]$kind != "uuid") return(NULL)
  assemble_uuid(frames[[1]], frames[[2]])
}

flip_bits <- function(bits, k) {
  at <- sample(seq_along(bits), k)
  bits[at] <- 1L - bits[at]
  bits
}

# Soft reads of a UUID row as the decoder sees them: about 1 for a dot, 0 for
# a gap, with noise; `weak` bits are pushed to just across the threshold
# (compression damage) and `erased` dots read as confident gaps (a mark
# painted over them).
soft_row <- function(bits, weak = integer(), erased = integer(), sd = 0.08) {
  v <- bits + stats::rnorm(length(bits), 0, sd)
  v[weak] <- 0.5 + ifelse(bits[weak] == 1L, -1, 1) * stats::runif(length(weak), 0.01, 0.1)
  v[erased] <- stats::runif(length(erased), -0.05, 0.1)
  v
}

# The decoder's acceptance test for the second row of a UUID (find_partner()).
partner_accept <- function(partner) {
  want <- 3L - partner$half
  function(frame) {
    frame$kind == "uuid" && frame$half == want && !is.null(join_halves(partner, frame))
  }
}

# ---- image-level fuzz ---------------------------------------------------------

# Charts to compose: three UUIDs, two of which share a half with the first
# (the worst case for joining rows across charts), two text IDs, two charts
# with only tiles (IDs one character apart) and an unmarked chart. Small
# renders keep each decode quick.
fuzz_pool <- function(width = 5, height = 3.5, dpi = 100) {
  ids <- list(
    uuid_a = "5d0c7e7a-3f4b-4c55-a1d2-9e8f7a6b5c4d",
    uuid_same_first = "5d0c7e7a-3f4b-4c55-0f1e-2d3c4b5a6978",
    uuid_same_second = "e1e2e3e4-e5e6-4e7e-a1d2-9e8f7a6b5c4d",
    packed = "K7Q2M9XD",
    text = "run-42/é",
    tiles_a = "TILE-A1",
    tiles_b = "TILE-B1",
    none = NULL
  )
  plots <- list(
    function() base_plot(),
    function() ggplot2::ggplot(ggplot2::mpg, ggplot2::aes(class)) + ggplot2::geom_bar(),
    function() ggplot2::ggplot(ggplot2::economics, ggplot2::aes(date, unemploy)) +
      ggplot2::geom_line() + ggplot2::theme_minimal() +
      ggplot2::theme(plot.background = ggplot2::element_rect(fill = "white", colour = NA))
  )
  lapply(seq_along(ids), function(i) {
    p <- plots[[(i - 1L) %% length(plots) + 1L]]()
    id <- ids[[i]]
    if (!is.null(id)) {
      p <- p + if (startsWith(names(ids)[i], "tiles")) {
        watermark_tiles(id, pitch = 2, size = 0.7)
      } else {
        watermark_dots(id)
      }
    }
    list(name = names(ids)[i], id = id,
         img = render_plot(p, width = width, height = height, dpi = dpi))
  })
}

# Same-size images side by side or one above the other, on a white page.
fuzz_join <- function(a, b, vertical) {
  if (vertical) {
    w <- max(dim(a)[2], dim(b)[2])
    out <- array(1, c(dim(a)[1] + dim(b)[1], w, 3))
    out[seq_len(dim(a)[1]), seq_len(dim(a)[2]), ] <- a[, , 1:3]
    out[dim(a)[1] + seq_len(dim(b)[1]), seq_len(dim(b)[2]), ] <- b[, , 1:3]
  } else {
    h <- max(dim(a)[1], dim(b)[1])
    out <- array(1, c(h, dim(a)[2] + dim(b)[2], 3))
    out[seq_len(dim(a)[1]), seq_len(dim(a)[2]), ] <- a[, , 1:3]
    out[seq_len(dim(b)[1]), dim(a)[2] + seq_len(dim(b)[2]), ] <- b[, , 1:3]
  }
  out
}

# One random trial: compose 1-3 charts from the pool, apply 1-4 random
# perturbations, and report what was drawn and what came back.
fuzz_trial <- function(pool) {
  k <- sample(1:3, 1L, prob = c(0.4, 0.4, 0.2))
  picks <- pool[sample(seq_along(pool), k, replace = TRUE)]
  img <- picks[[1]]$img[, , 1:3]
  steps <- character()
  for (p in picks[-1]) {
    vertical <- stats::runif(1) < 0.6
    img <- fuzz_join(img, p$img, vertical)
    steps <- c(steps, if (vertical) "stack" else "side")
  }
  ops <- c("transplant", "crop", "resize", "jpeg", "noise", "blur", "gamma",
           "pad", "gray", "invert", "blend", "mirror", "flip")
  probs <- c(4, 3, 3, 3, 2, 1, 1, 2, 1, 1, 1, 0.5, 0.5)
  for (op in sample(ops, sample(1:4, 1L), prob = probs)) {
    h <- dim(img)[1]
    w <- dim(img)[2]
    img <- switch(op,
      # Swap a band of rows for the same rows of another pool chart: the
      # surgery that once joined halves of two UUIDs.
      transplant = {
        donor <- pool[[sample(seq_along(pool), 1L)]]
        picks <- c(picks, list(donor))
        d <- donor$img[, , 1:3]
        rows <- sample(seq_len(min(h, dim(d)[1])), 1L) + 0:sample(4:30, 1L)
        rows <- rows[rows <= min(h, dim(d)[1])]
        cols <- seq_len(min(w, dim(d)[2]))
        dst_rows <- h - dim(d)[1] + rows
        dst_rows <- dst_rows[dst_rows >= 1L]
        src_rows <- utils::tail(rows, length(dst_rows))
        img[dst_rows, cols, ] <- d[src_rows, cols, ]
        img
      },
      crop = tf_crop(img, top = stats::runif(1, 0, 0.3), bottom = stats::runif(1, 0, 0.05),
                     left = stats::runif(1, 0, 0.1), right = stats::runif(1, 0, 0.1)),
      resize = if (w > 300) tf_resize(img, stats::runif(1, max(0.35, 250 / w), 1.6)) else img,
      jpeg = tf_jpeg(img, sample(30:95, 1L)),
      noise = tf_noise(img, stats::runif(1, 0, 0.03)),
      blur = tf_blur(img, 1),
      gamma = tf_gamma(img, stats::runif(1, 0.6, 1.6)),
      pad = tf_pad(img, sample(5:60, 1L), fill = stats::runif(1)),
      gray = tf_gray(img),
      invert = tf_invert(img),
      blend = {
        other <- pool[[sample(seq_along(pool), 1L)]]
        picks <- c(picks, list(other))
        o <- tf_resize(other$img[, , 1:3], 1)
        a <- stats::runif(1, 0.15, 0.35)
        hh <- min(h, dim(o)[1])
        ww <- min(w, dim(o)[2])
        img[h - hh + seq_len(hh), seq_len(ww), ] <-
          (1 - a) * img[h - hh + seq_len(hh), seq_len(ww), ] + a * o[dim(o)[1] - hh + seq_len(hh), seq_len(ww), ]
        img
      },
      mirror = img[, rev(seq_len(w)), , drop = FALSE],
      flip = img[rev(seq_len(h)), , , drop = FALSE])
    steps <- c(steps, op)
  }
  drawn <- unique(unlist(lapply(picks, `[[`, "id")))
  got <- extract_watermark(img)
  list(got = got, drawn = drawn, ok = is.null(got) || got %in% drawn,
       exact = !is.null(got), steps = paste(steps, collapse = " > "),
       charts = paste(vapply(picks, `[[`, "", "name"), collapse = "+"))
}
