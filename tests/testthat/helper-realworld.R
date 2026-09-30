# Real-world image pipelines for stress-testing extract_watermark(): the
# same bytes a chart meets when it is screenshotted in a browser, exported by
# macOS, recompressed by a chat app or rasterised from a PDF. Unlike
# helper-transforms.R these shell out to real tools (headless Chrome, sips,
# ffmpeg, cwebp/dwebp, pdftoppm, qlmanage), so every caller must check the
# tool exists first: rw_has("ffmpeg"), rw_chrome() != "". Nothing here runs
# at load time. tools/realworld-hammer.R sources this file too.

rw_has <- function(tool) nzchar(Sys.which(tool))

# Headless Chrome or Chromium, or "" if none. CHROME_BIN overrides.
rw_chrome <- function() {
  cands <- c(
    Sys.getenv("CHROME_BIN"),
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    unname(Sys.which(c("google-chrome", "google-chrome-stable", "chromium",
                       "chromium-browser")))
  )
  cands <- cands[nzchar(cands) & file.exists(cands)]
  if (length(cands) > 0L) cands[[1]] else ""
}

# Run a tool with every argument shell-quoted; stop with its stderr on error.
#
# system() with a string we quote ourselves (R 4.6's system2() quotes the
# command on its own, so pre-quoting it there breaks, and older R doesn't).
# Output goes to a log file rather than a pipe: Chrome leaves helper
# processes holding its stdout, so reading a pipe to EOF can hang.
rw_run <- function(cmd, args, timeout = 120) {
  log <- tempfile(fileext = ".log")
  on.exit(unlink(log))
  line <- paste(shQuote(cmd), paste(shQuote(as.character(args)), collapse = " "),
                ">", shQuote(log), "2>&1 < /dev/null")
  status <- suppressWarnings(system(line, timeout = timeout))
  out <- if (file.exists(log)) readLines(log, warn = FALSE) else character()
  if (status != 0L) {
    stop(sprintf("%s exited %d%s: %s", basename(cmd), status,
                 if (status == 124L) " (timed out)" else "",
                 paste(utils::tail(out, 3L), collapse = " | ")), call. = FALSE)
  }
  invisible(out)
}

rw_png_dim <- function(file) {
  d <- dim(png::readPNG(file))
  c(width = d[2], height = d[1])
}

# ---- headless Chrome ------------------------------------------------------

# Show `img` (PNG or SVG) on a web page, the way a report, notebook or wiki
# does, and take a screenshot of the viewport. The page has padding, a
# heading and a line of text above the chart, so the screenshot includes page
# background around it. `css_width` is a CSS pixel width or "100%" (the
# `viewport` width minus padding); `dpr` is the device pixel ratio (2 for a
# retina screen). `aspect` is height / width of the image.
rw_chrome_shot <- function(img, out, aspect, css_width = 640, dpr = 1,
                           bg = "#ffffff", fg = "#1f2328", viewport = 1280,
                           chrome = rw_chrome()) {
  pad <- 24
  w_css <- if (identical(css_width, "100%")) viewport - 2 * pad else as.numeric(css_width)
  win_w <- max(viewport, w_css + 2 * pad)
  win_h <- ceiling(pad + 72 + w_css * aspect + pad + 16)
  html <- tempfile(fileext = ".html")
  on.exit(unlink(html), add = TRUE)
  writeLines(sprintf(paste0(
    '<!doctype html><html><head><meta charset="utf-8"><style>',
    'body{margin:0;padding:%dpx;background:%s;color:%s;',
    'font:16px/1.5 -apple-system,Helvetica,Arial,sans-serif}',
    'h2{margin:0 0 4px;font-size:20px;height:30px}p{margin:0 0 14px;height:24px}',
    'img{display:block;width:%s;height:auto}</style></head><body>',
    '<h2>Quarterly results</h2><p>Figure 3 from the analysis.</p>',
    '<img src="%s"></body></html>'),
    pad, bg, fg, if (identical(css_width, "100%")) "100%" else paste0(w_css, "px"),
    paste0("file://", normalizePath(img))), html)
  # No --user-data-dir: headless Chrome then uses a throwaway profile and
  # exits after the screenshot (with a fresh named profile it lingers).
  rw_run(chrome, c(
    "--headless=new", "--hide-scrollbars", "--no-first-run",
    "--no-default-browser-check", "--allow-file-access-from-files",
    "--disable-background-networking", "--disable-component-update",
    paste0("--force-device-scale-factor=", dpr),
    sprintf("--window-size=%d,%d", as.integer(win_w), as.integer(win_h)),
    paste0("--screenshot=", out),
    paste0("file://", normalizePath(html))
  ))
  if (!file.exists(out)) stop("Chrome wrote no screenshot", call. = FALSE)
  # Figure width in device pixels, for the report.
  invisible(w_css * dpr)
}

# ---- macOS sips -----------------------------------------------------------

rw_sips_jpeg <- function(input, out, quality) {
  rw_run("sips", c("-s", "format", "jpeg", "-s", "formatOptions", quality,
                   input, "--out", out))
}

