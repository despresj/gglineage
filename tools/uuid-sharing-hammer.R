# UUID durability under "passed around" screenshots.
#
# Each trial renders a realistic chart carrying a fresh random UUID, then
# sends it through a random chain of 1-5 real-world hops: a browser
# screenshot (light or dark page, 1x/2x/3x), a user cropping the chart out,
# a chat or social app recompressing it (Slack, X, WhatsApp, email, iMessage
# HEIC, Discord WebP), a retina image halved when pasted into a document.
# The image is decoded after every hop, so the report shows survival by hop
# count, and every result is checked: anything other than the exact UUID or
# NULL is a WRONG ID.
#
# Usage (from the package root; needs Chrome, sips, ffmpeg, cwebp/dwebp):
#   Rscript tools/uuid-sharing-hammer.R [--trials=400] [--cores=6] [--seed=1]

suppressPackageStartupMessages({
  library(ggplot2)
  pkgload::load_all(".", quiet = TRUE, helpers = FALSE)
})
source("tests/testthat/helper-transforms.R")
source("tests/testthat/helper-realworld.R")

args <- commandArgs(trailingOnly = TRUE)
arg <- function(name, default) {
  hit <- grep(paste0("^--", name, "="), args, value = TRUE)
  if (length(hit)) as.numeric(sub(".*=", "", hit[1])) else default
}
n_trials <- arg("trials", 400)
cores <- arg("cores", max(1L, parallel::detectCores() - 2L))
seed <- arg("seed", 1)

chrome <- rw_chrome()
stopifnot(nzchar(chrome), rw_has("sips"), rw_has("ffmpeg"), rw_has("cwebp"))
out_root <- file.path("tools", "uuid-sharing-out")
dir.create(out_root, showWarnings = FALSE, recursive = TRUE)

# ---- charts ----------------------------------------------------------------

plots <- list(
  scatter = list(plot = function() ggplot(mtcars, aes(wt, mpg)) + geom_point(),
                 w = 7, h = 5, dpi = 150),
  facets = list(plot = function() ggplot(mpg, aes(displ, hwy)) + geom_point() +
                  facet_wrap(~drv), w = 9, h = 5, dpi = 150),
  legend_caption = list(plot = function() ggplot(mpg, aes(displ, hwy, colour = class)) +
                          geom_point() + theme(legend.position = "bottom") +
                          labs(title = "Fuel economy", caption = "Source: EPA"),
                        w = 8, h = 6, dpi = 150),
  dates = list(plot = function() ggplot(economics, aes(date, unemploy)) + geom_line() +
                 theme_minimal(), w = 8, h = 4.5, dpi = 150),
  bars = list(plot = function() ggplot(mpg, aes(class, fill = drv)) + geom_bar() +
                theme_classic(), w = 7, h = 5, dpi = 150),
  dark = list(plot = function() ggplot(mtcars, aes(wt, mpg)) + geom_point(colour = "#7fdbff") +
                theme_dark() + theme(plot.background = element_rect(fill = "grey10"),
                                     text = element_text(colour = "grey85")),
              w = 7, h = 5, dpi = 150, colour = "white"),
  wide = list(plot = function() ggplot(economics, aes(date, psavert)) + geom_area(alpha = 0.4) +
                theme_minimal(), w = 10, h = 4, dpi = 150),
  small = list(plot = function() ggplot(mtcars, aes(hp, qsec)) + geom_point(),
               w = 6, h = 4, dpi = 110),
  big = list(plot = function() ggplot(diamonds, aes(carat, price)) + geom_point(alpha = 0.1),
             w = 12, h = 8, dpi = 200)
)

# ---- hops ------------------------------------------------------------------
# Each hop takes the current PNG and state (the chart's bounding box in the
# image, in pixels, and the lowest JPEG-equivalent quality so far) and
# returns a new PNG and state.

pages <- c(white = "#ffffff", github_dark = "#0d1117", slack_dark = "#1a1d21",
           light_grey = "#f6f8fa")

img_width <- function(file) rw_png_dim(file)[["width"]]
img_height <- function(file) rw_png_dim(file)[["height"]]

scale_box <- function(box, s) box * s

hop_chrome <- function(input, output, st, rng) {
  css <- sample(c(360, 480, 640, 800, 1000), 1)
  dpr <- sample(c(1, 2, 2, 3), 1)
  page <- sample(names(pages), 1)
  w <- img_width(input)
  h <- img_height(input)
  css <- min(css, 1280 - 48)
  rw_chrome_shot(input, output, aspect = h / w, css_width = css, dpr = dpr,
                 bg = pages[[page]], fg = if (page %in% c("white", "light_grey")) "#1f2328" else "#e6edf3",
                 chrome = chrome)
  # The image sits at (24, 24 + 72) CSS px; see rw_chrome_shot().
  s <- css / w
  st$box <- c(x0 = 24 + st$box[["x0"]] * s, y0 = 96 + st$box[["y0"]] * s,
              x1 = 24 + st$box[["x1"]] * s, y1 = 96 + st$box[["y1"]] * s) * dpr
  list(st = st, label = sprintf("Chrome %dpx @%gx on %s", css, dpr, page))
}

