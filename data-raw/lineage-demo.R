# "Where did this chart come from?": the README animation.
#
# Left, the usual thread: a client wants to act on a chart, all anyone has is
# a screenshot from their deck, and the six things Sam would need to check
# the recommendation are unknown. Right, the same screenshot traced with
# gglineage. Sam's questions are also the six rows of the lineage ledger on
# the right: each thing Sam asks for turns a row into "unknown", and the
# decode fills them back in. On desktop Sam then closes the thread: the
# source run is found, and the recommendation can now be checked (the trace
# recovers the source; it does not vouch for the conclusion).
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
#    card is the manifest row, and the animation says so. The loupe strip is
#    the JPEG's own pixels around the dot row, magnified with no smoothing and
#    with its contrast stretched, and it is labelled as such.
#
# Run from the package root (needs ffmpeg on the PATH):
#   Rscript data-raw/lineage-demo.R
#
# Writes man/figures/lineage.gif (README hero, two panels), man/figures/
# lineage-mobile.gif (the same story as one column, two acts, for narrow
# screens) and man/figures/lineage-still.png (the finished desktop frame), and
# refreshes the demo manifest and screenshot in data-raw/lineage-demo/, so
# anyone can check the decode:
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

# A full UUID (version 7, so it starts with a timestamp), made once with
# wm_uuid(version = 7) and fixed here so the build is reproducible. All 128
# bits go into the dots, as two rows.
id <- "01a0f026-9e3e-729b-9cfa-87c8dd7bfb55"
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

# A screenshot of part of the slide, shrunk by a Retina display, saved as a
# JPEG by a chat app. The figure ends up about 570 px wide inside it, wider
# than a two-row UUID needs inside a padded JPEG at this quality (see the
# README's measured limits), so the decode is not a lucky one.
screenshot <- tf_crop(slide, top = 0.02, bottom = 0.03, left = 0.01, right = 0.1)
screenshot <- tf_resize(screenshot, 0.7)
screenshot_file <- "data-raw/lineage-demo/screenshot.jpg"
jpeg::writeJPEG(screenshot, screenshot_file, quality = 0.6)
screenshot <- jpeg::readJPEG(screenshot_file)

# 3. Trace it -----------------------------------------------------------------

decoded <- extract_watermark(screenshot_file)
stopifnot(identical(decoded, id))
plots <- utils::read.csv(manifest_path, fileEncoding = "UTF-8")
record <- plots[plots$id == decoded, ]
stopifnot(nrow(record) == 1L)
where <- find_watermark(as_gray(screenshot))
stopifnot(identical(where$id, decoded), identical(where$kind, "uuid"))
# A UUID is two rows of dots; the lower holds bytes 1-8, the upper 9-16.
dot_rows <- sort(c(where$row, where$partner_row))

# "No file metadata": list the JPEG's marker segments. A file with EXIF, XMP,
# ICC or a comment would carry APP1..APP15 or COM segments; this one must have
# none (APP0 is the bare JFIF header libjpeg always writes).
jpeg_segments <- function(file) {
  b <- readBin(file, "raw", file.size(file))
  stopifnot(identical(b[1:2], as.raw(c(0xff, 0xd8))))
  i <- 3L
  markers <- character()
  while (i < length(b)) {
    stopifnot(b[i] == as.raw(0xff))
    m <- as.integer(b[i + 1L])
    markers <- c(markers, sprintf("%02X", m))
    if (m == 0xda) break  # start of scan: entropy-coded data until EOI
    len <- as.integer(b[i + 2L]) * 256L + as.integer(b[i + 3L])
    i <- i + 2L + len
  }
  markers
}
segments <- jpeg_segments(screenshot_file)
metadata_segments <- segments[segments %in% c(sprintf("%02X", 0xe1:0xef), "FE")]
stopifnot(length(metadata_segments) == 0L)
message(sprintf("Decoded %s from %s (%d x %d px, JPEG); rows %d and %d, 2 x %d bits at %.2f px/bit; segments %s",
                decoded, basename(screenshot_file), ncol(screenshot),
                nrow(screenshot), dot_rows[1], dot_rows[2], where$n_bits, where$pitch,
                paste(segments, collapse = " ")))

# Drawing ---------------------------------------------------------------------
#
# Layout is in design units with the origin at the top left; one unit is one
# point at 72 dpi, so font sizes and positions share a scale. `S` sets output
# pixels per unit.

