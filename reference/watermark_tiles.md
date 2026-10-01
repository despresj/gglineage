# Crop-resistant tiled watermark

Tiles a faint 12 x 12 grid of dots behind the data in every panel. Each
tile carries the whole ID and a CRC-16 checksum, so a crop that keeps
enough of the panel still decodes with
[`extract_watermark()`](https://despresj.github.io/gglineage/reference/extract_watermark.md):
about two tiles across in each direction, roughly 80 mm square of open
panel at the default pitch (more on busy plots). Use it alongside, or
instead of,
[`watermark_dots()`](https://despresj.github.io/gglineage/reference/watermark_dots.md)
when images may be cropped.

## Usage

``` r
watermark_tiles(id, colour = "black", alpha = 0.04, size = 1.05, pitch = 3)
```

## Arguments

- id:

  The ID to embed: a string of at most 12 bytes.
  [`wm_id()`](https://despresj.github.io/gglineage/reference/wm_id.md)
  makes 8-character ones.

- colour:

  Dot colour. Use a light colour on dark panel backgrounds.

- alpha:

  Dot opacity.

- size:

  Dot diameter in mm; about a third of `pitch`.

- pitch:

  Spacing between lattice points in mm. A tile is 12 pitches square.

## Value

An object to add to a ggplot with `+`.

## Details

Tiles are drawn in the panels, on a lattice anchored to the page, so
facets share one continuous pattern. They need open panel between the
data: a plot whose data covers the whole panel (such as
[`geom_raster()`](https://ggplot2.tidyverse.org/reference/geom_tile.html))
leaves nothing to read. On a dark panel use `colour = "white"`. At the
default 3 mm pitch a tile is 36 mm square, so figures smaller than about
5 x 4 in hold too few tiles; use `pitch = 2, size = 0.7` for those,
saved at 150 dpi or more.

Tiles are read per panel, so small facets (under about 70 mm each) don't
decode. Each tile has a checksum but no error correction: when lines or
gridlines cover the same cells in every tile, some IDs fail where others
pass, and dark panels with light gridlines often fail. The strip from
[`watermark_dots()`](https://despresj.github.io/gglineage/reference/watermark_dots.md)
is more robust; use both when you can.

The tile checksum is 16 bits, against the strip's 32 (64 for a UUID), so
a corrupted tile reading is accepted as a wrong ID about once in 65,000
tries. Treat an ID read from tiles alone as a lead to confirm against
your records. A plot carries one ID: tiles with a different ID from the
plot's
[`watermark_dots()`](https://despresj.github.io/gglineage/reference/watermark_dots.md)
strip are an error.

## See also

[`watermark_dots()`](https://despresj.github.io/gglineage/reference/watermark_dots.md)
for the margin strip,
[`extract_watermark()`](https://despresj.github.io/gglineage/reference/extract_watermark.md)
to read either back.

## Examples

``` r
library(ggplot2)
p <- ggplot(mtcars, aes(wt, mpg)) +
  geom_point() +
  watermark_tiles("RUN-42")

file <- tempfile(fileext = ".png")
ggsave(file, p, width = 6, height = 4, dpi = 150)
extract_watermark(file)
#> [1] "RUN-42"
```
