# "Where did this chart come from?": the README animation.
#
# Left, the usual support thread: a screenshot with no context and six
# questions nobody can answer. Right, the same screenshot traced with
# watermark.
#
# Everything shown on the right is computed here, not typed in:
#
# 1. A small demo analysis saves a figure with ggsave_watermark() and logs a
#    row for it in a manifest, plots.csv. The client, project and run are
#    fictional demo labels; the script, data checksum and output path are the
#    real files this script uses and writes.
# 2. The figure is pasted into a slide, screenshotted, shrunk and saved as a
#    JPEG, like the attachment in the thread.
# 3. extract_watermark() reads the ID from that JPEG, and the ID is looked up
#    in plots.csv. Only the ID comes from the pixels; the rest of the lineage
#    card is the manifest row, and the animation says so.
#
# Run from the package root (needs ffmpeg on the PATH):
#   Rscript data-raw/lineage-demo.R
#
# Writes man/figures/lineage.gif (README hero), man/figures/lineage-still.png
# (its final frame) and man/figures/lineage-mobile.png (the two panels
# stacked, for narrow screens), and refreshes the demo manifest and
# screenshot in data-raw/lineage-demo/, so anyone can check the decode:
#   extract_watermark("data-raw/lineage-demo/screenshot.jpg")

suppressPackageStartupMessages({
  library(ggplot2)
  library(grid)
})
pkgload::load_all(quiet = TRUE)
source("tests/testthat/helper-transforms.R")

# 1. A demo analysis that logs what it saves ----------------------------------

project <- file.path(tempfile("lineage-demo"), "retention-study")
dir.create(file.path(project, "data"), recursive = TRUE)
dir.create(file.path(project, "output"))

set.seed(104)
accounts <- data.frame(
  account = sprintf("A%04d", 1:600),
  cohort = rep(c("2026 Q1", "2026 Q2"), each = 300),
  months_active = c(pmin(12L, rgeom(300, 0.11)), pmin(12L, rgeom(300, 0.08)))
)
snapshot <- "data/snapshot-2026-09-12.csv"
utils::write.csv(accounts, file.path(project, snapshot), row.names = FALSE)

curves <- do.call(rbind, lapply(split(accounts, accounts$cohort), function(d) {
  data.frame(cohort = d$cohort[1], month = 0:12,
             active = vapply(0:12, function(m) mean(d$months_active >= m), 0))
}))

chart <- ggplot(curves, aes(month, active, colour = cohort)) +
  geom_line(linewidth = 1) +
  geom_point(size = 1.6) +
  scale_y_continuous(labels = scales::percent, limits = c(0, 1)) +
  scale_x_continuous(breaks = seq(0, 12, 3)) +
  scale_colour_manual(values = c("#94a3b8", "#0f766e")) +
  labs(title = "Retention by signup cohort", x = "Months since signup",
       y = "Accounts still active", colour = NULL) +
  theme_minimal(base_size = 13) +
  theme(plot.title = element_text(face = "bold"), legend.position = "top",
        legend.justification = "left", panel.grid.minor = element_blank())

id <- "7K3M9QXD"
output <- "output/retention-by-cohort.png"
ggsave_watermark(file.path(project, output), chart, id = id,
                 width = 7, height = 4.3, dpi = 110, bg = "white")

# The manifest: one row per saved plot, written at save time. `script` is
# this file, identified by its git blob hash (`git hash-object <file>`).
script <- "data-raw/lineage-demo.R"
script_sha <- system2("git", c("hash-object", script), stdout = TRUE)
manifest <- data.frame(
  id = id,
  client = "Demo Retail Co. (fictional)",
  project = "RET-104 retention study",
  run = "2026-09-14-r03",
  script = sprintf("%s @ %s", script, substr(script_sha, 1, 7)),
  data = sprintf("%s · md5 %s", basename(snapshot),
                 substr(unname(tools::md5sum(file.path(project, snapshot))), 1, 7)),
  output = output
)
dir.create("data-raw/lineage-demo", showWarnings = FALSE)
manifest_path <- "data-raw/lineage-demo/plots.csv"
utils::write.csv(manifest, manifest_path, row.names = FALSE, fileEncoding = "UTF-8")

