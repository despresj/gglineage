# Changelog

## watermark 0.1.0

First release.

- [`watermark_dots()`](https://despresj.github.io/watermark/reference/watermark_dots.md)
  adds an invisible, machine-readable ID along the plot’s bottom margin
  as an ordinary `+` component. It is drawn relative to the figure, so
  scales, coordinates and facets are untouched, and it is framed with
  sync patterns and a CRC-8 so decodes are exact or rejected.
- [`extract_watermark()`](https://despresj.github.io/watermark/reference/extract_watermark.md)
  reads the ID back from PNG or JPEG files, or pixel arrays. It survives
  JPEG compression, rescaling, padding, colour changes and screenshot
  chains; see the robustness matrix in the README.
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
  generate IDs from a private random stream that neither affects nor is
  affected by [`set.seed()`](https://rdrr.io/r/base/Random.html).