hop_crop <- function(input, output, st, rng) {
  img <- png::readPNG(input)
  W <- dim(img)[2]
  H <- dim(img)[1]
  m <- sample(0:30, 4, replace = TRUE)
  x0 <- max(1, floor(st$box[["x0"]]) - m[1])
  y0 <- max(1, floor(st$box[["y0"]]) - m[2])
  x1 <- min(W, ceiling(st$box[["x1"]]) + m[3])
  y1 <- min(H, ceiling(st$box[["y1"]]) + m[4])
  png::writePNG(img[y0:y1, x0:x1, , drop = FALSE], output)
  st$box <- st$box - c(x0 - 1, y0 - 1, x0 - 1, y0 - 1)
  list(st = st, label = sprintf("crop to chart (+%d..%d px)", min(m), max(m)))
}

fit_width <- function(input, output, max_w) {
  w <- img_width(input)
  if (w > max_w) {
    rw_ffmpeg_scale(input, output, max_w, flags = "bicubic")
    max_w / w
  } else {
    file.copy(input, output, overwrite = TRUE)
    1
  }
}

jpeg_hop <- function(input, output, st, max_w, qv, q_equiv, label) {
  tmp <- tempfile(fileext = ".png")
  on.exit(unlink(tmp))
  s <- fit_width(input, tmp, max_w)
  jpg <- tempfile(fileext = ".jpg")
  on.exit(unlink(jpg), add = TRUE)
  rw_ffmpeg_jpeg(tmp, jpg, qv)
  rw_ffmpeg(jpg, output)
  st$box <- st$box * s
  st$q <- min(st$q, q_equiv)
  list(st = st, label = label)
}

hop_platform <- function(input, output, st, rng) {
  which <- sample(c("slack", "x", "whatsapp", "email", "imessage", "discord", "teams"), 1)
  switch(which,
    slack = jpeg_hop(input, output, st, 1600, 4, 88, "Slack (fit 1600, JPEG ~88)"),
    x = jpeg_hop(input, output, st, 1200, 5, 85, "X (fit 1200, JPEG ~85)"),
    whatsapp = jpeg_hop(input, output, st, 1600, 10, 70, "WhatsApp (fit 1600, JPEG ~70)"),
    email = {
      tmp <- tempfile(fileext = ".png")
      on.exit(unlink(tmp))
      s <- fit_width(input, tmp, 1024)
      jpg <- tempfile(fileext = ".jpg")
      rw_sips_jpeg(tmp, jpg, 75)
      rw_ffmpeg(jpg, output)
      unlink(jpg)
      st$box <- st$box * s
      st$q <- min(st$q, 75)
      list(st = st, label = "email (fit 1024, sips JPEG 75)")
    },
    imessage = {
      rw_sips_heic(input, output)
      st$q <- min(st$q, 80)
      list(st = st, label = "iMessage (HEIC)")
    },
    discord = {
      tmp <- tempfile(fileext = ".png")
      on.exit(unlink(tmp))
      s <- fit_width(input, tmp, 1280)
      rw_webp(tmp, output, 75)
      st$box <- st$box * s
      st$q <- min(st$q, 75)
      list(st = st, label = "Discord (fit 1280, WebP 75)")
    },
    teams = jpeg_hop(input, output, st, 800, 8, 75, "Teams preview (fit 800, JPEG ~75)")
  )
}

hop_halve <- function(input, output, st, rng) {
  w <- img_width(input)
  rw_ffmpeg_scale(input, output, max(2L, as.integer(round(w / 2 / 2) * 2)),
                  flags = sample(c("lanczos", "area", "bicubic"), 1))
  st$box <- st$box * (img_width(output) / w)
  list(st = st, label = "retina image halved (pasted into a doc)")
}

hop_phone <- function(input, output, st, rng) {
  w <- img_width(input)
  h <- img_height(input)
  page <- sample(c("white", "github_dark"), 1)
  rw_chrome_shot(input, output, aspect = h / w, css_width = 342, dpr = 3,
                 bg = pages[[page]], viewport = 390, chrome = chrome)
  s <- 342 / w
  st$box <- c(x0 = 24 + st$box[["x0"]] * s, y0 = 96 + st$box[["y0"]] * s,
              x1 = 24 + st$box[["x1"]] * s, y1 = 96 + st$box[["y1"]] * s) * 3
  list(st = st, label = sprintf("phone screenshot (390pt @3x, %s)", page))
}