# 2. The figure travels -----------------------------------------------------

sans <- if ("Helvetica Neue" %in% systemfonts::system_fonts()$family) {
  "Helvetica Neue"
} else {
  "sans"
}
mono <- if ("Menlo" %in% systemfonts::system_fonts()$family) "Menlo" else "mono"

figure <- png::readPNG(file.path(project, output))[, , 1:3]

# A deck slide with the figure pasted in, scaled like a placed image.
slide_file <- tempfile(fileext = ".png")
ragg::agg_png(slide_file, width = 1000, height = 640, res = 72,
              background = "white")
grid.rect(gp = gpar(fill = "#ffffff", col = NA))
grid.text("Q3 account review", x = unit(48, "points"), y = unit(1, "npc") - unit(44, "points"),
          just = "left", gp = gpar(fontfamily = sans, fontsize = 28, fontface = "bold",
                                   col = "#1f2937"))
grid.text("Retention, by cohort", x = unit(48, "points"),
          y = unit(1, "npc") - unit(78, "points"), just = "left",
          gp = gpar(fontfamily = sans, fontsize = 16, col = "#6b7280"))
grid.raster(figure, x = unit(48, "points"), y = unit(40, "points"),
            width = unit(820, "points"), height = unit(820 * nrow(figure) / ncol(figure), "points"),
            just = c("left", "bottom"), interpolate = TRUE)
invisible(dev.off())
slide <- png::readPNG(slide_file)[, , 1:3]

# A screenshot of part of the slide, halved by a Retina display, saved as a
# JPEG by a chat app.
screenshot <- tf_crop(slide, top = 0.02, bottom = 0.03, left = 0.01, right = 0.1)
screenshot <- tf_resize(screenshot, 0.62)
screenshot_file <- "data-raw/lineage-demo/screenshot.jpg"
jpeg::writeJPEG(screenshot, screenshot_file, quality = 0.6)
screenshot <- jpeg::readJPEG(screenshot_file)

# 3. Trace it -----------------------------------------------------------------

decoded <- extract_watermark(screenshot_file)
stopifnot(identical(decoded, id))
stopifnot(length(read_watermark_metadata(screenshot_file)) == 0L)
plots <- utils::read.csv(manifest_path, fileEncoding = "UTF-8")
record <- plots[plots$id == decoded, ]
stopifnot(nrow(record) == 1L)
where <- find_watermark(as_gray(screenshot))
stopifnot(identical(where$id, decoded))
message(sprintf("Decoded %s from %s (%d x %d px, JPEG); row %d, %d bits",
                decoded, basename(screenshot_file), ncol(screenshot),
                nrow(screenshot), where$row, where$n_bits))

# Drawing ---------------------------------------------------------------------
#
# Layout is in design units with the origin at the top left; one unit is one
# point at 72 dpi, so font sizes and positions share a scale. `S` sets output
# pixels per unit.

pal <- list(
  bg = "#f3f4f6", card = "#ffffff", line = "#e5e7eb", ink = "#1f2328",
  muted = "#6b7280", faint = "#9ca3af", accent = "#0f766e",
  accent_bg = "#ecf6f4", code_bg = "#f6f8fa",
  morgan = "#a16207", sam = "#3b5b92"
)

canvas_h <- NULL
Y <- function(y) unit(canvas_h - y, "native")
X <- function(x) unit(x, "native")

text_width <- function(label, size, face = "plain", family = sans) {
  g <- textGrob(label, gp = gpar(fontsize = size, fontface = face, fontfamily = family))
  convertWidth(grobWidth(g), "native", valueOnly = TRUE)
}

# Draw one line of text centred vertically on y, refusing to overflow.
txt <- function(label, x, y, size = 14, col = pal$ink, face = "plain",
                family = sans, just = "left", max_w = Inf, alpha = 1) {
  w <- text_width(label, size, face, family)
  if (w > max_w + 0.5) {
    stop(sprintf("Text overflows by %.0f units: \"%s\"", w - max_w, label))
  }
  grid.text(label, x = X(x), y = Y(y), just = c(just, "centre"),
            gp = gpar(fontsize = size, col = col, fontface = face,
                      fontfamily = family, alpha = alpha))
  invisible(w)
}

