# Invisible, machine-readable dot watermark

Adds a row of faint dots along the bottom margin of the plot that
encodes `id`. The code survives screenshots, JPEG compression and
moderate rescaling, and is read back with
[`extract_watermark()`](https://despresj.github.io/watermark/reference/extract_watermark.md).

## Usage

``` r
watermark_dots(id, colour = "grey30", alpha = 0.15, size = 1.2)

add_watermark(plot, id, ...)
```

## Arguments

- id:

  The ID to embed: a string of at most 16 bytes. Shorter IDs are more
  robust;
  [`wm_id()`](https://despresj.github.io/watermark/reference/wm_id.md)
  makes 8-character ones.

- colour:

  Dot colour. Use a light colour on dark plot backgrounds.

- alpha:

  Dot opacity. Lower is less visible but less robust to heavy
  compression.

- size:

  Maximum dot diameter in mm. Dots shrink automatically when the plot is
  too narrow to fit them at this size.

- plot:

  A ggplot object.

- ...:

  Passed to `watermark_dots()`.

## Value

A list of ggplot2 components, to be added to a plot with `+`.

## Details

The dots are drawn relative to the whole figure, not the data, so the
watermark never touches your scales, coordinate system or facets. The
plot's bottom margin is widened to 14pt to make room; a complete theme
added *after* the watermark (e.g. `+ theme_minimal()`) resets that
margin, so add themes first.

The code is framed with sync patterns, a length byte and a CRC-8
checksum, so a decode either returns the exact ID or nothing.

## See also

`add_watermark()` for a pipe-friendly version,
[`ggsave_watermark()`](https://despresj.github.io/watermark/reference/ggsave_watermark.md)
to also embed file metadata.

## Examples

``` r
library(ggplot2)
p <- ggplot(mtcars, aes(wt, mpg)) +
  geom_point() +
  watermark_dots("RUN-42")

file <- tempfile(fileext = ".png")
ggsave(file, p, width = 6, height = 4, dpi = 150)
extract_watermark(file)
#> [1] "RUN-42"
```