pal <- list(
  bg = "#f3f4f6", card = "#ffffff", line = "#e5e7eb", ink = "#1f2328",
  muted = "#6b7280", faint = "#9ca3af", accent = "#0f766e",
  accent_bg = "#ecf6f4", code_bg = "#f6f8fa", warn = "#b45309", warn_bg = "#fff7ed",
  morgan = "#a16207", sam = "#3b5b92", chip = "#f3f4f6"
)
S <- 1.25

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

box <- function(x, y, w, h, fill, col = NA, r = 0, lwd = 1, alpha = 1) {
  gp <- gpar(fill = fill, col = col, lwd = lwd, alpha = alpha)
  if (r > 0) {
    grid.roundrect(X(x), Y(y), X(w), unit(h, "native"), just = c("left", "top"),
                   r = unit(r, "bigpts"), gp = gp)
  } else {
    grid.rect(X(x), Y(y), X(w), unit(h, "native"), just = c("left", "top"), gp = gp)
  }
}

hline <- function(x0, x1, y, col = pal$line) {
  grid.lines(X(c(x0, x1)), Y(c(y, y)), gp = gpar(col = col))
}

image_at <- function(img, x, y, w) {
  h <- w * nrow(img) / ncol(img)
  grid.raster(img, X(x), Y(y), X(w), unit(h, "native"), just = c("left", "top"),
              interpolate = TRUE)
  box(x, y, w, h, fill = NA, col = pal$line)
  h
}

card <- function(x, y, w, h, title = NULL, sub = NULL) {
  box(x, y, w, h, fill = pal$card, col = pal$line, r = 10)
  hline(x, x + w, y + 42)
  if (is.null(title)) return(invisible())
  tw <- txt(title, x + 20, y + 21, size = 15, face = "bold")
  if (!is.null(sub)) txt(sub, x + 20 + tw + 10, y + 21, size = 12.5, col = pal$muted)
}

panel_label <- function(label, x, y) {
  txt(label, x + 2, y + 24, size = 13.5, col = pal$muted, face = "bold")
}

avatar <- function(x, y, who, alpha = 1) {
  col <- if (startsWith(who, "Sam")) pal$sam else pal$morgan
  box(x, y, 30, 30, fill = col, r = 6, alpha = alpha)
  txt(substr(who, 1, 1), x + 15, y + 15, size = 14, col = "#ffffff", face = "bold",
      just = "centre", alpha = alpha)
}

# Slack's "is typing" row: three dots in a pill and a muted label.
typing <- function(x, y, who) {
  box(x, y, 44, 22, fill = pal$chip, r = 11)
  for (i in 0:2) {
    grid.circle(X(x + 12 + i * 10), Y(y + 11), r = unit(2.6, "native"),
                gp = gpar(fill = pal$faint, col = NA))
  }
  txt(sprintf("%s is typing", who), x + 54, y + 11, size = 12, col = pal$faint)
}

question_chip <- function(x, y) {
  box(x, y - 8, 18, 16, fill = pal$warn_bg, col = NA, r = 4)
  txt("?", x + 9, y, size = 12, col = pal$warn, face = "bold", just = "centre")
}

# The loupe: the JPEG's own pixels around the two dot rows, drawn with no
# smoothing at an integer number of device pixels per image pixel, with the
# darkness of every pixel multiplied by `gain`. `cursor` in [0, 1] draws the
# reading bar that sweeps the strip. The strip starts just left of the
# frame's first dot, so the alternating start sync is in view.
LOUPE_COLS <- round(where$left) - 4 + 0:157
LOUPE_ROWS <- (dot_rows[1] - 4):(dot_rows[2] + 4)
LOUPE_ZOOM <- 3   # device pixels per image pixel
LOUPE_GAIN <- 2.5
loupe <- function(x, y, cursor = NA) {
  crop <- screenshot[LOUPE_ROWS, LOUPE_COLS, , drop = FALSE]
  crop <- clamp01(1 - (1 - crop) * LOUPE_GAIN)
  w <- length(LOUPE_COLS) * LOUPE_ZOOM / S
  h <- length(LOUPE_ROWS) * LOUPE_ZOOM / S
  grid.raster(crop, X(x), Y(y), X(w), unit(h, "native"), just = c("left", "top"),
              interpolate = FALSE)
  box(x, y, w, h, fill = NA, col = pal$line)
  if (!is.na(cursor)) {
    cx <- x + cursor * w
    box(x, y, cx - x, h, fill = pal$accent, col = NA, alpha = 0.10)
    grid.lines(X(c(cx, cx)), Y(c(y - 3, y + h + 3)), gp = gpar(col = pal$accent, lwd = 2))
  }
  h
}
loupe_label <- sprintf(
  "pixel rows %d–%d, columns %d–%d · each pixel ×%d · contrast ×%g",
  min(LOUPE_ROWS), max(LOUPE_ROWS), min(LOUPE_COLS), max(LOUPE_COLS), LOUPE_ZOOM, LOUPE_GAIN
)

