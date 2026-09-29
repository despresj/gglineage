# Image transforms for stress-testing extract_watermark(). Everything works on
# numeric arrays (height x width x channels, values in [0, 1]) in pure R, so
# the suite needs no ImageMagick. README.Rmd sources this file too.

render_plot <- function(plot, width = 7, height = 5, dpi = 150) {
  file <- tempfile(fileext = ".png")
  on.exit(unlink(file))
  ggplot2::ggsave(file, plot, width = width, height = height, dpi = dpi,
                  bg = "white")
  img <- png::readPNG(file)
  if (dim(img)[3] == 4L) img <- img[, , 1:3]
  img
}

clamp01 <- function(x) pmin(pmax(x, 0), 1)

per_channel <- function(img, f) {
  if (length(dim(img)) == 2L) return(f(img))
  chans <- lapply(seq_len(dim(img)[3]), function(i) f(img[, , i]))
  array(unlist(chans), dim = c(dim(chans[[1]]), length(chans)))
}

# Resampling matrix (n_out x n_in): area averaging when shrinking (what
# browsers and screenshot tools do), linear interpolation when enlarging.
resample_matrix <- function(n_in, n_out) {
  m <- matrix(0, n_out, n_in)
  if (n_out <= n_in) {
    edges <- seq(0, n_in, length.out = n_out + 1)
    for (i in seq_len(n_out)) {
      lo <- edges[i]
      hi <- edges[i + 1]
      for (j in (floor(lo) + 1):ceiling(hi)) {
        m[i, j] <- min(hi, j) - max(lo, j - 1)
      }
      m[i, ] <- m[i, ] / sum(m[i, ])
    }
  } else {
    pos <- (seq_len(n_out) - 0.5) * n_in / n_out + 0.5
    pos <- pmin(pmax(pos, 1), n_in)
    lo <- floor(pos)
    hi <- pmin(lo + 1, n_in)
    frac <- pos - lo
    m[cbind(seq_len(n_out), lo)] <- 1 - frac
    m[cbind(seq_len(n_out), hi)] <- m[cbind(seq_len(n_out), hi)] + frac
  }
  m
}

tf_resize <- function(img, scale) {
  h <- dim(img)[1]
  w <- dim(img)[2]
  rh <- resample_matrix(h, max(1, round(h * scale)))
  rw <- resample_matrix(w, max(1, round(w * scale)))
  per_channel(img, function(ch) rh %*% ch %*% t(rw))
}

tf_resize_to_width <- function(img, width) tf_resize(img, width / dim(img)[2])

tf_jpeg <- function(img, quality) {
  file <- tempfile(fileext = ".jpg")
  on.exit(unlink(file))
  jpeg::writeJPEG(img, file, quality = quality / 100)
  jpeg::readJPEG(file)
}

tf_png <- function(img) {
  file <- tempfile(fileext = ".png")
  on.exit(unlink(file))
  png::writePNG(img, file)
  png::readPNG(file)
}

# Fractions of the image to remove from each side.
tf_crop <- function(img, top = 0, bottom = 0, left = 0, right = 0) {
  h <- dim(img)[1]
  w <- dim(img)[2]
  rows <- (floor(h * top) + 1):(h - floor(h * bottom))
  cols <- (floor(w * left) + 1):(w - floor(w * right))
  img[rows, cols, , drop = FALSE]
}

# Embed in a larger canvas, like a screenshot that catches surrounding UI.
tf_pad <- function(img, px, fill = 0.94) {
  d <- dim(img)
  out <- array(fill, c(d[1] + 2 * px, d[2] + 2 * px, d[3]))
  out[px + seq_len(d[1]), px + seq_len(d[2]), ] <- img
  out
}

tf_noise <- function(img, sd) clamp01(img + stats::rnorm(length(img), 0, sd))

tf_blur <- function(img, radius) {
  box <- function(n) {
    m <- outer(seq_len(n), seq_len(n), function(i, j) abs(i - j) <= radius)
    m / rowSums(m)
  }
  bh <- box(dim(img)[1])
  bw <- box(dim(img)[2])
  per_channel(img, function(ch) bh %*% ch %*% t(bw))
}

tf_levels <- function(img, contrast = 1, brightness = 0) {
  clamp01((img - 0.5) * contrast + 0.5 + brightness)
}

tf_gamma <- function(img, gamma) img^gamma

tf_gray <- function(img) {
  g <- 0.299 * img[, , 1] + 0.587 * img[, , 2] + 0.114 * img[, , 3]
  array(g, c(dim(g), 3))
}

tf_posterize <- function(img, levels) round(img * (levels - 1)) / (levels - 1)

tf_invert <- function(img) 1 - img

tf_rotate90 <- function(img) {
  per_channel(img, function(ch) t(ch)[, rev(seq_len(nrow(ch)))])
}

