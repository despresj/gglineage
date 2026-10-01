# Save a plot with a dot watermark and embedded provenance metadata

A replacement for
[`ggplot2::ggsave()`](https://ggplot2.tidyverse.org/reference/ggsave.html)
that stamps the plot with
[`watermark_dots()`](https://despresj.github.io/gglineage/reference/watermark_dots.md)
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
  id = NULL,
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

  ID to embed: text of at most 16 bytes or a UUID (see
  [`watermark_dots()`](https://despresj.github.io/gglineage/reference/watermark_dots.md)).
  Defaults to the ID the plot already carries, if it has a
  [`watermark_dots()`](https://despresj.github.io/gglineage/reference/watermark_dots.md)
  or
  [`watermark_tiles()`](https://despresj.github.io/gglineage/reference/watermark_tiles.md)
  mark, and otherwise to a fresh
  [`wm_id()`](https://despresj.github.io/gglineage/reference/wm_id.md).
  A different ID from the one the plot carries is an error, so the
  file's metadata and its dots always name the same ID. This is the
  third argument, where
  [`ggplot2::ggsave()`](https://ggplot2.tidyverse.org/reference/ggsave.html)
  has `device`, so pass `device` and the other
  [`ggsave()`](https://ggplot2.tidyverse.org/reference/ggsave.html)
  arguments by name.

- metadata:

  A named list of extra fields to store in the PNG metadata, e.g.
  `list(commit = "a1b2c3d", script = "analysis/fig2.R")`. Each field is
  an atomic vector (stored as text, elements separated by spaces), each
  name is used once and is at most 69 bytes (PNG limits keywords to 79,
  including the package's prefix). The names `id`, `created`, `title`
  and `software` are reserved. Problems are reported before anything is
  saved.

- dots:

  If `FALSE`, skip the dot code and only write metadata.

- ...:

  Passed to
  [`ggplot2::ggsave()`](https://ggplot2.tidyverse.org/reference/ggsave.html)
  (`width`, `height`, `dpi`, ...).

## Value

The ID (not the file path, unlike
[`ggsave()`](https://ggplot2.tidyverse.org/reference/ggsave.html)),
invisibly: as given for text, or in lowercase form for a UUID.

## See also

[`read_watermark_metadata()`](https://despresj.github.io/gglineage/reference/read_watermark_metadata.md),
[`extract_watermark()`](https://despresj.github.io/gglineage/reference/extract_watermark.md).

## Examples

``` r
library(ggplot2)
p <- ggplot(mtcars, aes(wt, mpg)) + geom_point()

file <- tempfile(fileext = ".png")
id <- ggsave_watermark(file, p, metadata = list(script = "fig1.R"),
                       width = 6, height = 4, dpi = 150)

extract_watermark(file)
#> [1] "CPMCXFZP"
read_watermark_metadata(file)
#> $id
#> [1] "CPMCXFZP"
#> 
#> $created
#> [1] "2026-10-01T23:53:29+0000"
#> 
#> $software
#> [1] "R 4.6.1; ggplot2 4.0.3; gglineage 0.1.0"
#> 
#> $script
#> [1] "fig1.R"
#> 
```