PANEL_W <- 420
CARD_H <- 676
PAD <- 20
INNER_W <- PANEL_W - 2 * PAD

# Left: the thread ------------------------------------------------------------

# Lines are wrapped by hand (each must fit the card's text width). `asks`
# names the ledger rows a message turns to "unknown". The first N_PLAY
# messages are the exchange that stalls; the last one is Sam's reply after
# the trace, shown only in the desktop finale.
thread <- list(
  list(who = "Morgan (Accounts)", at = "9:41 AM",
       lines = c("Hey, you're gonna hate me. The client wants",
                 "to move ahead based on this chart. Can we",
                 "stand behind that recommendation?"),
       attach = TRUE),
  list(who = "Sam (Analytics)", at = "9:52 AM",
       lines = "Which client is this for?",
       asks = "client"),
  list(who = "Morgan (Accounts)", at = "9:58 AM",
       lines = "I've only got the screenshot from their deck."),
  list(who = "Sam (Analytics)", at = "10:06 AM",
       lines = "Which study was this? Do you have the run ID?",
       asks = c("project", "run")),
  list(who = "Morgan (Accounts)", at = "10:31 AM",
       lines = "No idea, sorry. They want an answer today."),
  list(who = "Sam (Analytics)", at = "10:34 AM",
       lines = c("Can you find the original report? I can't check",
                 "it without the data snapshot and script version."),
       asks = c("data", "script", "output")),
  list(who = "Sam (Analytics)", at = "10:47 AM",
       lines = c("Never mind, found the source run.",
                 "Let's check the recommendation."))
)
N_PLAY <- 6L             # messages exchanged before Sam traces the screenshot
N_ALL <- length(thread)  # ... plus Sam's reply once the trace is done
first_name <- function(who) sub(" .*", "", who)
# The rows Sam has asked about once the first n messages are up.
asked_after <- function(n) unlist(lapply(thread[seq_len(n)], `[[`, "asks"))

draw_message <- function(m, x, y, w, alpha = 1, dy = 0) {
  y <- y + dy
  avatar(x, y, m$who, alpha)
  tx <- x + 42
  nw <- txt(m$who, tx, y + 8, size = 14, face = "bold", alpha = alpha)
  txt(m$at, tx + nw + 8, y + 8.5, size = 11.5, col = pal$faint, alpha = alpha)
  yy <- y + 8
  for (line in m$lines) {
    yy <- yy + 20
    txt(line, tx, yy, size = 14.5, max_w = w - 42, alpha = alpha)
  }
  yy <- yy + 12
  if (isTRUE(m$attach)) {
    th <- image_at(screenshot, tx, yy, 132)
    txt("screenshot.jpg", tx + 144, yy + th - 8, size = 12, col = pal$muted, alpha = alpha)
    yy <- yy + th + 4
  }
  yy + 12 - dy
}

# `rise` in (0, 1] fades and lifts the newest message into place.
draw_left <- function(x, y, n_msgs, typing_who = NULL, rise = 1) {
  panel_label("The usual thread", x, y)
  cy <- y + 42
  card(x, cy, PANEL_W, CARD_H, "# analytics-help", "thread")
  yy <- cy + 60
  for (i in seq_len(n_msgs)) {
    last <- i == n_msgs
    yy <- draw_message(thread[[i]], x + PAD, yy, INNER_W,
                       alpha = if (last) rise else 1, dy = if (last) 8 * (1 - rise) else 0)
  }
  if (!is.null(typing_who)) typing(x + PAD + 42, yy - 2, typing_who)
  if (yy > cy + CARD_H) stop("Thread overflows its card by ", round(yy - cy - CARD_H))
}

