# "Ping a rando chart": the README animation.
#
# A random chart is watermarked, then really screenshotted, shrunk and
# JPEG-crunched. The real decoder then pings it, and the chart answers with
# its ID. Nothing is faked: the dots, the row and the ID come from
# extract_watermark()'s internals on the degraded image.
#
# Run from the package root (needs ffmpeg on the PATH):
#   Rscript data-raw/ping.R

suppressPackageStartupMessages({
  library(ggplot2)
  library(grid)
})
pkgload::load_all(quiet = TRUE)
source("tests/testthat/helper-transforms.R")

set.seed(as.integer(Sys.time()))
frames_dir <- tempfile("ping-frames")
dir.create(frames_dir)

# Palette, matching the hex logo.
navy <- "#0f1b2d"
teal <- "#5eead4"
ink <- "#f8fafc"
muted <- "#94a3b8"
seg_cols <- c("#2dd4bf", "#fbbf24", "#60a5fa", "#fb7185", "#2dd4bf")

# A rando chart ----------------------------------------------------------------

randos <- list(
  function() {
    d <- data.frame(day = 1:40, vibes = cumsum(rnorm(40, 0.25)))
    ggplot(d, aes(day, vibes)) +
      geom_line(linewidth = 1.1, colour = "#7c3aed") +
      geom_point(colour = "#7c3aed", size = 1.6) +
      labs(title = "Vibes over time", x = "Day", y = "Vibes (arbitrary units)")
  },
  function() {
    d <- data.frame(cups = rpois(45, 3))
    d$lines <- pmax(0, 110 * d$cups + rnorm(45, 0, 80))
    ggplot(d, aes(cups, lines)) +
      geom_jitter(width = 0.15, size = 2.4, colour = "#0891b2", alpha = 0.8) +
      geom_smooth(method = "lm", formula = y ~ x, se = FALSE,
                  colour = "#f97316") +
      labs(title = "Cups of coffee vs. lines of code", x = "Cups",
           y = "Lines of code")
  },
  function() {
    d <- data.frame(hour = factor(8:18), pigeons = rpois(11, 7))
    ggplot(d, aes(hour, pigeons)) +
      geom_col(fill = "#16a34a", width = 0.75) +
      labs(title = "Pigeons spotted per hour", x = "Hour", y = "Pigeons")
  },
  function() {
    d <- data.frame(meeting = 1:25, minutes = 30 + cumsum(rexp(25, 0.3)))
    ggplot(d, aes(meeting, minutes)) +
      geom_area(fill = "#e11d48", alpha = 0.25) +
      geom_line(colour = "#e11d48", linewidth = 1) +
      labs(title = "\"Quick sync\" duration", x = "Meeting #", y = "Minutes")
  }
)

id <- wm_id()
chart <- sample(randos, 1)[[1]]() +
  theme_minimal(base_size = 13) +
  theme(plot.title = element_text(face = "bold")) +
  watermark_dots(id)

# Life happens -----------------------------------------------------------------

add_chrome <- function(img) {
  bar <- 28L
  border <- 6L
  d <- dim(img)
  out <- array(0.16, c(d[1] + bar + border, d[2] + 2L * border, 3L))
  out[bar + seq_len(d[1]), border + seq_len(d[2]), ] <- img
  lights <- list(c(1, 0.37, 0.34), c(1, 0.74, 0.18), c(0.16, 0.79, 0.26))
  yy <- row(out[, , 1])
  xx <- col(out[, , 1])
  for (i in seq_along(lights)) {
    hit <- (yy - bar / 2)^2 + (xx - (border + 14 + 20 * (i - 1)))^2 <= 36
    for (ch in 1:3) out[, , ch][hit] <- lights[[i]][ch]
  }
  out
}

stages <- list(render_plot(chart, width = 7, height = 4.4, dpi = 110))
stages[[2]] <- add_chrome(stages[[1]])
stages[[3]] <- tf_resize(stages[[2]], 0.85)
stages[[4]] <- tf_jpeg(stages[[3]], 50)
stage_labels <- c("screenshot", "shrunk to 85%", "JPEG quality 50")

