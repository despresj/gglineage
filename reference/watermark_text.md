# Visible text watermark

Stamps a label such as "DRAFT" or "CONFIDENTIAL" over the whole figure,
as a large diagonal stamp, a repeating tile, or a small corner mark.
Like
[`watermark_dots()`](https://despresj.github.io/watermark/reference/watermark_dots.md),
it is drawn relative to the figure and never affects scales, coordinates
or facets.

## Usage

``` r
watermark_text(
  label = "DRAFT",
  position = c("center", "tile", "bottomright", "bottomleft", "topright", "topleft"),
  colour = "grey50",
  alpha = NULL,
  size = NULL,
  angle = NULL,
  fontface = "bold",
  family = ""
)
```

## Arguments

- label:

  Text to stamp.

- position:

  One of `"center"` (one large diagonal stamp sized to the figure),
  `"tile"` (a repeating diagonal pattern), or a corner: `"bottomright"`,
  `"bottomleft"`, `"topright"`, `"topleft"`.

- colour, alpha:

  Text colour and opacity.

- size:

  Font size in points. `NULL` picks a size suited to `position`; for
  `"center"` the stamp is scaled to span most of the figure.

- angle:

  Rotation in degrees. `NULL` uses the figure diagonal for `"center"`,
  30 for `"tile"` and 0 for corners.

- fontface, family:

  Font face and family.

## Value

A ggplot2 layer, to be added to a plot with `+`.

## Details

Text never enters the bottom few millimetres of the figure, which are
reserved for the dot code, so visible and invisible watermarks can be
combined freely.

## Examples

``` r
library(ggplot2)
p <- ggplot(mtcars, aes(wt, mpg)) + geom_point()

p + watermark_text("DRAFT")

p + watermark_text("INTERNAL", position = "tile")

p + watermark_text("github.com/you/analysis", position = "bottomright")
```
