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

Both use the package's own generator, seeded from the clock and process
ID, rather than R's random number generator:
[`set.seed()`](https://rdrr.io/r/base/Random.html) in your analysis
neither repeats the IDs nor is disturbed by them. IDs are for
provenance, not security.

## Examples

``` r
wm_id()
#> [1] "TB7F3TDH"
wm_id(12)
#> [1] "QX14M7EKZE2Q"
wm_uuid()
#> [1] "ddb1ea0c-0421-41c6-a91f-5a1b9638ef23"
```