box <- function(x, y, w, h, fill, col = NA, r = 0, lwd = 1) {
  if (r > 0) {
    grid.roundrect(X(x), Y(y), X(w), unit(h, "native"), just = c("left", "top"),
                   r = unit(r, "bigpts"), gp = gpar(fill = fill, col = col, lwd = lwd))
  } else {
    grid.rect(X(x), Y(y), X(w), unit(h, "native"), just = c("left", "top"),
              gp = gpar(fill = fill, col = col, lwd = lwd))
  }
}

image_at <- function(img, x, y, w) {
  h <- w * nrow(img) / ncol(img)
  grid.raster(img, X(x), Y(y), X(w), unit(h, "native"), just = c("left", "top"),
              interpolate = TRUE)
  box(x, y, w, h, fill = NA, col = pal$line)
  h
}

card <- function(x, y, w, h, title, sub = NULL) {
  box(x, y, w, h, fill = pal$card, col = pal$line, r = 10)
  grid.lines(X(c(x, x + w)), Y(c(y + 42, y + 42)), gp = gpar(col = pal$line))
  tw <- txt(title, x + 18, y + 21, size = 15, face = "bold")
  if (!is.null(sub)) txt(sub, x + 18 + tw + 10, y + 21, size = 12.5, col = pal$muted)
}

panel_label <- function(label, x, y) {
  txt(label, x + 2, y, size = 13, col = pal$muted, face = "bold")
}

PANEL_W <- 440
LEFT_H <- 600
RIGHT_H <- 600

# Left: the thread ------------------------------------------------------------

thread <- list(
  list(who = "Morgan (Sales)", at = "9:41 AM",
       lines = c("Hey, you're gonna hate me. Can you help me",
                 "understand what this plot means?"),
       attach = TRUE),
  list(who = "Sam (Analytics)", at = "9:52 AM",
       lines = c("Sure! Which client is this for?",
                 "And which project or study ID?")),
  list(who = "Morgan (Sales)", at = "9:58 AM",
       lines = "A retail one? It was in last quarter's deck."),
  list(who = "Sam (Analytics)", at = "10:06 AM",
       lines = c("Do you know the run ID?",
                 "Or which data snapshot it used?")),
  list(who = "Morgan (Sales)", at = "10:31 AM",
       lines = "No idea, someone forwarded it to me."),
  list(who = "Sam (Analytics)", at = "10:34 AM",
       lines = c("Which version of the script made it?",
                 "Is the original report saved anywhere?")),
  list(who = "Morgan (Sales)", at = "11:02 AM",
       lines = "Let me ask around…")
)

draw_message <- function(m, x, y, w) {
  who_col <- if (startsWith(m$who, "Sam")) pal$sam else pal$morgan
  box(x, y, 30, 30, fill = who_col, r = 6)
  txt(substr(m$who, 1, 1), x + 15, y + 15, size = 14, col = "#ffffff", face = "bold",
      just = "centre")
  tx <- x + 42
  nw <- txt(m$who, tx, y + 8, size = 14, face = "bold")
  txt(m$at, tx + nw + 8, y + 8.5, size = 11.5, col = pal$faint)
  yy <- y + 8
  for (line in m$lines) {
    yy <- yy + 20
    txt(line, tx, yy, size = 14.5, max_w = w - 42)
  }
  yy <- yy + 12
  if (isTRUE(m$attach)) {
    th <- image_at(screenshot, tx, yy, 132)
    txt("screenshot.jpg", tx + 144, yy + th - 8, size = 12, col = pal$muted)
    yy <- yy + th + 4
  }
  yy + 12
}

draw_left <- function(x, y, n_msgs) {
  panel_label("The usual thread", x, y)
  cy <- y + 18
  card(x, cy, PANEL_W, LEFT_H, "# analytics-help")
  yy <- cy + 60
  for (m in thread[seq_len(n_msgs)]) {
    yy <- draw_message(m, x + 18, yy, PANEL_W - 36)
  }
  if (yy > cy + LEFT_H) stop("Thread overflows its card by ", round(yy - cy - LEFT_H))
}

# Right: the same screenshot, traced -----------------------------------------