# Right: the same screenshot, traced -----------------------------------------

lineage_rows <- c("client", "project", "run", "data", "script", "output")
console_lines <- c(
  sprintf('> id <- extract_watermark("%s")', basename(screenshot_file)),
  "> id",
  sprintf('[1] "%s"', decoded),
  "> plots[plots$id == id, ]"
)
N_CONSOLE <- length(console_lines)
LH <- 20  # console line height
# The UUID, broken after its third group, for the ledger's two-line ID box.
id_lines <- c(sub("^(.{19}).*", "\\1", decoded), sub("^.{19}", "", decoded))

draw_console <- function(x, y, w, n, cursor = FALSE, prompt = FALSE) {
  if (n == 0 && !prompt) return(invisible())
  if (n == 0) {
    # An idle R prompt: the session is there before anything is typed.
    box(x, y, w, 10 + LH, fill = pal$code_bg, r = 6)
    txt(">", x + 12, y + 5 + LH / 2, size = 13, family = mono, col = pal$muted)
    return(invisible())
  }
  box(x, y, w, 10 + LH * n, fill = pal$code_bg, r = 6)
  for (i in seq_len(n)) {
    is_out <- startsWith(console_lines[i], "[1]")
    txt(console_lines[i], x + 12, y + 5 + LH * i - LH / 2, size = 13, family = mono,
        col = if (is_out) pal$accent else pal$ink, face = if (is_out) "bold" else "plain",
        max_w = w - 24)
  }
  if (cursor) {
    cw <- text_width(console_lines[n], 13, "plain", mono)
    box(x + 12 + cw + 3, y + 5 + LH * n - LH / 2 - 7, 7, 14, fill = pal$ink, col = NA)
  }
}

