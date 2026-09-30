# Real-world hammer: render a zoo of realistic, nasty plots with watermarks,
# push each through the pipelines a chart actually meets (headless Chrome
# screenshots, macOS sips, ffmpeg, cwebp, pdftoppm, Quick Look, crops), decode
# every result and write a Markdown report with a pass/fail matrix.
#
# Every decode is classified exact / NULL / WRONG. A WRONG ID anywhere (a
# decode that is neither NULL nor the embedded ID, including any ID read from
# a plot that carries none) makes the script exit non-zero. "Promised" cells
# follow the limits documented in README.Rmd; a promised case that returns
# NULL is listed in the report but does not fail the run.
#
# Pipelines whose tool is missing are skipped, so the script runs anywhere;
# the report lists what was skipped.
#
# Usage (from the package root):
#   Rscript tools/realworld-hammer.R            # full run, a few minutes
#   Rscript tools/realworld-hammer.R --quick    # 4 plots, no sweeps
#   Rscript tools/realworld-hammer.R --cores=4
#
# Outputs: tools/realworld-report.md and tools/realworld-results.csv
# (committed), and every intermediate image under tools/realworld-out/
# (ignored). Images that decode to a WRONG ID, or make the decoder error, are
# also copied to tools/realworld-out/keep/, which is never cleared.

t_start <- Sys.time()
args <- commandArgs(trailingOnly = TRUE)
quick <- "--quick" %in% args
cores_arg <- sub("^--cores=", "", grep("^--cores=", args, value = TRUE))
cores <- if (length(cores_arg)) as.integer(cores_arg) else
  max(1L, min(8L, parallel::detectCores() - 2L))

suppressPackageStartupMessages({
  library(ggplot2)
  if (requireNamespace("pkgload", quietly = TRUE) && file.exists("DESCRIPTION")) {
    pkgload::load_all(".", quiet = TRUE, helpers = FALSE)
  } else {
    library(gglineage)
  }
})
source("tests/testthat/helper-realworld.R")
`%||%` <- function(a, b) if (is.null(a)) b else a