# Ping: run the real decoder on the degraded image -----------------------------

final <- stages[[4]]
stopifnot(identical(extract_watermark(final), id))
gray <- as_gray(final)
for (hit_row in rev(seq_len(nrow(gray)))) {
  found <- decode_row(gray[hit_row, ])
  if (!is.null(found)) break
}
stopifnot(identical(found$id, id))

signal <- gray[hit_row, ]
dev <- abs(signal - stats::runmed(signal, 2L * (length(signal) %/% 16L) + 1L,
                                  endrule = "median"))
threshold <- stats::quantile(dev, 0.85, names = FALSE) / 2
runs <- rle(dev > threshold)
ends <- cumsum(runs$lengths)
centers <- ((ends - runs$lengths + 1 + ends) / 2)[runs$values]
centers <- centers[centers >= found$left - 1 & centers <= found$right + 1]

# Canvas -----------------------------------------------------------------------

W <- 800
H <- 600
box <- c(x = 40, y = 100, w = 720, h = 384)

placement <- function(img) {
  s <- min(box[["w"]] / ncol(img), box[["h"]] / nrow(img))
  w <- ncol(img) * s
  h <- nrow(img) * s
  c(x = box[["x"]] + (box[["w"]] - w) / 2, y = box[["y"]] + (box[["h"]] - h) / 2,
    w = w, h = h)
}

to_canvas <- function(img, col, row) {
  p <- placement(img)
  list(
    x = p[["x"]] + (col - 0.5) / ncol(img) * p[["w"]],
    y = p[["y"]] + p[["h"]] - (row - 0.5) / nrow(img) * p[["h"]]
  )
}

px <- function(v) unit(v, "native")

draw_image <- function(img, fade = 1) {
  p <- placement(img)
  grid.raster(img, x = px(p[["x"]]), y = px(p[["y"]]), width = px(p[["w"]]),
              height = px(p[["h"]]), just = c("left", "bottom"),
              interpolate = FALSE)
  if (fade < 1) {
    grid.rect(x = px(p[["x"]]), y = px(p[["y"]]), width = px(p[["w"]]),
              height = px(p[["h"]]), just = c("left", "bottom"),
              gp = gpar(fill = navy, col = NA, alpha = 1 - fade))
  }
}

draw_header <- function(stage, chips = character()) {
  grid.text("ping a rando chart", x = px(40), y = px(H - 40), just = "left",
            gp = gpar(col = ink, fontsize = 24, fontface = "bold"))
  grid.text(stage, x = px(W - 40), y = px(H - 40), just = "right",
            gp = gpar(col = teal, fontsize = 15, fontface = "bold"))
  x <- 40
  for (chip in chips) {
    label <- paste(chip, "✓")
    wd <- nchar(label) * 7.6 + 20
    grid.roundrect(x = px(x), y = px(H - 82), width = px(wd), height = px(24),
                   just = "left", r = unit(12, "points"),
                   gp = gpar(fill = "#1e293b", col = "#334155"))
    grid.text(label, x = px(x + wd / 2), y = px(H - 82),
              gp = gpar(col = "#fcd34d", fontsize = 11.5))
    x <- x + wd + 10
  }
}

draw_footer <- function(typed = "", status = "", cursor = FALSE) {
  shown <- paste0(typed, if (cursor) "▌" else "")
  grid.text("id:", x = px(40), y = px(58), just = "left",
            gp = gpar(col = muted, fontsize = 20, fontfamily = "mono"))
  grid.text(if (nzchar(shown)) shown else "????????", x = px(90), y = px(58),
            just = "left",
            gp = gpar(col = if (nzchar(shown)) teal else "#475569",
                      fontsize = 20, fontfamily = "mono", fontface = "bold"))
  grid.text(status, x = px(W - 40), y = px(58), just = "right",
            gp = gpar(col = muted, fontsize = 13))
}