lineage_rows <- c("client", "project", "run", "script", "data", "output")

draw_right <- function(x, y, step) {
  panel_label("The same screenshot, with watermark", x, y)
  cy <- y + 18
  card(x, cy, PANEL_W, RIGHT_H, "Trace it in R")
  ix <- x + 18
  iy <- cy + 60
  iw <- 220
  ih <- image_at(screenshot, ix, iy, iw)

  info_x <- ix + iw + 16
  info_w <- PANEL_W - 36 - iw - 16
  txt("screenshot.jpg", info_x, iy + 10, size = 14, face = "bold", max_w = info_w)
  txt(sprintf("%d × %d px, JPEG", ncol(screenshot), nrow(screenshot)),
      info_x, iy + 31, size = 13, col = pal$muted, max_w = info_w)
  txt("No file metadata left", info_x, iy + 50, size = 13, col = pal$muted,
      max_w = info_w)

  if (step >= 2) {
    # Outline the row the decoder actually read.
    s <- iw / ncol(screenshot)
    x0 <- ix + (where$left - 2 * where$pitch) * s
    x1 <- ix + (where$right + 2 * where$pitch) * s
    ry <- iy + (where$row - 0.5) * s
    box(x0, ry - 4, x1 - x0, 8, fill = NA, col = pal$accent, r = 2, lwd = 1.4)
    box(info_x, iy + ih - 20, 22, 8, fill = NA, col = pal$accent, r = 2, lwd = 1.4)
    txt("ID read here", info_x + 30, iy + ih - 16, size = 13,
        col = pal$accent, face = "bold", max_w = info_w - 30)
  }

  # Console.
  lh <- 20
  cy2 <- iy + ih + 14
  n_lines <- c(0, 1, 2, 4)[step + 1]
  if (n_lines > 0) {
    box(ix, cy2, PANEL_W - 36, 10 + lh * n_lines, fill = pal$code_bg, r = 6)
    code <- c(sprintf('> extract_watermark("%s")', basename(screenshot_file)),
              sprintf('[1] "%s"', decoded),
              sprintf('> plots <- read.csv("%s")', basename(manifest_path)),
              sprintf('> plots[plots$id == "%s", ]', decoded))
    for (i in seq_len(n_lines)) {
      is_out <- startsWith(code[i], "[1]")
      txt(code[i], ix + 12, cy2 + 5 + lh * i - lh / 2, size = 13, family = mono,
          col = if (is_out) pal$accent else pal$ink,
          face = if (is_out) "bold" else "plain", max_w = PANEL_W - 60)
    }
  }
  if (step < 3) return(invisible())

  # Lineage: what came from the pixels, and what came from the manifest.
  ly <- cy2 + 10 + lh * 4 + 14
  lx <- ix
  lw <- PANEL_W - 36
  key_x <- lx + 12
  val_x <- lx + 86
  val_w <- lw - 86 - 8

  box(lx, ly, lw, 40, fill = pal$accent_bg, r = 6)
  txt("FROM THE PIXELS", key_x, ly + 12, size = 11.5, col = pal$accent, face = "bold")
  txt("plot ID", key_x, ly + 29, size = 13, col = pal$muted)
  txt(decoded, val_x, ly + 29, size = 14, family = mono, face = "bold",
      col = pal$accent)

  my <- ly + 52
  txt("FROM YOUR MANIFEST: plots.csv, demo data", key_x, my + 4, size = 11.5,
      col = pal$muted, face = "bold", max_w = lw - 20)
  row_h <- 21
  for (i in seq_along(lineage_rows)) {
    ry <- my + 4 + row_h * i
    txt(lineage_rows[i], key_x, ry, size = 13, col = pal$muted)
    txt(record[[lineage_rows[i]]], val_x, ry, size = 13.5, max_w = val_w)
  }

  ny <- my + 4 + row_h * length(lineage_rows) + 28
  txt("Only the ID is in the pixels. The rest is the row you",
      lx, ny, size = 13, col = pal$ink, max_w = lw)
  txt("logged when you saved the plot.", lx, ny + 18, size = 13,
      col = pal$ink, max_w = lw)
  if (ny + 18 + 14 > cy + RIGHT_H) {
    stop("Lineage overflows its card by ", round(ny + 32 - cy - RIGHT_H))
  }
}

