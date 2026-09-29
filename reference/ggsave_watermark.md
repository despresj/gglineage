# Save a plot with a dot watermark and embedded provenance metadata

A drop-in replacement for
[`ggplot2::ggsave()`](https://ggplot2.tidyverse.org/reference/ggsave.html)
that stamps the plot with
[`watermark_dots()`](https://despresj.github.io/watermark/reference/watermark_dots.md)
and, for PNG files, also writes provenance fields into the file's `tEXt`
metadata chunks. The dots survive screenshots and recompression; the
metadata is lossless and can carry much more (a UUID, a git commit, a
script path) but is lost when the image is screenshotted or re-encoded.
Using both gives you the rich record when the original file is shared
and the short ID when it isn't.

## Usage

``` r
ggsave_watermark(
  filename,
  plot = ggplot2::last_plot(),
  id = wm_id(),
  metadata = list(),
  dots = TRUE,
  ...
)
```

## Arguments

- filename:

  File to create, as in
  [`ggplot2::ggsave()`](https://ggplot2.tidyverse.org/reference/ggsave.html).

- plot:

  Plot to save; defaults to the last plot displayed.

- id:

  ID to embed. Defaults to a fresh
  [`wm_id()`](https://despresj.github.io/watermark/reference/wm_id.md).

- metadata:

  A named list of extra fields to store in the PNG metadata, e.g.
  `list(commit = "a1b2c3d", script = "analysis/fig2.R")`.

- dots:

  If `FALSE`, skip the dot code and only write metadata.

- ...:

  Passed to
  [`ggplot2::ggsave()`](https://ggplot2.tidyverse.org/reference/ggsave.html)
  (`width`, `height`, `dpi`, ...).

## Value

The ID, invisibly.

## See also

[`read_watermark_metadata()`](https://despresj.github.io/watermark/reference/read_watermark_metadata.md),
[`extract_watermark()`](https://despresj.github.io/watermark/reference/extract_watermark.md).

## Examples

``` r
library(ggplot2)
p <- ggplot(mtcars, aes(wt, mpg)) + geom_point()

file <- tempfile(fileext = ".png")
id <- ggsave_watermark(file, p, metadata = list(script = "fig1.R"),
                       width = 6, height = 4, dpi = 150)

extract_watermark(file)
#> [1] "ZAS7J5ZN"
read_watermark_metadata(file)
#> $id
#> [1] "ZAS7J5ZN"
#> 
#> $created
#> [1] "2026-09-29T12:06:10+0000"
#> 
#> $software
#> [1] "R 4.6.1; ggplot2 4.0.3; watermark 0.1.0"
#> 
#> $script
#> [1] "fig1.R"
#> 
```
