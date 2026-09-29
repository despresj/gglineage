# Generate IDs for tracing plots

`wm_id()` returns a short random ID in Crockford base32 (no `I`, `L`,
`O` or `U`, so it survives being read aloud or retyped). Eight
characters give 40 bits, which fits comfortably in a
[`watermark_dots()`](https://despresj.github.io/watermark/reference/watermark_dots.md)
code. `wm_uuid()` returns a random (version 4) UUID, which is too long
for the dot code but useful as a metadata field in
[`ggsave_watermark()`](https://despresj.github.io/watermark/reference/ggsave_watermark.md).

## Usage

``` r
wm_id(n = 8)

wm_uuid()
```

## Arguments

- n:

  Number of characters, 1 to 16.

## Value

A character string.

## Details

Both draw from a private random stream: they do not advance or depend on
the session's RNG, so [`set.seed()`](https://rdrr.io/r/base/Random.html)
in your analysis neither changes the IDs nor is changed by them. IDs are
for provenance, not security.

## Examples

``` r
wm_id()
#> [1] "67JAV6YR"
wm_id(12)
#> [1] "4EZRR82AQMXN"
wm_uuid()
#> [1] "faf583a9-4d3e-42d1-afad-4d070ef8b2ec"
```