# Scenes ----------------------------------------------------------------------

S <- 1.25
render <- function(file, w, h, draw, scale = S) {
  canvas_h <<- h
  ragg::agg_png(file, width = round(w * scale), height = round(h * scale),
                res = 72 * scale, background = pal$bg)
  pushViewport(viewport(xscale = c(0, w), yscale = c(0, h)))
  draw()
  popViewport()
  invisible(dev.off())
  png::readPNG(file)[, , 1:3]
}

GIF_W <- 2 * PANEL_W + 3 * 24
GIF_H <- 24 + 18 + LEFT_H + 24

scene <- function(n_msgs, step) {
  render(tempfile(fileext = ".png"), GIF_W, GIF_H, function() {
    draw_left(24, 24, n_msgs)
    draw_right(48 + PANEL_W, 24, step)
  })
}

# Each state is held, then cross-faded into the next. The GIF opens on the
# finished story so the first frame (all that shows when animation is off)
# makes the point, and so the loop is seamless.
states <- list(
  list(msgs = 7, step = 3, hold = 1.8),
  list(msgs = 1, step = 0, hold = 1.6),
  list(msgs = 2, step = 0, hold = 1.2),
  list(msgs = 3, step = 0, hold = 0.9),
  list(msgs = 4, step = 0, hold = 1.2),
  list(msgs = 5, step = 0, hold = 0.9),
  list(msgs = 6, step = 0, hold = 1.2),
  list(msgs = 7, step = 0, hold = 1.0),
  list(msgs = 7, step = 1, hold = 0.8),
  list(msgs = 7, step = 2, hold = 1.3),
  list(msgs = 7, step = 3, hold = 2.8)
)
fade <- c(1, 2) / 3
fade_step <- 0.07

frames_dir <- tempfile("lineage-frames")
dir.create(frames_dir)
imgs <- lapply(states, function(s) scene(s$msgs, s$step))

concat <- "ffconcat version 1.0"
n_frames <- 0L
add_frame <- function(img, duration) {
  n_frames <<- n_frames + 1L
  f <- file.path(frames_dir, sprintf("f%03d.png", n_frames))
  png::writePNG(img, f)
  concat <<- c(concat, sprintf("file '%s'", f), sprintf("duration %.2f", duration))
}
for (i in seq_along(states)) {
  add_frame(imgs[[i]], states[[i]]$hold)
  nxt <- imgs[[i %% length(imgs) + 1]]
  # The last state equals the first, so the loop needs no fade.
  if (i < length(states)) {
    for (a in fade) add_frame((1 - a) * imgs[[i]] + a * nxt, fade_step)
  }
}
concat <- c(concat, utils::tail(concat, 2)[1])  # ffmpeg drops the last duration
list_file <- file.path(frames_dir, "frames.txt")
writeLines(concat, list_file)

out <- "man/figures/lineage.gif"
status <- system2("ffmpeg", c(
  "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", shQuote(list_file),
  "-vf", shQuote(paste0(
    "split[a][b];[a]palettegen=max_colors=128:stats_mode=full[p];",
    "[b][p]paletteuse=dither=none:diff_mode=rectangle"
  )),
  "-fps_mode", "vfr", "-loop", "0", out
))
stopifnot(status == 0)

# Stills: the finished story, side by side and stacked for phones.
png::writePNG(imgs[[1]], "man/figures/lineage-still.png")
MOBILE_W <- PANEL_W + 2 * 20
MOBILE_H <- 20 + 2 * (18 + LEFT_H) + 30 + 20
invisible(render("man/figures/lineage-mobile.png", MOBILE_W, MOBILE_H, function() {
  draw_left(20, 20, 7)
  draw_right(20, 20 + 18 + LEFT_H + 30, 3)
}, scale = 2))

duration <- sum(vapply(states, `[[`, 0, "hold")) +
  (length(states) - 1) * length(fade) * fade_step
message(sprintf("Wrote %s: %d frames, %.1f s, %.0f KB; ID %s matches plots.csv",
                out, n_frames, duration, file.size(out) / 1024, decoded))