out_dir <- "tools/realworld-out"
run_dir <- file.path(out_dir, "run")
keep_dir <- file.path(out_dir, "keep")
unlink(run_dir, recursive = TRUE)
dir.create(run_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(keep_dir, recursive = TRUE, showWarnings = FALSE)

chrome <- rw_chrome()
tools_found <- c(
  chrome = nzchar(chrome),
  sips = rw_has("sips"),
  ffmpeg = rw_has("ffmpeg"),
  cwebp = rw_has("cwebp") && rw_has("dwebp"),
  pdftoppm = rw_has("pdftoppm"),
  qlmanage = rw_has("qlmanage"),
  svglite = requireNamespace("svglite", quietly = TRUE)
)
has_tool <- function(t) all(vapply(t, function(x) x == "R" || isTRUE(tools_found[[x]]), logical(1)))

# ---- IDs ------------------------------------------------------------------

ids <- list(
  id8 = "K7Q2M9XD",                 # wm_id() style, 5-bit packed
  run = "RUN-42",                   # short human text
  b16 = "ZZ0123456789ABCD",         # 16 bytes, the strip's maximum
  utf8 = "Zürich-δ✓", # 13 bytes of UTF-8
  uuid = "f47ac10b-58cc-4372-a567-0e02b2c3d479",
  b12 = "ZZ0123456789",             # 12 bytes, the tiles' maximum
  utf8t = "café-δ"        # 8 bytes of UTF-8, fits tiles
)

# ---- the plot zoo ---------------------------------------------------------

set.seed(20260930)
dense_df <- data.frame(x = stats::rnorm(1e4), y = stats::rnorm(1e4))
diamonds_df <- ggplot2::diamonds[sample(nrow(ggplot2::diamonds), 5000), ]
long_caption <- paste(strwrap(paste(
  "Source: U.S. Environmental Protection Agency fuel economy data for 38",
  "popular models of cars, 1999 and 2008. Points are jittered to reduce",
  "overplotting; manufacturers with fewer than five models are included",
  "anyway because the legend is supposed to be long and annoying. Figures",
  "are preliminary and subject to revision once the audit is complete."),
  width = 110), collapse = "\n")

zoo <- list(
  list(name = "baseline", w = 7, h = 5, dpi = 150, dots = ids$id8, tiles = ids$id8,
       plot = ggplot(mtcars, aes(wt, mpg)) + geom_point()),
  list(name = "facets_3x4", w = 9, h = 6, dpi = 150, dots = ids$id8, tiles = ids$run, slow = TRUE,
       plot = ggplot(mpg, aes(displ, hwy, colour = class)) + geom_point(alpha = 0.7) +
         facet_grid(drv ~ cyl) +
         labs(title = "Highway mileage by drive train and cylinders")),
  list(name = "facet_wrap_1x2", w = 9, h = 5, dpi = 150, dots = ids$run, tiles = ids$id8,
       plot = ggplot(mpg, aes(displ, hwy)) + geom_point() + facet_wrap(~year)),
  list(name = "legend_caption", w = 8, h = 6, dpi = 150, dots = ids$b16, tiles = ids$id8,
       plot = ggplot(mpg, aes(cty, hwy, colour = manufacturer)) +
         geom_jitter(width = 0.3, height = 0.3) +
         guides(colour = guide_legend(nrow = 3)) +
         labs(title = "City vs highway", caption = long_caption) +
         theme(legend.position = "bottom")),
  list(name = "rug_outside", w = 7, h = 5, dpi = 150, dots = ids$utf8, tiles = ids$utf8t,
       plot = ggplot(faithful, aes(eruptions, waiting)) + geom_point() +
         geom_rug(sides = "b", outside = TRUE, length = unit(0.03, "npc"), alpha = 0.6) +
         coord_cartesian(clip = "off") + theme_minimal()),
  list(name = "heatmap_raster", w = 7, h = 5, dpi = 150, dots = ids$uuid, tiles = ids$id8,
       open = FALSE,
       plot = ggplot(faithfuld, aes(waiting, eruptions, fill = density)) + geom_raster() +
         scale_fill_viridis_c() + scale_x_continuous(expand = c(0, 0)) +
         scale_y_continuous(expand = c(0, 0))),
  list(name = "dense_10k", w = 7, h = 5, dpi = 200, dots = ids$id8, tiles = ids$b12,
       plot = ggplot(dense_df, aes(x, y)) + geom_point(alpha = 0.1, size = 0.8)),
  list(name = "dates_line", w = 8, h = 4.5, dpi = 150, dots = ids$uuid, tiles = ids$run,
       plot = ggplot(economics, aes(date, unemploy)) + geom_line() +
         scale_x_date(date_breaks = "5 years", date_labels = "%Y") + theme_minimal()),
  list(name = "theme_dark", w = 7, h = 5, dpi = 150, dots = ids$run, tiles = ids$run,
       tiles_args = list(colour = "white"),
       plot = ggplot(mpg, aes(displ, hwy)) + geom_point(colour = "orange") + theme_dark()),
  list(name = "black_bg", w = 7, h = 5, dpi = 150, dots = ids$id8, tiles = ids$id8,
       dots_args = list(colour = "white"), tiles_args = list(colour = "white"),
       plot = ggplot(mtcars, aes(wt, mpg)) + geom_point(colour = "#7fdbff") +
         theme_minimal() +
         theme(plot.background = element_rect(fill = "#121212", colour = NA),
               panel.background = element_rect(fill = "#1e1e1e", colour = NA),
               text = element_text(colour = "grey85"),
               axis.text = element_text(colour = "grey70"),
               panel.grid = element_line(colour = "grey25"))),
  list(name = "theme_void", w = 7, h = 5, dpi = 150, dots = ids$uuid, tiles = ids$id8,
       plot = ggplot(mtcars, aes(wt, mpg)) + geom_point(size = 3) + theme_void()),
  list(name = "tall_3x8", w = 3, h = 8, dpi = 150, dots = ids$id8, tiles = ids$run,
       plot = ggplot(mpg, aes(hwy, reorder(model, hwy))) + geom_boxplot() + labs(y = NULL)),
  list(name = "wide_12x3", w = 12, h = 3, dpi = 150, dots = ids$uuid, tiles = ids$id8,
       plot = ggplot(economics, aes(date, psavert)) +
         geom_area(fill = "steelblue", alpha = 0.3) + geom_line()),
  list(name = "small_4x3_96dpi", w = 4, h = 3, dpi = 96, dots = ids$id8, tiles = ids$run,
       tiles_args = list(pitch = 2, size = 0.7),
       plot = ggplot(mtcars, aes(wt, mpg)) + geom_point()),
  list(name = "huge_14x10_300dpi", w = 14, h = 10, dpi = 300, dots = ids$uuid, tiles = ids$id8, slow = TRUE,
       plot = ggplot(diamonds_df, aes(carat, price)) + geom_point(alpha = 0.3) +
         geom_smooth(method = "lm", formula = y ~ x)),
  list(name = "long_title", w = 7, h = 5, dpi = 150, dots = ids$b16, tiles = ids$b12,
       plot = ggplot(mtcars, aes(wt, mpg)) + geom_point() +
         labs(title = strrep("A very long plot title that just keeps on going ", 5),
              subtitle = strrep("and a subtitle that is not wrapped either ", 5))),
  list(name = "coord_polar", w = 6, h = 6, dpi = 150, dots = ids$id8, tiles = ids$run,
       open = FALSE,
       plot = ggplot(mpg, aes(x = factor(1), fill = class)) + geom_bar(width = 1) +
         coord_polar(theta = "y")),
  list(name = "text_heavy", w = 7, h = 5, dpi = 150, dots = ids$utf8, tiles = ids$utf8t,
       plot = ggplot(mtcars, aes(wt, mpg, label = rownames(mtcars))) + geom_point() +
         geom_text(size = 3, vjust = -0.8) +
         annotate("rect", xmin = 3, xmax = 4, ymin = 10, ymax = 20, alpha = 0.1, fill = "red") +
         annotate("text", x = 4.6, y = 31, label = "Heavier cars\nuse more fuel", size = 5) +
         labs(title = "Motor Trend road tests, 1974", subtitle = "Weight against mileage",
              caption = "Labels: car model. Shaded: the 3,000-4,000 lb class.",
              x = "Weight (1000 lb)", y = "Miles per US gallon"))
)
if (quick) zoo <- Filter(function(z) z$name %in% c("baseline", "facet_wrap_1x2", "heatmap_raster", "small_4x3_96dpi"), zoo)

wm_kinds <- c("dots", "tiles", "both", "none")

make_cases <- function() {
  cases <- list()
  for (z in zoo) for (kind in wm_kinds) {
    id <- switch(kind, dots = z$dots, tiles = , both = z$tiles, none = NA_character_)
    wm <- switch(kind,
      dots = list(do.call(watermark_dots, c(list(z$dots), z$dots_args))),
      tiles = list(do.call(watermark_tiles, c(list(z$tiles), z$tiles_args))),
      both = list(do.call(watermark_tiles, c(list(z$tiles), z$tiles_args)),
                  do.call(watermark_dots, c(list(z$tiles), z$dots_args))),
      none = list())
    p <- Reduce(`+`, wm, z$plot)
    cases[[length(cases) + 1L]] <- c(z[setdiff(names(z), "plot")], list(
      key = sprintf("%s.%s", z$name, kind), kind = kind, id = id, gg = p,
      open = z$open %||% TRUE, pitch = z$tiles_args$pitch %||% 3))
  }
  cases
}

render_case <- function(cs) {
  dir <- file.path(run_dir, cs$key)
  dir.create(dir, showWarnings = FALSE)
  f <- function(ext) file.path(dir, paste0("source", ext))
  ggsave(f(".png"), cs$gg, width = cs$w, height = cs$h, dpi = cs$dpi, bg = "white")
  transparent <- cs$gg + theme(plot.background = element_rect(fill = "transparent", colour = NA))
  ggsave(f("-transparent.png"), transparent, width = cs$w, height = cs$h, dpi = cs$dpi,
         bg = "transparent")
  ggsave(f(".pdf"), cs$gg, width = cs$w, height = cs$h)
  if (tools_found[["svglite"]]) ggsave(f(".svg"), cs$gg, width = cs$w, height = cs$h)
  d <- rw_png_dim(f(".png"))
  boxes <- rw_panel_boxes(cs$gg, cs$w, cs$h, cs$dpi)
  c(cs, list(dir = dir, png = f(".png"), png_t = f("-transparent.png"), pdf = f(".pdf"),
             svg = if (tools_found[["svglite"]]) f(".svg"), px_w = d[["width"]],
             px_h = d[["height"]], boxes = boxes,
             union_box = c(x0 = min(boxes[, "x0"]), y0 = min(boxes[, "y0"]),
                           x1 = max(boxes[, "x1"]), y1 = max(boxes[, "y1"]))))
}

# ---- pipelines ------------------------------------------------------------
# Each returns list(file, fig_px = figure width in output pixels, q = lossy
# quality proxy or NA for lossless, crop = crop box in source pixels or NULL).

P <- function(name, group, tools, fn, q = NA_real_) {
  list(name = name, group = group, tools = tools, fn = fn, q = q)
}
out_file <- function(cs, name, ext) {
  file.path(cs$dir, paste0(gsub("[^A-Za-z0-9]+", "_", name), ext))
}
res <- function(file, fig_px, q = NA_real_, crop = NULL) {
  list(file = file, fig_px = fig_px, q = q, crop = crop)
}

chrome_css_px <- function(css) if (identical(css, "100%")) 1232 else as.numeric(css)

pipelines <- list()
add <- function(p) pipelines[[length(pipelines) + 1L]] <<- p

# Chrome: the PNG in a web page at several CSS widths, light and dark page,
# 1x and retina, screenshot of the viewport (page padding and text included).
for (bg in c("light", "dark")) for (dpr in c(1, 2)) for (css in list("100%", 640, 480, 360)) local({
  bg <- bg; dpr <- dpr; css <- css
  nm <- sprintf("Chrome %s %s page @%dx", if (is.character(css)) css else paste0(css, "px"), bg, dpr)
  add(P(nm, "Chrome screenshot", "chrome", function(cs) {
    o <- out_file(cs, nm, ".png")
    rw_chrome_shot(cs$png, o, cs$px_h / cs$px_w, css, dpr,
                   bg = if (bg == "light") "#ffffff" else "#0d1117",
                   fg = if (bg == "light") "#1f2328" else "#e6edf3", chrome = chrome)
    res(o, chrome_css_px(css) * dpr)
  }))
})

# sips (macOS): Preview / Photos style exports.
for (q in c(90, 70, 50, 30)) local({
  q <- q
  add(P(sprintf("sips JPEG q%d", q), "sips (macOS)", "sips", function(cs) {
    o <- out_file(cs, sprintf("sips jpeg q%d", q), ".jpg")
    rw_sips_jpeg(cs$png, o, q)
    res(o, cs$px_w, q)
  }, q = q))
})
add(P("sips HEIC (iPhone/Photos)", "sips (macOS)", "sips", function(cs) {
  o <- out_file(cs, "sips heic", ".png")
  rw_sips_heic(cs$png, o)
  res(o, cs$px_w, 80)
}, q = 80))
for (w in c(1024, 640, 480)) local({
  w <- w
  add(P(sprintf("sips resample to %d px", w), "sips (macOS)", "sips", function(cs) {
    o <- out_file(cs, sprintf("sips resample %d", w), ".png")
    rw_sips_resample(cs$png, o, w)
    res(o, w)
  }))
})
add(P("sips resample 640 + JPEG q60", "sips (macOS)", "sips", function(cs) {
  mid <- out_file(cs, "sips chain mid", ".png")
  o <- out_file(cs, "sips chain 640 q60", ".jpg")
  rw_sips_resample(cs$png, mid, 640)
  rw_sips_jpeg(mid, o, 60)
  res(o, 640, 60)
}, q = 60))

# ffmpeg: 4:2:0 JPEG at several -q:v, scaling filters, chat-app chains.
for (qv in c(2, 5, 10, 20)) local({
  qv <- qv
  qq <- c(`2` = 95, `5` = 85, `10` = 70, `20` = 50)[[as.character(qv)]]
  add(P(sprintf("ffmpeg JPEG 4:2:0 -q:v %d (~q%d)", qv, qq), "ffmpeg", "ffmpeg", function(cs) {
    o <- out_file(cs, sprintf("ffmpeg jpeg qv%d", qv), ".jpg")
    rw_ffmpeg_jpeg(cs$png, o, qv)
    res(o, cs$px_w, qq)
  }, q = qq))
})
for (flags in c("bicubic", "lanczos", "area", "bilinear", "neighbor")) local({
  flags <- flags
  add(P(sprintf("ffmpeg scale 640 %s", flags), "ffmpeg", "ffmpeg", function(cs) {
    o <- out_file(cs, sprintf("ffmpeg scale 640 %s", flags), ".png")
    rw_ffmpeg_scale(cs$png, o, 640, flags)
    res(o, 640)
  }))
})
add(P("ffmpeg scale 480 neighbor", "ffmpeg", "ffmpeg", function(cs) {
  o <- out_file(cs, "ffmpeg scale 480 neighbor", ".png")
  rw_ffmpeg_scale(cs$png, o, 480, "neighbor")
  res(o, 480)
}))
add(P("Slack: fit 1024, JPEG ~q85, re-encoded", "ffmpeg", "ffmpeg", function(cs) {
  a <- out_file(cs, "slack a", ".jpg")
  o <- out_file(cs, "slack b", ".jpg")
  rw_ffmpeg_jpeg(cs$png, a, 4, vf = "scale='min(1024,iw)':-2:flags=bicubic")
  rw_ffmpeg_jpeg(a, o, 4)
  res(o, min(1024, cs$px_w), 85)
}, q = 85))
add(P("Twitter: fit 680, JPEG ~q85, re-encoded", "ffmpeg", "ffmpeg", function(cs) {
  a <- out_file(cs, "twitter a", ".jpg")
  o <- out_file(cs, "twitter b", ".jpg")
  rw_ffmpeg_jpeg(cs$png, a, 4, vf = "scale=680:-2:flags=bicubic")
  rw_ffmpeg_jpeg(a, o, 5)
  res(o, 680, 85)
}, q = 85))
add(P("Chat thumbnail: fit 360, JPEG ~q75", "ffmpeg", "ffmpeg", function(cs) {
  o <- out_file(cs, "thumb 360", ".jpg")
  rw_ffmpeg_jpeg(cs$png, o, 8, vf = "scale=360:-2:flags=bicubic")
  res(o, 360, 75)
}, q = 75))

# WebP via libwebp's own encoder (this ffmpeg build has no WebP encoder).
for (q in c(75, 50)) local({
  q <- q
  add(P(sprintf("WebP q%d (cwebp)", q), "WebP", "cwebp", function(cs) {
    o <- out_file(cs, sprintf("webp q%d", q), ".png")
    rw_webp(cs$png, o, q)
    res(o, cs$px_w, q)
  }, q = q))
})
add(P("WebP q75 at 640 px (cwebp -resize)", "WebP", "cwebp", function(cs) {
  webp <- out_file(cs, "webp 640", ".webp")
  o <- out_file(cs, "webp 640", ".png")
  rw_run("cwebp", c("-quiet", "-q", 75, "-resize", 640, 0, cs$png, "-o", webp))
  rw_run("dwebp", c(webp, "-quiet", "-o", o))
  res(o, 640, 75)
}, q = 75))

# Vector: PDF and SVG, rasterised by the tools a reader would use.
for (dpi in c(72, 110, 150, 300)) local({
  dpi <- dpi
  add(P(sprintf("PDF -> pdftoppm %d dpi", dpi), "PDF / SVG", "pdftoppm", function(cs) {
    o <- out_file(cs, sprintf("pdftoppm %d", dpi), ".png")
    rw_pdftoppm(cs$pdf, o, dpi)
    res(o, round(cs$w * dpi))
  }))
})
add(P("PDF -> sips PNG (72 dpi)", "PDF / SVG", "sips", function(cs) {
  o <- out_file(cs, "pdf sips", ".png")
  rw_sips_png(cs$pdf, o)
  res(o, round(cs$w * 72))
}))
add(P("PDF -> Quick Look 1000 px", "PDF / SVG", "qlmanage", function(cs) {
  o <- out_file(cs, "pdf ql", ".png")
  rw_qlmanage(cs$pdf, o, 1000)
  res(o, rw_png_dim(o)[["width"]])
}))
# Quick Look draws an SVG at its own page size into a 1000 px square and
# crops what doesn't fit (the right side of a wide figure, the bottom of a
# tall one), so nothing is promised here.
add(P("SVG -> Quick Look 1000 px", "PDF / SVG", c("qlmanage", "svglite"), function(cs) {
  o <- out_file(cs, "svg ql", ".png")
  rw_qlmanage(cs$svg, o, 1000)
  r <- res(o, rw_png_dim(o)[["width"]])
  r$promise <- FALSE
  r
}))
for (v in list(list("100%", 1), list(640, 2), list(480, 1))) local({
  css <- v[[1]]; dpr <- v[[2]]
  nm <- sprintf("SVG in Chrome %s @%dx", if (is.character(css)) css else paste0(css, "px"), dpr)
  add(P(nm, "PDF / SVG", c("chrome", "svglite"), function(cs) {
    o <- out_file(cs, nm, ".png")
    rw_chrome_shot(cs$svg, o, cs$h / cs$w, css, dpr, chrome = chrome)
    res(o, chrome_css_px(css) * dpr)
  }))
})

# Transparent background (ggsave(bg = "transparent")) as viewers show it.
add(P("Transparent PNG as saved", "Transparent PNG", "R", function(cs) {
  res(cs$png_t, cs$px_w)
}))
for (v in list(c("white", "0xffffff"), c("Slack dark", "0x1a1d21"), c("black", "0x000000"))) local({
  v <- v
  add(P(sprintf("Transparent on %s (ffmpeg overlay)", v[1]), "Transparent PNG", "ffmpeg", function(cs) {
    o <- out_file(cs, paste("transparent on", v[1]), ".png")
    rw_ffmpeg_composite(cs$png_t, o, v[2])
    res(o, cs$px_w)
  }))
})
add(P("Transparent on Slack dark + JPEG ~q85", "Transparent PNG", "ffmpeg", function(cs) {
  a <- out_file(cs, "transparent dark mid", ".png")
  o <- out_file(cs, "transparent dark jpeg", ".jpg")
  rw_ffmpeg_composite(cs$png_t, a, "0x1a1d21")
  rw_ffmpeg_jpeg(a, o, 5)
  res(o, cs$px_w, 85)
}, q = 85))
add(P("Transparent in Chrome dark page 640px @2x", "Transparent PNG", "chrome", function(cs) {
  o <- out_file(cs, "transparent chrome dark", ".png")
  rw_chrome_shot(cs$png_t, o, cs$px_h / cs$px_w, 640, 2, bg = "#0d1117", fg = "#e6edf3",
                 chrome = chrome)
  res(o, 1280)
}))

# Crops, as someone would make them with a screenshot tool.
crop_to <- function(cs, name, box, ext = ".png") {
  img <- png::readPNG(cs$png)
  o <- out_file(cs, name, ext)
  png::writePNG(rw_crop(img, box), o)
  res(o, cs$px_w, crop = box)
}
full_box <- function(cs) c(x0 = 1, y0 = 1, x1 = cs$px_w, y1 = cs$px_h)
square_in_panel <- function(cs, mm) {
  b <- cs$union_box
  half <- mm / 25.4 * cs$dpi / 2
  cx <- (b[["x0"]] + b[["x1"]]) / 2
  cy <- (b[["y0"]] + b[["y1"]]) / 2
  c(x0 = max(b[["x0"]], cx - half), y0 = max(b[["y0"]], cy - half),
    x1 = min(b[["x1"]], cx + half), y1 = min(b[["y1"]], cy + half))
}
add(P("Crop: top 30% off (strip kept)", "Crops", "R", function(cs) {
  b <- full_box(cs); b[["y0"]] <- round(0.3 * cs$px_h)
  crop_to(cs, "crop top30", b)
}))
add(P("Crop: bottom 4% off (strip cut)", "Crops", "R", function(cs) {
  b <- full_box(cs); b[["y1"]] <- round(0.96 * cs$px_h)
  crop_to(cs, "crop bottom4", b)
}))
add(P("Crop: left 8% off", "Crops", "R", function(cs) {
  b <- full_box(cs); b[["x0"]] <- round(0.08 * cs$px_w)
  crop_to(cs, "crop left8", b)
}))
add(P("Crop: tight around all panels", "Crops", "R", function(cs) {
  crop_to(cs, "crop panels", cs$union_box)
}))
add(P("Crop: first panel only", "Crops", "R", function(cs) {
  crop_to(cs, "crop panel1", cs$boxes[1, ])
}))
add(P("Crop: 75 mm square of panel", "Crops", "R", function(cs) {
  crop_to(cs, "crop 75mm", square_in_panel(cs, 75))
}))
add(P("Crop: tight panels + sips JPEG q80", "Crops", "sips", function(cs) {
  r <- crop_to(cs, "crop panels q80 src", cs$union_box)
  o <- out_file(cs, "crop panels q80", ".jpg")
  rw_sips_jpeg(r$file, o, 80)
  r$file <- o; r$q <- 80
  r
}, q = 80))
add(P("Crop: tight panels of Chrome 640px @2x shot", "Crops", "chrome", function(cs) {
  shot <- out_file(cs, "crop chrome shot", ".png")
  rw_chrome_shot(cs$png, shot, cs$px_h / cs$px_w, 640, 2, chrome = chrome)
  s <- 640 / cs$px_w * 2
  b <- cs$union_box
  box <- c(x0 = 24 * 2 + (b[["x0"]] - 1) * s + 1, y0 = 96 * 2 + (b[["y0"]] - 1) * s + 1,
           x1 = 24 * 2 + b[["x1"]] * s, y1 = 96 * 2 + b[["y1"]] * s)
  img <- png::readPNG(shot)
  o <- out_file(cs, "crop chrome panels", ".png")
  png::writePNG(rw_crop(img, box), o)
  res(o, 1280, crop = b)
}))

# ---- promises -------------------------------------------------------------
# What README.Rmd documents, coarsely. A promised NULL is reported, not fatal.

is_uuid <- function(id) grepl("^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$", id)

strip_kept <- function(cs, crop) {
  is.null(crop) || (crop[["x0"]] <= 1 && crop[["x1"]] >= cs$px_w && crop[["y1"]] >= cs$px_h)
}

# Visible open panel, in mm (width, height), after any crop.
panel_mm <- function(cs, crop) {
  b <- cs$union_box
  if (!is.null(crop)) {
    b <- c(x0 = max(b[["x0"]], crop[["x0"]]), y0 = max(b[["y0"]], crop[["y0"]]),
           x1 = min(b[["x1"]], crop[["x1"]]), y1 = min(b[["y1"]], crop[["y1"]]))
  }
  pmax(0, c(b[["x1"]] - b[["x0"]], b[["y1"]] - b[["y0"]])) / cs$dpi * 25.4
}

promise_dots <- function(cs, r) {
  if (isFALSE(r$promise)) return(FALSE)
  if (!cs$kind %in% c("dots", "both") || !strip_kept(cs, r$crop)) return(FALSE)
  uuid <- is_uuid(cs$id) || (cs$kind == "dots" && is_uuid(cs$dots))
  lossy <- !is.na(r$q)
  if (lossy && r$q < 50) return(FALSE)
  min_w <- if (lossy) (if (uuid) 560 else 480) else (if (uuid) 400 else 360)
  r$fig_px >= min_w
}

promise_tiles <- function(cs, r) {
  if (isFALSE(r$promise)) return(FALSE)
  if (!cs$kind %in% c("tiles", "both") || !cs$open) return(FALSE)
  if (!is.na(r$q) && r$q < 75) return(FALSE)
  px_per_pitch <- r$fig_px / (cs$w * 25.4) * cs$pitch
  if (px_per_pitch < 15) return(FALSE)  # about 150 dpi at the default pitch
  all(panel_mm(cs, r$crop) >= 70 * cs$pitch / 3)
}

# ---- run ------------------------------------------------------------------

message(sprintf("Tools: %s", paste(names(tools_found), ifelse(tools_found, "yes", "NO"),
                                  sep = "=", collapse = ", ")))
cases <- make_cases()
message(sprintf("Rendering %d cases ...", length(cases)))
cases <- lapply(cases, render_case)
names(cases) <- vapply(cases, `[[`, "", "key")

active <- Filter(function(p) has_tool(p$tools), pipelines)
skipped <- Filter(function(p) !has_tool(p$tools), pipelines)
jobs <- expand.grid(case = names(cases), pipe = seq_along(active), stringsAsFactors = FALSE)
# A NULL costs a full tile search (seconds at 1050 px, minutes on a 3 x 4
# facet grid or a 4200 px image), so unwatermarked plots, and everything but
# the strip on the slow plots, go through the core pipelines only.
core <- c("Chrome 100% light page @1x", "Chrome 480px dark page @2x",
          "Chrome 360px light page @1x", "sips JPEG q70", "sips HEIC (iPhone/Photos)",
          "sips resample to 640 px", "ffmpeg JPEG 4:2:0 -q:v 10 (~q70)",
          "ffmpeg scale 640 area", "Slack: fit 1024, JPEG ~q85, re-encoded",
          "WebP q75 (cwebp)", "PDF -> pdftoppm 150 dpi", "SVG in Chrome 640px @2x",
          "Transparent on Slack dark (ffmpeg overlay)", "Crop: bottom 4% off (strip cut)",
          "Crop: tight around all panels", "Crop: 75 mm square of panel")
is_core <- vapply(active, function(p) p$name %in% core, logical(1))
job_kind <- vapply(cases[jobs$case], `[[`, "", "kind")
job_slow <- vapply(cases[jobs$case], function(cs) isTRUE(cs$slow), logical(1))
# `both` mostly repeats `dots` (the strip wins), so it gets the core set too.
stopifnot(all(core %in% vapply(pipelines, `[[`, "", "name")))
jobs <- jobs[is_core[jobs$pipe] | job_kind == "dots" | (job_kind == "tiles" & !job_slow), ]
# Chrome jobs first: they are slowest, so scheduling them early balances cores.
jobs <- jobs[order(!vapply(jobs$pipe, function(i) "chrome" %in% active[[i]]$tools, logical(1))), ]
message(sprintf("Running %d pipeline x case jobs on %d cores ...", nrow(jobs), cores))

decode <- function(file) {
  t0 <- Sys.time()
  got <- tryCatch(extract_watermark(file), error = function(e) structure(conditionMessage(e), class = "decode_error"))
  list(got = got, secs = as.numeric(difftime(Sys.time(), t0, units = "secs")))
}

classify <- function(got, expected) {
  if (inherits(got, "decode_error")) return("ERROR")
  if (is.null(got)) return("NULL")
  if (!is.na(expected) && identical(got, expected)) return("exact")
  "WRONG"
}

run_job <- function(i) {
  cs <- cases[[jobs$case[i]]]
  p <- active[[jobs$pipe[i]]]
  r <- tryCatch(p$fn(cs), error = function(e) e)
  base <- data.frame(case = cs$key, plot = cs$name, kind = cs$kind,
                     id = cs$id %||% NA_character_, pipeline = p$name, group = p$group,
                     stringsAsFactors = FALSE)
  if (inherits(r, "error")) {
    return(cbind(base, file = NA, out_w = NA, out_h = NA, fig_px = NA, q = p$q,
                 strip = NA, panel_w_mm = NA, panel_h_mm = NA, promised_dots = FALSE,
                 promised_tiles = FALSE, got = NA, status = "PIPELINE-ERROR",
                 note = conditionMessage(r), secs = NA, stringsAsFactors = FALSE))
  }
  d <- decode(r$file)
  status <- classify(d$got, cs$id %||% NA_character_)
  dims <- tryCatch({
    if (grepl("\\.jpe?g$", r$file)) rev(dim(jpeg::readJPEG(r$file))[1:2]) else rw_png_dim(r$file)
  }, error = function(e) c(NA, NA))
  pm <- panel_mm(cs, r$crop)
  cbind(base, file = r$file, out_w = dims[[1]], out_h = dims[[2]], fig_px = r$fig_px,
        q = r$q, strip = strip_kept(cs, r$crop), panel_w_mm = round(pm[1]),
        panel_h_mm = round(pm[2]), promised_dots = promise_dots(cs, r),
        promised_tiles = promise_tiles(cs, r),
        got = if (is.character(d$got) && !inherits(d$got, "decode_error")) d$got else NA,
        status = status,
        note = if (inherits(d$got, "decode_error")) as.character(d$got) else "",
        secs = round(d$secs, 2), stringsAsFactors = FALSE)
}

rows <- parallel::mclapply(seq_len(nrow(jobs)), run_job, mc.cores = cores,
                           mc.preschedule = FALSE)
bad <- vapply(rows, inherits, logical(1), "try-error")
if (any(bad)) stop("Worker failures:\n", paste(unlist(rows[bad]), collapse = "\n"))
results <- do.call(rbind, rows)
results$promised <- results$promised_dots | results$promised_tiles
results$sweep <- ""

# ---- sweeps: where does it stop working? ----------------------------------

sweep_rows <- list()
if (!quick) {
  base <- zoo[[1]]
  sweep_cases <- lapply(list(
    list(key = "sweep.dots_id8", kind = "dots", id = ids$id8,
         gg = base$plot + watermark_dots(ids$id8)),
    list(key = "sweep.dots_uuid", kind = "dots", id = ids$uuid,
         gg = base$plot + watermark_dots(ids$uuid)),
    list(key = "sweep.tiles_id8", kind = "tiles", id = ids$id8,
         gg = base$plot + watermark_tiles(ids$id8))
  ), function(s) render_case(c(s, list(name = "baseline", w = 7, h = 5, dpi = 150,
                                       dots = ids$id8, open = TRUE, pitch = 3))))
  widths <- seq(160, 640, by = 40)
  sweeps <- list()
  if (tools_found[["chrome"]]) {
    for (w in widths) local({
      w <- w
      sweeps[[length(sweeps) + 1L]] <<- list(sweep = "Chrome, light page @1x", x = w, fn = function(cs) {
        o <- out_file(cs, sprintf("sweep chrome %d", w), ".png")
        rw_chrome_shot(cs$png, o, cs$px_h / cs$px_w, w, 1, chrome = chrome)
        res(o, w)
      })
    })
  }
  if (tools_found[["chrome"]]) {
    # Same chart pixels (480 CSS px @1x), wider and wider browser window: the
    # chart becomes a smaller fraction of the screenshot.
    for (vw in c(640, 800, 1024, 1280, 1440, 1600, 1920, 2560)) local({
      vw <- vw
      sweeps[[length(sweeps) + 1L]] <<- list(sweep = "Chrome 480px chart @1x, browser window width", x = vw, fn = function(cs) {
        o <- out_file(cs, sprintf("sweep viewport %d", vw), ".png")
        rw_chrome_shot(cs$png, o, cs$px_h / cs$px_w, 480, 1, viewport = vw, chrome = chrome)
        res(o, 480)
      })
    })
  }
  if (tools_found[["sips"]]) {
    for (w in widths) local({
      w <- w
      sweeps[[length(sweeps) + 1L]] <<- list(sweep = "sips resample + JPEG q50", x = w, fn = function(cs) {
        mid <- out_file(cs, sprintf("sweep sips %d mid", w), ".png")
        o <- out_file(cs, sprintf("sweep sips %d", w), ".jpg")
        rw_sips_resample(cs$png, mid, w)
        rw_sips_jpeg(mid, o, 50)
        res(o, w, 50)
      })
    })
  }
  if (tools_found[["ffmpeg"]]) {
    for (w in widths) local({
      w <- w
      sweeps[[length(sweeps) + 1L]] <<- list(sweep = "ffmpeg lanczos + JPEG 4:2:0 ~q85", x = w, fn = function(cs) {
        o <- out_file(cs, sprintf("sweep ffmpeg %d", w), ".jpg")
        rw_ffmpeg_jpeg(cs$png, o, 5, vf = sprintf("scale=%d:-2:flags=lanczos", w))
        res(o, w, 85)
      })
    })
  }
  for (mm in seq(40, 110, by = 10)) local({
    mm <- mm
    sweeps[[length(sweeps) + 1L]] <<- list(sweep = "Square crop of panel (mm), lossless", x = mm, fn = function(cs) {
      crop_to(cs, sprintf("sweep crop %d", mm), square_in_panel(cs, mm))
    })
  })
  sjobs <- expand.grid(case = seq_along(sweep_cases), sw = seq_along(sweeps))
  message(sprintf("Running %d sweep jobs ...", nrow(sjobs)))
  sweep_rows <- parallel::mclapply(seq_len(nrow(sjobs)), function(i) {
    cs <- sweep_cases[[sjobs$case[i]]]
    sw <- sweeps[[sjobs$sw[i]]]
    r <- tryCatch(sw$fn(cs), error = function(e) e)
    if (inherits(r, "error")) {
      return(data.frame(case = cs$key, sweep = sw$sweep, x = sw$x, status = "PIPELINE-ERROR",
                        got = NA, file = NA, stringsAsFactors = FALSE))
    }
    d <- decode(r$file)
    data.frame(case = cs$key, sweep = sw$sweep, x = sw$x, status = classify(d$got, cs$id),
               got = if (is.character(d$got)) d$got else NA, file = r$file,
               stringsAsFactors = FALSE)
  }, mc.cores = cores, mc.preschedule = FALSE)
  sweep_rows <- do.call(rbind, sweep_rows)
}

# ---- keep offending images ------------------------------------------------

offenders <- rbind(
  results[results$status %in% c("WRONG", "ERROR"), c("case", "pipeline", "file", "status", "got")],
  if (length(sweep_rows)) {
    s <- sweep_rows[sweep_rows$status %in% c("WRONG", "ERROR"), ]
    data.frame(case = s$case, pipeline = paste(s$sweep, s$x), file = s$file,
               status = s$status, got = s$got)
  }
)
if (nrow(offenders)) {
  offenders$kept <- file.path(keep_dir, paste0(offenders$case, "__",
    gsub("[^A-Za-z0-9]+", "_", offenders$pipeline), sub(".*(\\.[a-z]+)$", "\\1", offenders$file)))
  file.copy(offenders$file, offenders$kept, overwrite = TRUE)
}

# ---- report ---------------------------------------------------------------

tool_version <- function(cmd, args, pattern = ".") {
  v <- tryCatch(suppressWarnings(system2(cmd, args, stdout = TRUE, stderr = TRUE)),
                error = function(e) "")
  v <- grep(pattern, v, value = TRUE)
  if (length(v)) trimws(v[[1]]) else "?"
}
versions <- c(
  if (tools_found[["chrome"]]) tool_version(chrome, "--version"),
  if (tools_found[["ffmpeg"]]) tool_version("ffmpeg", "-version"),
  if (tools_found[["pdftoppm"]]) tool_version("pdftoppm", "-v", "pdftoppm"),
  if (tools_found[["cwebp"]]) paste("cwebp", tool_version("cwebp", "-version")),
  if (tools_found[["sips"]]) paste("sips", tool_version("sw_vers", "-productVersion"))
)

decoded <- results[results$status != "PIPELINE-ERROR", ]
count <- function(d, s) sum(d$status == s)
all_status <- c(decoded$status, if (length(sweep_rows)) sweep_rows$status[sweep_rows$status != "PIPELINE-ERROR"])
n_wrong <- sum(all_status == "WRONG")
n_error <- sum(all_status == "ERROR")
elapsed <- as.numeric(difftime(Sys.time(), t_start, units = "mins"))

by_kind <- do.call(rbind, lapply(wm_kinds, function(k) {
  d <- decoded[decoded$kind == k, ]
  data.frame(kind = k, decodes = nrow(d), exact = count(d, "exact"), null = count(d, "NULL"),
             wrong = count(d, "WRONG"), error = count(d, "ERROR"),
             promised = sum(d$promised), missed = sum(d$promised & d$status != "exact"))
}))

sym <- function(status, promised) {
  switch(status, exact = "✅", `NULL` = if (promised) "✖" else "·",
         WRONG = "❌", ERROR = "\U0001f4a5", `PIPELINE-ERROR` = "–", "?")
}
kinds_in_cell <- c("dots", "tiles", "both", "none")
plots <- vapply(zoo, `[[`, "", "name")
matrix_md <- unlist(lapply(unique(vapply(active, `[[`, "", "group")), function(g) {
  pn <- unique(results$pipeline[results$group == g])
  c(sprintf("### %s", g), "",
    paste0("| Pipeline | ", paste(plots, collapse = " | "), " |"),
    paste0("|---|", strrep(":---:|", length(plots))),
    vapply(pn, function(p) {
      cells <- vapply(plots, function(pl) {
        paste(vapply(kinds_in_cell, function(k) {
          r <- results[results$pipeline == p & results$plot == pl & results$kind == k, ]
          if (!nrow(r)) return("_")
          sym(r$status[1], r$promised[1])
        }, ""), collapse = "")
      }, "")
      sprintf("| %s | %s |", p, paste(cells, collapse = " | "))
    }, ""), "")
}))

missed <- decoded[decoded$promised & decoded$status != "exact", ]
missed_md <- if (nrow(missed)) c(
  "| Case | Pipeline | Figure px | Visible panel (mm) | Result |", "|---|---|---:|---|---|",
  sprintf("| %s | %s | %s | %s x %s | %s |", missed$case, missed$pipeline, missed$fig_px,
          missed$panel_w_mm, missed$panel_h_mm, missed$status)) else "None."

offenders_md <- if (nrow(offenders)) c(
  "| Case | Pipeline | Status | Decoded | Kept image |", "|---|---|---|---|---|",
  sprintf("| %s | %s | %s | `%s` | `%s` |", offenders$case, offenders$pipeline,
          offenders$status, offenders$got, offenders$kept)) else "None."

pipe_errors <- results[results$status == "PIPELINE-ERROR", ]
pipe_errors_md <- if (nrow(pipe_errors)) sprintf("- %s / %s: %s", pipe_errors$case,
  pipe_errors$pipeline, pipe_errors$note) else "None."

# "240-640" style runs of the sweep values that decoded exactly.
exact_ranges <- function(xs, ok) {
  if (!any(ok)) return("none")
  runs <- rle(ok)
  ends <- cumsum(runs$lengths)
  starts <- ends - runs$lengths + 1L
  parts <- ifelse(starts == ends, xs[starts], paste0(xs[starts], "–", xs[ends]))
  paste(parts[runs$values], collapse = ", ")
}

sweep_md <- character()
if (length(sweep_rows)) {
  for (sw in unique(sweep_rows$sweep)) {
    s <- sweep_rows[sweep_rows$sweep == sw, ]
    xs <- sort(unique(s$x))
    sweep_md <- c(sweep_md, sprintf("**%s**", sw), "",
      paste0("| Watermark | ", paste(xs, collapse = " | "), " | exact at |"),
      paste0("|---|", strrep(":---:|", length(xs)), "---|"),
      vapply(unique(s$case), function(k) {
        sk <- s[s$case == k, ]
        st <- sk$status[match(xs, sk$x)]
        sprintf("| %s | %s | %s |", sub("^sweep\\.", "", k),
                paste(vapply(st, sym, "", promised = FALSE), collapse = " | "),
                exact_ranges(xs, st == "exact"))
      }, ""), "")
  }
}

md <- c(
  "# Real-world pipeline hammer",
  "",
  sprintf("Generated by `tools/realworld-hammer.R`%s on %s (%s, R %s, ggplot2 %s) in %.1f min.",
          if (quick) " --quick" else "", format(Sys.Date()), Sys.info()[["sysname"]],
          getRversion(), packageVersion("ggplot2"), elapsed),
  "",
  paste0("Tools: ", paste(versions, collapse = "; "), "."),
  if (length(skipped)) paste0("Skipped (tool missing): ",
                              paste(vapply(skipped, `[[`, "", "name"), collapse = ", "), "."),
  "",
  sprintf("**%s: %d decodes (%d in the matrix, %d in sweeps): %d exact, %d NULL, %d WRONG, %d decoder errors.**",
          if (n_wrong + n_error == 0) "PASS" else "FAIL", length(all_status), nrow(decoded),
          length(all_status) - nrow(decoded), sum(all_status == "exact"),
          sum(all_status == "NULL"), n_wrong, n_error),
  sprintf("%d promised cases returned NULL; %d pipeline runs failed before decoding.",
          nrow(missed), nrow(pipe_errors)),
  "",
  "| Watermark | Decodes | Exact | NULL | WRONG | Errors | Promised | Promised but NULL |",
  "|---|---:|---:|---:|---:|---:|---:|---:|",
  sprintf("| %s | %d | %d | %d | %d | %d | %d | %d |", by_kind$kind, by_kind$decodes,
          by_kind$exact, by_kind$null, by_kind$wrong, by_kind$error, by_kind$promised,
          by_kind$missed),
  "",
  "`none` is the same plot with no watermark: anything but NULL there is a false positive.",
  "",
  "## Matrix",
  "",
  paste("Each cell is four results, for the plot with `watermark_dots()`,",
        "`watermark_tiles()`, both, and neither. ✅ exact · · NULL",
        "(not promised) · ✖ NULL where the README's limits promise a decode",
        "· ❌ WRONG ID · \U0001f4a5 decoder error · – pipeline failed · _ not run",
        "(`both`, `none`, and `tiles` on the two slow plots, run the 16 core",
        "pipelines only, to keep the run under an hour)."),
  "",
  "Plots: ",
  sprintf("- `%s`: %s x %s in at %d dpi (%d x %d px); dots `%s`, tiles `%s`%s",
          plots, vapply(zoo, `[[`, 0, "w"), vapply(zoo, `[[`, 0, "h"),
          vapply(zoo, function(z) as.integer(z$dpi), 0L),
          vapply(zoo, function(z) as.integer(round(z$w * z$dpi)), 0L),
          vapply(zoo, function(z) as.integer(round(z$h * z$dpi)), 0L),
          vapply(zoo, `[[`, "", "dots"), vapply(zoo, `[[`, "", "tiles"),
          vapply(zoo, function(z) {
            a <- c(if (!isTRUE(z$open %||% TRUE)) "panel not open (tiles not promised)",
                   if (length(z$tiles_args)) paste0("tiles(", paste(names(z$tiles_args), z$tiles_args, sep = "=", collapse = ", "), ")"),
                   if (length(z$dots_args)) paste0("dots(", paste(names(z$dots_args), z$dots_args, sep = "=", collapse = ", "), ")"))
            if (length(a)) paste0("; ", paste(a, collapse = "; ")) else ""
          }, "")),
  "",
  matrix_md,
  "## WRONG IDs and decoder errors",
  "",
  offenders_md,
  "",
  "## Promised but NULL",
  "",
  paste("Promised = strip intact, figure at least 360 px wide lossless / 480 px",
        "lossy at quality 50+ (UUID: 400 / 560); tiles: open panel, 75+ quality,",
        "15+ px per lattice pitch, and at least 70 mm x 70 mm of panel visible."),
  "",
  missed_md,
  "",
  if (length(sweep_md)) c("## Sweeps: where decoding stops", "",
    paste("Baseline 7 x 5 in scatter at 150 dpi (1050 px). Chrome/sips/ffmpeg columns",
          "are the figure's width in output pixels; the crop sweep is the side of a",
          "square crop from the panel centre, in mm; the window sweep keeps the chart",
          "at 480 px and widens the browser window around it."),
    "", sweep_md),
  "## Pipeline failures (not decodes)",
  "",
  pipe_errors_md,
  ""
)

writeLines(md, "tools/realworld-report.md")
keep_cols <- c("case", "plot", "kind", "id", "pipeline", "group", "out_w", "out_h", "fig_px",
               "q", "strip", "panel_w_mm", "panel_h_mm", "promised", "status", "got", "secs")
utils::write.csv(results[, keep_cols], "tools/realworld-results.csv", row.names = FALSE)
if (length(sweep_rows)) {
  utils::write.csv(sweep_rows[, c("case", "sweep", "x", "status", "got")],
                   "tools/realworld-sweeps.csv", row.names = FALSE)
}

cat(md[1:(grep("^## Matrix", md) - 1L)], sep = "\n")
message(sprintf("Report: tools/realworld-report.md (%.1f min)", elapsed))
if (n_wrong > 0 || n_error > 0) quit(status = 1)