# Every element has a fixed slot, so nothing moves while the story plays:
# image and facts at the top, loupe and console in the middle, the ledger
# anchored to the bottom. `asked` rows show "? unknown"; the first `filled`
# rows show the manifest values (the newest at `fill_alpha`).
draw_right <- function(x, y, asked = character(), console = 0, prompt = TRUE, cursor = FALSE,
                       scan = NA, loupe_on = FALSE, id_shown = FALSE, filled = 0,
                       fill_alpha = 1, note = FALSE) {
  panel_label("The same screenshot, traced with gglineage", x, y)
  cy <- y + 42
  card(x, cy, PANEL_W, CARD_H, "Trace it", "R console")
  ix <- x + PAD
  iy <- cy + 58
  iw <- 196
  ih <- image_at(screenshot, ix, iy, iw)
  info_x <- ix + iw + 16
  info_w <- INNER_W - iw - 16
  txt("screenshot.jpg", info_x, iy + 10, size = 14, face = "bold", max_w = info_w)
  txt(sprintf("%d × %d px, JPEG", ncol(screenshot), nrow(screenshot)),
      info_x, iy + 31, size = 13, col = pal$muted, max_w = info_w)
  txt("No file metadata", info_x, iy + 50, size = 13, col = pal$muted, max_w = info_w)
  txt("Forwarded from a slide deck", info_x, iy + 69, size = 13, col = pal$muted, max_w = info_w)

  show_row <- loupe_on || !is.na(scan) || id_shown
  if (show_row) {
    # Outline the two rows the decoder read, on the thumbnail.
    s <- iw / ncol(screenshot)
    x0 <- ix + (where$left - 2 * where$pitch) * s
    x1 <- ix + (where$right + 2 * where$pitch) * s
    ry0 <- iy + (dot_rows[1] - 0.5) * s
    ry1 <- iy + (dot_rows[2] + 0.5) * s
    box(x0, ry0 - 4, x1 - x0, ry1 - ry0 + 8, fill = NA, col = pal$accent, r = 2, lwd = 1.4)
  }
  if (id_shown) {
    box(info_x, iy + ih - 38, 22, 10, fill = NA, col = pal$accent, r = 2, lwd = 1.4)
    txt("ID read from", info_x + 30, iy + ih - 33, size = 13,
        col = pal$accent, face = "bold", max_w = info_w - 30)
    txt("these two rows", info_x + 30, iy + ih - 15, size = 13,
        col = pal$accent, face = "bold", max_w = info_w - 30)
  }

  # Loupe slot, on a whole device pixel so the magnified pixels stay square.
  ly <- ceiling((iy + ih + 10) * S) / S
  lh <- length(LOUPE_ROWS) * LOUPE_ZOOM / S
  if (show_row) {
    loupe(ix, ly, cursor = scan)
    txt(loupe_label, ix, ly + lh + 11, size = 11, col = pal$muted, max_w = INNER_W)
  }
  # Console slot, all its lines reserved.
  csy <- ly + lh + 24
  draw_console(ix, csy, INNER_W, console, cursor = cursor, prompt = prompt)

  # The ledger, anchored to the bottom of the card.
  bottom <- cy + CARD_H - PAD
  key_x <- ix + 12
  val_x <- ix + 86
  val_w <- INNER_W - 86 - 8
  row_h <- 21
  note_h <- 3 * 18
  rows_h <- 4 + row_h * length(lineage_rows) + 8
  id_box_h <- 66
  id_h <- id_box_h + 14
  block_top <- bottom - note_h - 12 - rows_h - id_h
  stopifnot(block_top >= csy + 10 + LH * N_CONSOLE + 10)
  yy <- block_top
  if (id_shown) {
    box(ix, yy, INNER_W, id_box_h, fill = pal$accent_bg, r = 6)
    txt("FROM THE PIXELS", key_x, yy + 14, size = 11.5, col = pal$accent, face = "bold")
    txt("plot ID", key_x, yy + 34, size = 13, col = pal$muted)
    # The UUID on two lines, broken after a hyphen, so it stays legible on a
    # phone.
    for (i in seq_along(id_lines)) {
      txt(id_lines[i], val_x, yy + 34 + 18 * (i - 1), size = 16, family = mono,
          face = "bold", col = pal$accent, max_w = val_w)
    }
  }
  yy <- yy + id_h
  hw <- txt("WHAT SAM NEEDS TO KNOW", key_x, yy + 4, size = 11.5, col = pal$muted, face = "bold")
  if (console >= N_CONSOLE) {
    # The lookup has been typed: the rows are about to come from the manifest.
    txt("from plots.csv", key_x + hw + 10, yy + 4.5, size = 11.5, col = pal$accent,
        face = "bold", max_w = INNER_W - hw - 22)
  }
  for (i in seq_along(lineage_rows)) {
    key <- lineage_rows[i]
    ry <- yy + 4 + row_h * i
    txt(key, key_x, ry, size = 13, col = pal$muted)
    if (i <= filled) {
      txt(record[[key]], val_x, ry, size = 13.5, max_w = val_w,
          alpha = if (i == filled) fill_alpha else 1)
    } else if (key %in% asked) {
      question_chip(val_x, ry)
      txt("unknown", val_x + 26, ry, size = 13, col = pal$faint)
    } else {
      txt("—", val_x, ry, size = 13, col = pal$line)
    }
  }
  yy <- yy + rows_h + 12
  if (note) {
    lines <- c("Only the ID is in the pixels. The rest is the row you logged",
               "in plots.csv when you saved the plot. Client, project and",
               "run are demo values; script, data and output are real.")
    for (i in seq_along(lines)) {
      txt(lines[i], ix, yy + 4 + 18 * (i - 1), size = 13, max_w = INNER_W)
    }
  }
}

# Scenes ----------------------------------------------------------------------

render <- function(w, h, draw, file = tempfile(fileext = ".png")) {
  canvas_h <<- h
  ragg::agg_png(file, width = round(w * S), height = round(h * S),
                res = 72 * S, background = pal$bg)
  pushViewport(viewport(xscale = c(0, w), yscale = c(0, h)))
  draw()
  popViewport()
  invisible(dev.off())
  png::readPNG(file)[, , 1:3]
}

GUTTER <- 20
GIF_W <- 2 * PANEL_W + 3 * GUTTER
GIF_H <- 42 + CARD_H + 22
MOBILE_W <- PANEL_W + 2 * GUTTER

# Desktop: both panels side by side.
scene <- function(left, right) {
  render(GIF_W, GIF_H, function() {
    do.call(draw_left, c(list(x = GUTTER, y = 0), left))
    do.call(draw_right, c(list(x = 2 * GUTTER + PANEL_W, y = 0), right))
  })
}
# Mobile: one column, one panel at a time; `blank` is the empty card shell
# the two acts fade through.
mobile_scene <- function(left = NULL, right = NULL, blank = FALSE) {
  render(MOBILE_W, GIF_H, function() {
    if (blank) card(GUTTER, 42, PANEL_W, CARD_H)
    if (!is.null(left)) do.call(draw_left, c(list(x = GUTTER, y = 0), left))
    if (!is.null(right)) do.call(draw_right, c(list(x = GUTTER, y = 0), right))
  })
}