hops <- list(chrome = hop_chrome, crop = hop_crop, platform = hop_platform,
             halve = hop_halve, phone = hop_phone)
hop_weights <- c(chrome = 3, crop = 2, platform = 4, halve = 1, phone = 1)

# ---- trials ----------------------------------------------------------------

# Durability judged against the documented limits for a UUID: quality 50
# holds down to about 400 px of chart width, quality 35 (or a padded
# screenshot) needs about 480. Report against both a strict promise (chart
# >= 480 px, quality >= 50) and the raw outcome.
promised <- function(st) {
  chart_w <- st$box[["x1"]] - st$box[["x0"]]
  chart_w >= 480 && st$q >= 50
}

# Charts are rendered up front, in this process: macOS kills forked workers
# that touch the font system (ragg uses CoreText), so the parallel part only
# shells out to the image tools and decodes.
render_trial <- function(i) {
  set.seed(seed * 100000 + i)
  name <- sample(names(plots), 1)
  spec <- plots[[name]]
  id <- wm_uuid(version = sample(c(4, 7), 1))
  dir <- file.path(out_root, sprintf("t%04d", i))
  dir.create(dir, showWarnings = FALSE)
  src <- file.path(dir, "h0.png")
  ggsave(src, spec$plot() + watermark_dots(id, colour = spec$colour %||% "grey30"),
         width = spec$w, height = spec$h, dpi = spec$dpi, bg = "white")
  list(name = name, id = id, dir = dir, src = src)
}

run_trial <- function(i, made) {
  set.seed(seed * 100000 + i + 0.5)
  name <- made$name
  id <- made$id
  dir <- made$dir
  src <- made$src
  st <- list(box = c(x0 = 0, y0 = 0, x1 = img_width(src), y1 = img_height(src)), q = 100)
  n_hops <- sample(1:5, 1, prob = c(0.2, 0.25, 0.25, 0.15, 0.15))
  # Every chain starts with someone screenshotting the chart.
  chain <- c(sample(c("chrome", "phone"), 1, prob = c(4, 1)),
             if (n_hops > 1) sample(names(hops), n_hops - 1, replace = TRUE, prob = hop_weights))
  rows <- list()
  current <- src
  for (h in seq_along(chain)) {
    nxt <- file.path(dir, sprintf("h%d.png", h))
    step <- tryCatch(hops[[chain[h]]](current, nxt, st), error = function(e) e)
    if (inherits(step, "error")) {
      rows[[h]] <- data.frame(trial = i, plot = name, id = id, hop = h, step = chain[h],
                              label = conditionMessage(step), chart_px = NA, q = st$q,
                              promised = NA, status = "PIPELINE-ERROR", secs = NA)
      break
    }
    st <- step$st
    t0 <- Sys.time()
    got <- tryCatch(extract_watermark(nxt), error = function(e) paste("ERROR:", conditionMessage(e)))
    secs <- as.numeric(Sys.time() - t0, units = "secs")
    status <- if (is.null(got)) "NULL" else if (identical(got, id)) "exact" else
      if (startsWith(got, "ERROR:")) "DECODER-ERROR" else "WRONG"
    rows[[h]] <- data.frame(trial = i, plot = name, id = id, hop = h, step = chain[h],
                            label = step$label,
                            chart_px = round(st$box[["x1"]] - st$box[["x0"]]),
                            q = st$q, promised = promised(st), status = status,
                            secs = round(secs, 2),
                            got = if (status == "WRONG") got else "")
    current <- nxt
  }
  # Keep only interesting trials on disk.
  res <- do.call(rbind, lapply(rows, function(r) { if (is.null(r$got)) r$got <- ""; r }))
  if (!any(res$status %in% c("WRONG", "DECODER-ERROR") | (res$promised %in% TRUE & res$status == "NULL"))) {
    unlink(dir, recursive = TRUE)
  }
  res
}

started <- Sys.time()
cat(sprintf("Rendering %d charts ...\n", n_trials))
made <- lapply(seq_len(n_trials), render_trial)
cat(sprintf("Running %d trials on %d cores (seed %d) ...\n", n_trials, cores, seed))
results <- parallel::mclapply(seq_len(n_trials), function(i) {
  tryCatch(run_trial(i, made[[i]]), error = function(e) {
    data.frame(trial = i, plot = NA, id = NA, hop = NA, step = NA, label = conditionMessage(e),
               chart_px = NA, q = NA, promised = NA, status = "TRIAL-ERROR", secs = NA, got = "")
  })
}, mc.cores = cores, mc.preschedule = FALSE)
res <- do.call(rbind, results)
minutes <- as.numeric(Sys.time() - started, units = "mins")
utils::write.csv(res, "tools/uuid-sharing-results.csv", row.names = FALSE)

