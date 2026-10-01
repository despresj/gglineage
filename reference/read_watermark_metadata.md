# Read provenance metadata written by ggsave_watermark()

Read provenance metadata written by ggsave_watermark()

## Usage

``` r
read_watermark_metadata(file)
```

## Arguments

- file:

  Path to a PNG file.

## Value

A named list of metadata fields (`id`, `created`, `title`, `software`,
plus anything passed via `metadata`), or an empty list if the file
carries none, e.g. because it was screenshotted or re-encoded.

## Examples

``` r
library(ggplot2)
file <- tempfile(fileext = ".png")
ggsave_watermark(file, ggplot(mtcars, aes(wt, mpg)) + geom_point(),
                 width = 4, height = 3, dpi = 100)
read_watermark_metadata(file)
#> $id
#> [1] "0J6K69VT"
#> 
#> $created
#> [1] "2026-10-01T23:53:29+0000"
#> 
#> $software
#> [1] "R 4.6.1; ggplot2 4.0.3; gglineage 0.1.0"
#> 
```
