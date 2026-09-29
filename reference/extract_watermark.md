# Recover a dot watermark from an image

Scans an image for the dot code written by
[`watermark_dots()`](https://despresj.github.io/watermark/reference/watermark_dots.md)
and decodes it. Works on the original file, screenshots, and
recompressed or rescaled copies, as long as the bottom strip of the
figure is intact and the image is not rotated.

## Usage

``` r
extract_watermark(image, debug = FALSE)
```

## Arguments

- image:

  Path to a PNG or JPEG file, or a numeric array of pixel intensities in
  `[0, 1]` (height x width, optionally x channels), as returned by
  [`png::readPNG()`](https://rdrr.io/pkg/png/man/readPNG.html) or
  [`jpeg::readJPEG()`](https://rdrr.io/pkg/jpeg/man/readJPEG.html).

- debug:

  If `TRUE`, report which row decoded and the estimated bit pitch.

## Value

The embedded ID, or `NULL` if no valid code was found.

## Details

Every row of the image is a candidate; a row is accepted only if its
start and end sync patterns, length byte and CRC-8 checksum all agree,
so false positives are vanishingly rare.

## Examples

``` r
library(ggplot2)
p <- ggplot(mtcars, aes(wt, mpg)) + geom_point()

file <- tempfile(fileext = ".png")
ggsave(file, add_watermark(p, "RUN-42"), width = 6, height = 4, dpi = 150)
extract_watermark(file)
#> [1] "RUN-42"
```