draw_scanline <- function(y, p) {
  for (k in 6:1) {
    grid.rect(x = px(p[["x"]]), y = px(y), width = px(p[["w"]]),
              height = px(k * 3), just = "left",
              gp = gpar(fill = teal, col = NA, alpha = 0.05))
  }
  grid.lines(x = px(c(p[["x"]], p[["x"]] + p[["w"]])), y = px(c(y, y)),
             gp = gpar(col = teal, lwd = 2))
}

draw_ping <- function(t, rings = TRUE) {
  pos <- to_canvas(final, centers, hit_row)
  cx <- mean(range(pos$x))
  cy <- pos$y[1]
  for (k in if (rings) 0:2 else integer()) {
    tk <- t - k * 0.18
    if (tk > 0 && tk < 1) {
      grid.circle(x = px(cx), y = px(cy), r = px(40 + tk * 380),
                  gp = gpar(col = teal, fill = NA, lwd = 3 * (1 - tk),
                            alpha = 1 - tk))
    }
  }
  grid.circle(x = px(pos$x), y = px(pos$y), r = px(7),
              gp = gpar(fill = teal, col = NA, alpha = 0.25))
  grid.circle(x = px(pos$x), y = px(pos$y), r = px(3),
              gp = gpar(fill = teal, col = NA))
}

# Magnified, contrast-stretched strip around the dot row, with the frame
# segments (sync / length / payload / CRC / sync) underneath.
strip_raster <- local({
  pad <- 2 * found$pitch
  cols <- max(1, floor(found$left - pad)):min(ncol(gray), ceiling(found$right + pad))
  half <- max(1, round(found$pitch * 0.5))
  rows <- max(1, hit_row - half):min(nrow(gray), hit_row + half)
  g <- gray[rows, cols, drop = FALSE]
  local_bg <- t(apply(g, 1, function(r) {
    stats::runmed(r, 2L * (length(r) %/% 16L) + 1L, endrule = "median")
  }))
  k <- pmin(abs(g - local_bg) / stats::quantile(abs(g - local_bg), 0.97), 1)
  bg <- grDevices::col2rgb(navy)[, 1] / 255
  fg <- grDevices::col2rgb(teal)[, 1] / 255
  list(
    img = array(c(bg[1] + (fg[1] - bg[1]) * k, bg[2] + (fg[2] - bg[2]) * k,
                  bg[3] + (fg[3] - bg[3]) * k), c(dim(k), 3)),
    cols = cols
  )
})

draw_strip <- function(t) {
  y <- 128 + 30 * (1 - t)
  sx <- 60
  sw <- W - 120
  sh <- 58
  grid.rect(x = px(sx - 8), y = px(y - 34), width = px(sw + 16),
            height = px(sh + 58), just = c("left", "bottom"),
            gp = gpar(fill = navy, col = teal, lwd = 1.5, alpha = t))
  grid.raster(strip_raster$img, x = px(sx), y = px(y), width = px(sw),
              height = px(sh), just = c("left", "bottom"), interpolate = FALSE)
  cols <- strip_raster$cols
  to_x <- function(col) sx + (col - cols[1]) / (length(cols) - 1) * sw
  n <- found$n_bits
  bounds <- cumsum(c(0, 16, 8, n - 48, 8, 16))
  bit_x <- function(b) to_x(found$left + (b - 0.5) * found$pitch)
  labels <- c("sync", "len", sprintf("payload · %d bytes", (n - 48) / 8),
              "crc", "sync")
  for (i in 1:5) {
    x0 <- bit_x(bounds[i])
    x1 <- bit_x(bounds[i + 1])
    grid.rect(x = px(x0), y = px(y - 10), width = px(x1 - x0 - 2),
              height = px(6), just = c("left", "bottom"),
              gp = gpar(fill = seg_cols[i], col = NA, alpha = t))
    grid.text(labels[i], x = px((x0 + x1) / 2), y = px(y - 24),
              gp = gpar(col = seg_cols[i], fontsize = 10, alpha = t))
  }
}

# Frames -----------------------------------------------------------------------