# ---- report ----------------------------------------------------------------

decoded <- res[res$status %in% c("exact", "NULL", "WRONG", "DECODER-ERROR"), ]
n_wrong <- sum(decoded$status == "WRONG")
n_err <- sum(decoded$status == "DECODER-ERROR")
prom <- decoded[decoded$promised %in% TRUE, ]
final <- do.call(rbind, lapply(split(decoded, decoded$trial), function(d) d[which.max(d$hop), ]))
pct <- function(x) sprintf("%.1f%%", 100 * mean(x))

by_hop <- do.call(rbind, lapply(sort(unique(decoded$hop)), function(h) {
  d <- decoded[decoded$hop == h, ]
  p <- d[d$promised %in% TRUE, ]
  data.frame(hop = h, decodes = nrow(d), exact = pct(d$status == "exact"),
             promised = nrow(p), promised_exact = if (nrow(p)) pct(p$status == "exact") else "-",
             wrong = sum(d$status == "WRONG"))
}))
by_width <- do.call(rbind, lapply(list(c(0, 300), c(300, 400), c(400, 480), c(480, 640),
                                       c(640, 1000), c(1000, Inf)), function(b) {
  d <- decoded[!is.na(decoded$chart_px) & decoded$chart_px >= b[1] & decoded$chart_px < b[2], ]
  data.frame(chart_px = sprintf("%s-%s", b[1], b[2]), decodes = nrow(d),
             exact = if (nrow(d)) pct(d$status == "exact") else "-",
             wrong = sum(d$status == "WRONG"))
}))
by_step <- do.call(rbind, lapply(split(decoded, decoded$label), function(d) {
  data.frame(hop = d$label[1], decodes = nrow(d), exact = pct(d$status == "exact"),
             promised_null = sum(d$promised %in% TRUE & d$status == "NULL"))
}))
by_step <- by_step[order(-by_step$decodes), ]

fails <- prom[prom$status != "exact", ]
md <- c(
  "# UUID durability: screenshots passed around",
  "",
  sprintf("Generated by `tools/uuid-sharing-hammer.R` on %s in %.1f min (%d trials, seed %d, %d cores).",
          format(Sys.Date()), minutes, n_trials, seed, cores),
  "",
  sprintf("**%s: %d decodes after every hop of %d chains. %d exact, %d NULL, %d WRONG, %d decoder errors.**",
          if (n_wrong + n_err == 0) "PASS" else "FAIL", nrow(decoded), length(unique(decoded$trial)),
          sum(decoded$status == "exact"), sum(decoded$status == "NULL"), n_wrong, n_err),
  "",
  sprintf("Within the documented limits (chart at least 480 px wide, every JPEG at quality 50 or better): **%d of %d exact (%s)**.",
          sum(prom$status == "exact"), nrow(prom), if (nrow(prom)) pct(prom$status == "exact") else "-"),
  sprintf("End of chain, all trials: %d of %d exact (%s).", sum(final$status == "exact"), nrow(final), pct(final$status == "exact")),
  sprintf("Pipeline or trial errors (tools failing, not the decoder): %d.",
          sum(res$status %in% c("PIPELINE-ERROR", "TRIAL-ERROR"))),
  "",
  "## Survival by hop", "",
  "| Hop | Decodes | Exact | Within limits | Within limits, exact | WRONG |", "|---:|---:|---:|---:|---:|---:|",
  sprintf("| %d | %d | %s | %d | %s | %d |", by_hop$hop, by_hop$decodes, by_hop$exact,
          by_hop$promised, by_hop$promised_exact, by_hop$wrong),
  "", "## By the chart's final width", "",
  "| Chart px | Decodes | Exact | WRONG |", "|---|---:|---:|---:|",
  sprintf("| %s | %d | %s | %d |", by_width$chart_px, by_width$decodes, by_width$exact, by_width$wrong),
  "", "## By hop type", "",
  "| Hop | Decodes | Exact | Within limits but NULL |", "|---|---:|---:|---:|",
  sprintf("| %s | %d | %s | %d |", by_step$hop, by_step$decodes, by_step$exact, by_step$promised_null),
  "", "## Within limits but not exact", "",
  if (nrow(fails)) sprintf("- trial %d (%s), hop %d: %s, chart %d px, q %d: **%s** (images in `tools/uuid-sharing-out/t%04d/`)",
                           fails$trial, fails$plot, fails$hop, fails$label, fails$chart_px, fails$q,
                           fails$status, fails$trial) else "None."
)
writeLines(md, "tools/uuid-sharing-report.md")
cat(md[1:12], sep = "\n")
if (n_wrong + n_err > 0) quit(status = 1)