# A frame list for ffmpeg's concat demuxer: holds are single long frames,
# transitions run at FPS (12.5, so every transition frame is exactly 8
# hundredths of a second, the unit GIF delays are stored in). Each state is
# rendered once and cached by its arguments, so identical frames cost one
# render.
FPS <- 12.5
ease <- function(t) t * t * (3 - 2 * t)
new_timeline <- function(dir) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  tl <- new.env()
  tl$dir <- dir
  tl$n <- 0L
  tl$concat <- "ffconcat version 1.0"
  tl$duration <- 0
  tl$cache <- list()
  tl
}
add_frame <- function(tl, img, duration) {
  tl$n <- tl$n + 1L
  f <- file.path(tl$dir, sprintf("f%03d.png", tl$n))
  png::writePNG(img, f)
  tl$concat <- c(tl$concat, sprintf("file '%s'", f), sprintf("duration %.3f", duration))
  tl$duration <- tl$duration + duration
  invisible(img)
}
cached <- function(tl, key, make) {
  key <- paste(deparse(key, width.cutoff = 500L), collapse = "")
  if (is.null(tl$cache[[key]])) tl$cache[[key]] <- make()
  tl$cache[[key]]
}

write_gif <- function(tl, out, max_kb) {
  # ffmpeg drops the last duration, so repeat the last file.
  concat <- c(tl$concat, utils::tail(tl$concat, 2)[1])
  list_file <- file.path(tl$dir, "frames.txt")
  writeLines(concat, list_file)
  status <- system2("ffmpeg", c(
    "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", shQuote(list_file),
    "-vf", shQuote(paste0(
      "split[a][b];[a]palettegen=max_colors=128:stats_mode=full[p];",
      "[b][p]paletteuse=dither=none:diff_mode=rectangle"
    )),
    "-fps_mode", "vfr", "-loop", "0", out
  ))
  stopifnot(status == 0)
  kb <- file.size(out) / 1024
  if (kb > max_kb) stop(sprintf("%s is %.0f KB, over the %d KB budget", out, kb, max_kb))
  message(sprintf("Wrote %s: %d frames, %.1f s, %.0f KB", out, tl$n, tl$duration, kb))
}

# The story, as beats shared by both GIFs ------------------------------------
#
# `frame(left, right)` renders a state for the current layout. The thread
# beats only touch the left panel; the trace beats only the right one.

thread_beats <- function(tl, frame, with_ledger = TRUE) {
  R <- function(n) if (with_ledger) list(asked = asked_after(n)) else list(asked = character())
  add_frame(tl, frame(list(n_msgs = 1), R(1)), 2.3)
  for (m in 2:N_PLAY) {
    who <- first_name(thread[[m]]$who)
    is_sam <- who == "Sam"
    add_frame(tl, frame(list(n_msgs = m - 1, typing_who = who), R(m - 1)),
              if (is_sam) 0.65 else 0.45)
    for (r in c(0.35, 0.7)) add_frame(tl, frame(list(n_msgs = m, rise = r), R(m - 1)), 1 / FPS)
    if (is_sam && with_ledger) {
      # The question lands, then a beat later its rows turn to "unknown".
      add_frame(tl, frame(list(n_msgs = m), R(m - 1)), 0.25)
      add_frame(tl, frame(list(n_msgs = m), R(m)), 1.95)
    } else {
      add_frame(tl, frame(list(n_msgs = m), R(m)),
                if (is_sam) 2.2 else if (m == N_PLAY) 1.2 else 1.0)
    }
  }
}