frame_no <- 0L
frame <- function(draw) {
  frame_no <<- frame_no + 1L
  ragg::agg_png(file.path(frames_dir, sprintf("f%04d.png", frame_no)),
                width = W, height = H, units = "px", res = 96, background = navy)
  pushViewport(viewport(xscale = c(0, W), yscale = c(0, H)))
  draw()
  popViewport()
  invisible(grDevices::dev.off())
}
ease <- function(t) t * t * (3 - 2 * t)
seq01 <- function(n) seq(0, 1, length.out = n)

# 1. A rando chart appears.
for (t in seq01(12)) {
  frame(function() {
    draw_header("a rando chart appears")
    draw_image(stages[[1]], ease(t))
    draw_footer(status = "watermarked, secretly")
  })
}
for (i in 1:10) frame(function() {
  draw_header("a rando chart appears")
  draw_image(stages[[1]])
  draw_footer(status = "watermarked, secretly")
})

# 2. Life happens.
for (s in 1:3) {
  for (i in 1:11) {
    frame(function() {
      draw_header("life happens", stage_labels[seq_len(s)])
      draw_image(stages[[s + 1]])
      if (i <= 3) {
        p <- placement(stages[[s + 1]])
        grid.rect(x = px(p[["x"]]), y = px(p[["y"]]), width = px(p[["w"]]),
                  height = px(p[["h"]]), just = c("left", "bottom"),
                  gp = gpar(fill = "white", col = NA, alpha = 0.7 * (1 - i / 3)))
      }
      draw_footer(status = sprintf("%d × %d px", ncol(stages[[s + 1]]),
                                   nrow(stages[[s + 1]])))
    })
  }
}

# 3. Ping: sweep down to the dot row.
p_final <- placement(final)
target_y <- to_canvas(final, 1, hit_row)$y
top_y <- p_final[["y"]] + p_final[["h"]]
for (t in seq01(20)) {
  y <- top_y - ease(t) * (top_y - target_y)
  scanned <- round((top_y - y) / p_final[["h"]] * nrow(final))
  frame(function() {
    draw_header("ping…", stage_labels)
    draw_image(final)
    draw_scanline(y, p_final)
    draw_footer(status = sprintf("scanning row %d of %d", scanned, nrow(final)))
  })
}
for (t in seq01(12)) {
  frame(function() {
    draw_header("PING!", stage_labels)
    draw_image(final)
    draw_scanline(target_y, p_final)
    draw_ping(t)
    draw_footer(status = sprintf("%d dots at %.1f px apart", length(centers),
                                 found$pitch))
  })
}

# 4. The chart answers.
for (t in seq01(6)) {
  frame(function() {
    draw_header("decoding", stage_labels)
    draw_image(final, 0.45)
    draw_ping(1, rings = FALSE)
    draw_strip(ease(t))
    draw_footer(status = "checking syncs + CRC-8")
  })
}
chars <- strsplit(id, "")[[1]]
for (i in seq_along(chars)) {
  frame(function() {
    draw_header("decoding", stage_labels)
    draw_image(final, 0.45)
    draw_ping(1, rings = FALSE)
    draw_strip(1)
    draw_footer(paste(chars[seq_len(i)], collapse = ""),
                "checking syncs + CRC-8", cursor = TRUE)
  })
}
for (i in 1:22) {
  frame(function() {
    draw_header("found you ✨", stage_labels)
    draw_image(final, 0.45)
    draw_ping(1, rings = FALSE)
    draw_strip(1)
    draw_footer(id, "✓ checksum OK · exact match",
                cursor = i %% 8 < 4)
  })
}

# Assemble ---------------------------------------------------------------------

out <- "man/figures/ping.gif"
status <- system2("ffmpeg", c(
  "-y", "-loglevel", "error", "-framerate", "12",
  "-i", shQuote(file.path(frames_dir, "f%04d.png")),
  "-vf", shQuote(paste0(
    "split[a][b];[a]palettegen=max_colors=96:stats_mode=diff[p];",
    "[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle"
  )),
  "-loop", "0", out
))
stopifnot(status == 0)
message(sprintf("Wrote %s: %d frames, %.0f KB, id %s", out, frame_no,
                file.size(out) / 1024, id))