rw_sips_png <- function(input, out) {
  rw_run("sips", c("-s", "format", "png", input, "--out", out))
}

# PNG -> HEIC (what an iPhone or macOS "Export" writes) -> PNG to read back.
rw_sips_heic <- function(input, out) {
  heic <- tempfile(fileext = ".heic")
  on.exit(unlink(heic))
  rw_run("sips", c("-s", "format", "heic", input, "--out", heic))
  rw_sips_png(heic, out)
}

rw_sips_resample <- function(input, out, width) {
  rw_run("sips", c("--resampleWidth", width, input, "--out", out))
}

# ---- ffmpeg ---------------------------------------------------------------

rw_ffmpeg <- function(input, out, vf = NULL, extra = NULL) {
  rw_run("ffmpeg", c("-hide_banner", "-loglevel", "error", "-y", "-i", input,
                     if (!is.null(vf)) c("-vf", vf), extra, out))
}

# JPEG with 4:2:0 chroma subsampling; -q:v 2 is about quality 95, 5 about 85,
# 10 about 70, 20 about 50.
rw_ffmpeg_jpeg <- function(input, out, qv, vf = NULL) {
  rw_ffmpeg(input, out, vf = vf, extra = c("-pix_fmt", "yuvj420p", "-q:v", qv))
}

rw_ffmpeg_scale <- function(input, out, width, flags = "bicubic") {
  rw_ffmpeg(input, out, vf = sprintf("scale=%d:-2:flags=%s", width, flags))
}

# Composite a (transparent) PNG over a flat colour, as a chat app or a
# dark-mode viewer shows it.
rw_ffmpeg_composite <- function(input, out, colour = "0x1a1d21") {
  d <- rw_png_dim(input)
  rw_run("ffmpeg", c(
    "-hide_banner", "-loglevel", "error", "-y",
    "-f", "lavfi", "-i", sprintf("color=c=%s:s=%dx%d", colour, d[["width"]], d[["height"]]),
    "-i", input,
    "-filter_complex", "[0:v]format=rgba[bg];[bg][1:v]overlay=format=auto:shortest=1,format=rgb24",
    "-frames:v", "1", out
  ))
}

# ---- WebP (libwebp's own tools) -------------------------------------------

rw_webp <- function(input, out, quality) {
  webp <- tempfile(fileext = ".webp")
  on.exit(unlink(webp))
  rw_run("cwebp", c("-quiet", "-q", quality, input, "-o", webp))
  rw_run("dwebp", c(webp, "-quiet", "-o", out))
}

# ---- vector rasterisers ---------------------------------------------------

rw_pdftoppm <- function(pdf, out, dpi) {
  prefix <- sub("\\.png$", "", out)
  rw_run("pdftoppm", c("-r", dpi, "-png", "-singlefile", pdf, prefix))
}

# Quick Look thumbnail (Finder previews, Mail attachments); `size` is the
# longest side in pixels.
rw_qlmanage <- function(input, out, size) {
  dir <- tempfile("ql-")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE))
  rw_run("qlmanage", c("-t", "-s", size, "-o", dir, input))
  made <- file.path(dir, paste0(basename(input), ".png"))
  if (!file.exists(made)) stop("qlmanage made no thumbnail", call. = FALSE)
  file.copy(made, out, overwrite = TRUE)
}

# ---- geometry -------------------------------------------------------------

# Pixel boxes (x0, y0, x1, y1; 1-based, y down) of every panel of `plot` when
# saved at width x height inches and `dpi`, read from grid's own layout.
rw_panel_boxes <- function(plot, width, height, dpi) {
  file <- tempfile(fileext = ".png")
  grDevices::png(file, width = width, height = height, units = "in", res = dpi)
  on.exit({
    grDevices::dev.off()
    unlink(file)
  })
  grid::grid.newpage()
  grid::grid.draw(ggplot2::ggplotGrob(plot))
  grid::grid.force()
  vps <- grid::grid.ls(viewports = TRUE, grobs = FALSE, print = FALSE)$name
  vps <- unique(vps[grepl("^panel", vps)])
  boxes <- lapply(vps, function(vp) {
    grid::seekViewport(vp)
    loc <- grid::deviceLoc(grid::unit(c(0, 1), "npc"), grid::unit(c(0, 1), "npc"),
                           valueOnly = TRUE)
    grid::upViewport(0)
    c(x0 = floor(loc$x[1] * dpi) + 1, y0 = floor((height - loc$y[2]) * dpi) + 1,
      x1 = ceiling(loc$x[2] * dpi), y1 = ceiling((height - loc$y[1]) * dpi))
  })
  do.call(rbind, boxes)
}

rw_crop <- function(img, box) {
  box <- round(box)
  img[max(1, box[["y0"]]):min(dim(img)[1], box[["y1"]]),
      max(1, box[["x0"]]):min(dim(img)[2], box[["x1"]]), , drop = FALSE]
}
