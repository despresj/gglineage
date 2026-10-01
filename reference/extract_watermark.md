# Recover a dot watermark from an image

Scans an image for the dot code written by
[`watermark_dots()`](https://despresj.github.io/watermark/reference/watermark_dots.md)
and decodes it; if no strip is found, looks for the tiles written by
[`watermark_tiles()`](https://despresj.github.io/watermark/reference/watermark_tiles.md).
Works on the original file, screenshots, and recompressed or rescaled
copies. The strip needs the bottom of the figure intact; tiles survive
crops that keep about two tiles across in each direction of open panel.
Rotated images are not supported. When a plot carries both, the strip's
ID is returned.

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

  If `TRUE`, report which rows decoded and the estimated bit pitch, or
  each stage of the tile decoder.

## Value

The embedded ID as a plain string, or `NULL` if no valid code was found.
Text IDs come back exactly as given. UUIDs come back in canonical
lowercase form (`xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`), and only a UUID
has that form: text IDs are at most 16 bytes, so the two cannot be
confused. Nothing else is returned: the dots carry the ID and nothing
more, so what the ID *means* (the script, data and run behind the plot)
is whatever you recorded against it when you saved the plot.

## Details

Every row of the image is a candidate; a row is accepted only if its
start and end sync patterns, header and 32-bit checksum all agree, so
false positives are vanishingly rare. A UUID is spread over two such
rows, one above the other; each row is checked on its own and against
the whole UUID, so a UUID is returned only when both of its rows are
read, and halves of two different UUIDs (charts stacked in a report,
say) are never joined. Tiles are voted on across every visible copy and
accepted only if their CRC-16 passes for exactly one ID. That 16-bit
check is much weaker than the strip's: a corrupted tile reading slips
through it about once in 65,000 tries, for instance when a crop holds
tiles of two charts with different IDs. Where a wrong ID would matter,
rely on the strip.

The result names an ID that was drawn in the image, or is `NULL`. An
image holding several marked charts (a collage, a stacked report)
decodes to one of them, the strip nearest the bottom first; crop to the
chart you mean. Mirrored, flipped and rotated images give `NULL`.

## Examples

``` r
library(ggplot2)
p <- ggplot(mtcars, aes(wt, mpg)) + geom_point()

file <- tempfile(fileext = ".png")
ggsave(file, add_watermark(p, "RUN-42"), width = 6, height = 4, dpi = 150)
extract_watermark(file)
#> [1] "RUN-42"
```
