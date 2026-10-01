# Changelog

## gglineage 0.1.0

First release.

- [`watermark_tiles()`](https://despresj.github.io/watermark/reference/watermark_tiles.md)
  adds a crop-resistant watermark: a faint, tiled 12 x 12 dot grid
  behind the data in every panel, each tile carrying the full ID (up to
  12 bytes) and a CRC-16.
  [`extract_watermark()`](https://despresj.github.io/watermark/reference/extract_watermark.md)
  reads tiles when no dot strip is found, including inverted (dark mode)
  images.
- [`watermark_dots()`](https://despresj.github.io/watermark/reference/watermark_dots.md)
  adds an invisible, machine-readable ID along the plot’s bottom margin
  as an ordinary `+` component. It is drawn relative to the figure, so
  scales, coordinates and facets are untouched, and it is framed with
  sync patterns and a 32-bit check so decodes are exact or rejected. IDs
  from
  [`wm_id()`](https://despresj.github.io/watermark/reference/wm_id.md)
  are packed at 5 bits per character.
- UUIDs are carried in full. Pass a canonical UUID
  (`xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`, either case; braces or a
  `urn:uuid:` prefix are allowed) as the `id` and all 128 bits are drawn
  as two rows of dots;
  [`extract_watermark()`](https://despresj.github.io/watermark/reference/extract_watermark.md)
  returns the canonical lowercase form. Each row is checked on its own
  and against the whole UUID, so halves of two different UUIDs (stacked
  or copied charts) are never joined. Text IDs of up to 16 bytes are
  unchanged. A UUID needs about 20% more pixel width than an 8-character
  [`wm_id()`](https://despresj.github.io/watermark/reference/wm_id.md)
  to survive the same treatment; see the README for the measured limits.
  Malformed UUIDs (no hyphens, wrong length, bad characters) are
  rejected with a message saying what is wrong.
- [`extract_watermark()`](https://despresj.github.io/watermark/reference/extract_watermark.md)
  reads the ID back from PNG or JPEG files, or pixel arrays. It survives
  JPEG compression, rescaling, padding, colour changes and screenshot
  chains, including small images. See the robustness matrix in the
  README.
- [`watermark_text()`](https://despresj.github.io/watermark/reference/watermark_text.md)
  adds visible stamps: a diagonal “DRAFT”, a repeating tile, or a corner
  label. Text stays clear of the dot strip.
- [`ggsave_watermark()`](https://despresj.github.io/watermark/reference/ggsave_watermark.md)
  saves with dots and writes provenance fields into PNG metadata;
  [`read_watermark_metadata()`](https://despresj.github.io/watermark/reference/read_watermark_metadata.md)
  reads them back.
- [`wm_id()`](https://despresj.github.io/watermark/reference/wm_id.md)
  and
  [`wm_uuid()`](https://despresj.github.io/watermark/reference/wm_id.md)
  draw their randomness from the operating system’s secure generator
  (`/dev/urandom`, or
  [`openssl::rand_bytes()`](https://jeroen.r-universe.dev/openssl/reference/rand_bytes.html)
  where that is missing, as on Windows), and stop with an error if
  neither is available rather than fall back to a weaker source. R’s
  random number generator is never touched, so
  [`set.seed()`](https://rdrr.io/r/base/Random.html) neither repeats
  them nor is disturbed by them. `wm_uuid(version = 7)` makes UUIDs that
  sort by creation time to the millisecond.