# Named transforms, each a function of an image. `survives` records what the
# package promises; the tests hold it to that and README.Rmd reports all of
# them. `slow` ones are skipped on CRAN to keep check time down.
stress_transforms <- function() {
  list(
    list(name = "Original PNG", group = "Lossless",
         f = identity, survives = TRUE),
    list(name = "PNG re-save", group = "Lossless",
         f = tf_png, survives = TRUE),
    list(name = "JPEG quality 95", group = "Compression",
         f = function(x) tf_jpeg(x, 95), survives = TRUE),
    list(name = "JPEG quality 75", group = "Compression",
         f = function(x) tf_jpeg(x, 75), survives = TRUE),
    list(name = "JPEG quality 50", group = "Compression",
         f = function(x) tf_jpeg(x, 50), survives = TRUE),
    list(name = "JPEG quality 25", group = "Compression",
         f = function(x) tf_jpeg(x, 25), survives = TRUE),
    list(name = "JPEG q75, re-encoded 10 times", group = "Compression",
         f = function(x) Reduce(function(a, i) tf_jpeg(a, 75), 1:10, x),
         survives = TRUE, slow = TRUE),
    list(name = "JPEG -> PNG -> JPEG", group = "Compression",
         f = function(x) tf_jpeg(tf_png(tf_jpeg(x, 80)), 80), survives = TRUE),
    list(name = "Downscale to 75%", group = "Resize",
         f = function(x) tf_resize(x, 0.75), survives = TRUE),
    list(name = "Downscale to 50%", group = "Resize",
         f = function(x) tf_resize(x, 0.5), survives = TRUE),
    list(name = "Upscale 2x (retina)", group = "Resize",
         f = function(x) tf_resize(x, 2), survives = TRUE, slow = TRUE),
    list(name = "Odd scale 0.83x", group = "Resize",
         f = function(x) tf_resize(x, 0.83), survives = TRUE),
    list(name = "Downscale to 640 px wide", group = "Resize",
         f = function(x) tf_resize_to_width(x, 640), survives = TRUE),
    list(name = "Crop top 30%", group = "Crop & frame",
         f = function(x) tf_crop(x, top = 0.3), survives = TRUE),
    list(name = "Pad with light UI chrome", group = "Crop & frame",
         f = function(x) tf_pad(x, 60), survives = TRUE),
    list(name = "Pad with dark UI chrome", group = "Crop & frame",
         f = function(x) tf_pad(x, 60, fill = 0.12), survives = TRUE),
    list(name = "Screenshot chain (2x, pad, 0.5x, JPEG 80)", group = "Crop & frame",
         f = function(x) tf_jpeg(tf_resize(tf_pad(tf_resize(x, 2), 80), 0.5), 80),
         survives = TRUE, slow = TRUE),
    list(name = "Brightness +5%", group = "Colour",
         f = function(x) tf_levels(x, brightness = 0.05), survives = TRUE),
    list(name = "Contrast 70%", group = "Colour",
         f = function(x) tf_levels(x, contrast = 0.7), survives = TRUE),
    list(name = "Gamma 1.8", group = "Colour",
         f = function(x) tf_gamma(x, 1.8), survives = TRUE),
    list(name = "Grayscale", group = "Colour",
         f = tf_gray, survives = TRUE),
    list(name = "Inverted (dark mode)", group = "Colour",
         f = tf_invert, survives = TRUE),
    list(name = "Posterize to 32 levels", group = "Colour",
         f = function(x) tf_posterize(x, 32), survives = TRUE),
    list(name = "Gaussian noise sd 0.01", group = "Degrade",
         f = function(x) tf_noise(x, 0.01), survives = TRUE),
    list(name = "Box blur radius 1", group = "Degrade",
         f = function(x) tf_blur(x, 1), survives = TRUE, slow = TRUE),
    list(name = "Social re-share (0.6x, JPEG 70, x3)", group = "Degrade",
         f = function(x) Reduce(function(a, i) tf_jpeg(tf_resize(a, 0.9), 70), 1:3,
                                tf_resize(x, 0.6 / 0.729)),
         survives = TRUE, slow = TRUE),
    list(name = "Shrink to 640 px wide + JPEG 50", group = "Degrade",
         f = function(x) tf_jpeg(tf_resize_to_width(x, 640), 50),
         survives = TRUE),
    # Documented limits: these must not decode, and must never decode wrongly.
    list(name = "Crop bottom 5%", group = "Past the limits",
         f = function(x) tf_crop(x, bottom = 0.05), survives = FALSE),
    list(name = "Crop left 10%", group = "Past the limits",
         f = function(x) tf_crop(x, left = 0.1), survives = FALSE),
    list(name = "Rotate 90 degrees", group = "Past the limits",
         f = tf_rotate90, survives = FALSE),
    list(name = "Brightness +15% (dots clip to white)", group = "Past the limits",
         f = function(x) tf_levels(x, brightness = 0.15), survives = FALSE),
    list(name = "JPEG quality 5", group = "Past the limits",
         f = function(x) suppressWarnings(tf_jpeg(x, 5)), survives = FALSE),
    list(name = "Shrink to 430 px wide + JPEG 50", group = "Past the limits",
         f = function(x) tf_jpeg(tf_resize_to_width(x, 430), 50),
         survives = FALSE),
    list(name = "Downscale to 25%", group = "Past the limits",
         f = function(x) tf_resize(x, 0.25), survives = FALSE)
  )
}
