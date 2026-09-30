# watermark (development version)

* `watermark_tiles()` adds a crop-resistant watermark: a faint, tiled 12 x 12
  dot grid behind the data in every panel, each tile carrying the full ID and
  a CRC-16. `extract_watermark()` reads tiles when no dot strip is found,
  including inverted (dark mode) images.

# watermark 0.1.0

First release.

* `watermark_dots()` adds an invisible, machine-readable ID along the plot's
  bottom margin as an ordinary `+` component. It is drawn relative to the
  figure, so scales, coordinates and facets are untouched, and it is framed
  with sync patterns and a CRC-8 so decodes are exact or rejected.
* `extract_watermark()` reads the ID back from PNG or JPEG files, or pixel
  arrays. It survives JPEG compression, rescaling, padding, colour changes
  and screenshot chains; see the robustness matrix in the README.
* `watermark_text()` adds visible stamps: a diagonal "DRAFT", a repeating
  tile, or a corner label. Text stays clear of the dot strip.
* `ggsave_watermark()` saves with dots and writes provenance fields into PNG
  metadata; `read_watermark_metadata()` reads them back.
* `wm_id()` and `wm_uuid()` generate IDs from a private random stream that
  neither affects nor is affected by `set.seed()`.