# `closing(rise)`, if given, renders Sam's reply lifting into the thread once
# the ledger is full; while the rows fill, the thread shows Sam typing.
trace_beats <- function(tl, frame, final, closing = NULL) {
  L <- list(n_msgs = N_PLAY)
  LT <- if (is.null(closing)) L else c(L, list(typing_who = "Sam"))
  all_asked <- asked_after(N_PLAY)
  add_frame(tl, frame(L, list(asked = all_asked, console = 1, cursor = TRUE)), 0.6)
  add_frame(tl, frame(L, list(asked = all_asked, console = 1, cursor = TRUE, loupe_on = TRUE)), 0.4)
  for (k in 1:9) {
    add_frame(tl, frame(L, list(asked = all_asked, console = 1, cursor = TRUE,
                                scan = ease(k / 9))), 1 / FPS)
  }
  # `> id` and its printed UUID arrive together; the lookup line follows.
  add_frame(tl, frame(L, list(asked = all_asked, console = 3, id_shown = TRUE)), 1.7)
  add_frame(tl, frame(L, list(asked = all_asked, console = 4, id_shown = TRUE)), 0.7)
  for (i in seq_along(lineage_rows)) {
    add_frame(tl, frame(LT, list(asked = all_asked, console = 4, id_shown = TRUE, filled = i,
                                 fill_alpha = 0.45)), 1 / FPS)
    add_frame(tl, frame(LT, list(asked = all_asked, console = 4, id_shown = TRUE, filled = i)),
              if (i < length(lineage_rows)) 0.16 else 0.5)
  }
  if (!is.null(closing)) for (r in c(0.35, 0.7)) add_frame(tl, closing(r), 1 / FPS)
  add_frame(tl, final, 2.0)
}

FINAL_RIGHT <- list(asked = lineage_rows, console = 4, id_shown = TRUE, filled = 6, note = TRUE)

# Desktop GIF ------------------------------------------------------------------
#
# Opens on the finished story (the first frame is the static preview), rewinds
# with a short fade, plays, and ends on the same finished frame so the loop
# has no seam. The opener's elements all sit where they do in the final frame,
# so the rewind is a pure fade-out of what the story adds. The finished story
# includes Sam's reply in the thread, posted once the ledger is full.

frames_dir <- tempfile("lineage-frames")
tl <- new_timeline(file.path(frames_dir, "desktop"))
frame <- function(left, right) cached(tl, list(left, right), function() scene(left, right))
final <- frame(list(n_msgs = N_ALL), FINAL_RIGHT)
add_frame(tl, final, 2.4)
opener <- frame(list(n_msgs = 1), list())
for (t in c(0.25, 0.5, 0.75)) add_frame(tl, (1 - ease(t)) * final + ease(t) * opener, 1 / FPS)
thread_beats(tl, frame)
trace_beats(tl, frame, final,
            closing = function(rise) frame(list(n_msgs = N_ALL, rise = rise), FINAL_RIGHT))
write_gif(tl, "man/figures/lineage.gif", max_kb = 600)
png::writePNG(final, "man/figures/lineage-still.png")

# Mobile GIF --------------------------------------------------------------------
#
# One column, two acts: the thread, then the trace panel (its six rows
# already "unknown", since Sam has just asked). Acts change by a short fade
# through the empty card, which is far cheaper than a slide and never
# overlays one act's text on the other's. Opens and closes on the finished
# trace panel; the rewind is the same fade back to the thread's first message.
# Sam's closing reply is desktop-only: here the filled ledger is the finale.

tm <- new_timeline(file.path(frames_dir, "mobile"))
mframe <- function(left = NULL, right = NULL, blank = FALSE) {
  cached(tm, list(left, right, blank), function() mobile_scene(left, right, blank))
}
m_blank <- mframe(blank = TRUE)
fade_through <- function(from, to) {
  for (t in c(0.4, 0.75)) add_frame(tm, (1 - t) * from + t * m_blank, 1 / FPS)
  add_frame(tm, m_blank, 1 / FPS)
  for (t in c(0.35, 0.7)) add_frame(tm, (1 - t) * m_blank + t * to, 1 / FPS)
}
m_final <- mframe(right = FINAL_RIGHT)
add_frame(tm, m_final, 2.4)
fade_through(m_final, mframe(left = list(n_msgs = 1)))
thread_beats(tm, function(left, right) mframe(left = left), with_ledger = FALSE)
trace_opener <- mframe(right = list(asked = lineage_rows))
fade_through(mframe(left = list(n_msgs = N_PLAY)), trace_opener)
add_frame(tm, trace_opener, 0.9)
trace_beats(tm, function(left, right) mframe(right = right), m_final)
write_gif(tm, "man/figures/lineage-mobile.gif", max_kb = 450)

message(sprintf("ID %s matches plots.csv; script %s", decoded, record$script))
