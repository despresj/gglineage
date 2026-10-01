# Generate IDs for tracing plots

`wm_id()` returns a short random ID in Crockford base32 (no `I`, `L`,
`O` or `U`, so it survives being read aloud or retyped). Eight
characters give 40 bits and fit in a single row of
[`watermark_dots()`](https://despresj.github.io/watermark/reference/watermark_dots.md).

## Usage

``` r
wm_id(n = 8)

wm_uuid(version = 4)
```

## Arguments

- n:

  Number of characters, 1 to 16.

- version:

  UUID version: `4` (random) or `7` (time-ordered).

## Value

A character string.

## Details

`wm_uuid()` returns a UUID (RFC 9562) as a lowercase hyphenated string.
Version 4 (the default) has 122 random bits. Version 7 starts with a
48-bit Unix timestamp in milliseconds, so IDs from different
milliseconds sort by creation time, followed by 74 random bits; IDs made
within the same millisecond are in random order (RFC 9562 makes stricter
ordering optional). Either takes two rows of dots; see
[`watermark_dots()`](https://despresj.github.io/watermark/reference/watermark_dots.md)
for the width that needs.

## Randomness

Random bits come from the operating system's cryptographically secure
generator: `/dev/urandom` on Linux, macOS and other Unix-alikes, and
otherwise (on Windows)
[`openssl::rand_bytes()`](https://jeroen.r-universe.dev/openssl/reference/rand_bytes.html),
which needs the openssl package. If neither is available the functions
stop with an error rather than fall back to a weaker source. R's own
random number generator is never used, so
[`set.seed()`](https://rdrr.io/r/base/Random.html) in your analysis
neither repeats the IDs nor is disturbed by them, and forked workers
([`parallel::mclapply()`](https://rdrr.io/r/parallel/mclapply.html)) get
different IDs.

Uniqueness is probabilistic: two version 4 UUIDs collide with
probability about \\2^{-122}\\, and an 8-character `wm_id()` has only 40
bits, so among a million of them a repeat is likely (about 36\\ IDs from
many people or machines share one record. The IDs identify plots; they
are not secrets, and the dot code is not authentication: anyone can read
it, and anyone can draw it.

## Examples

``` r
wm_id()
#> [1] "ZCWXTN3T"
wm_id(12)
#> [1] "9PCWCQNE956Z"
wm_uuid()
#> [1] "61c67bd0-7569-4ea2-b43d-c9a5d86d5dfb"
wm_uuid(version = 7)
#> [1] "01a0f9a3-56aa-7e66-a30e-599f3af73359"
```
