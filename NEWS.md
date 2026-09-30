# gglineage 0.1.0

First release.

* `watermark_dots()` adds an invisible, machine-readable ID along the plot's
  bottom margin as an ordinary `+` component. It is drawn relative to the
  figure, so scales, coordinates and facets are untouched, and it is framed
  with sync patterns and a 32-bit check so decodes are exact or rejected.
  IDs from `wm_id()` are packed at 5 bits per character.
* UUIDs are carried in full. Pass a canonical UUID
  (`xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`, either case; braces or a
  `urn:uuid:` prefix are allowed) as the `id` and all 128 bits are drawn as
  two rows of dots; `extract_watermark()` returns the canonical lowercase
  form. Each row is checked on its own and against the whole UUID, so
  halves of two different UUIDs (stacked or copied charts) are never joined.
  Text IDs of up to 16 bytes are unchanged. A UUID needs about 20%
  more pixel width than an 8-character `wm_id()` to survive the same
  treatment; see the README for the measured limits. Malformed UUIDs (no
  hyphens, wrong length, bad characters) are rejected with a message saying
  what is wrong.
* `extract_watermark()` reads the ID back from PNG or JPEG files, or pixel
  arrays. It survives JPEG compression, rescaling, padding, colour changes
  and screenshot chains, including small images. See the robustness matrix
  in the README.
* `watermark_text()` adds visible stamps: a diagonal "DRAFT", a repeating
  tile, or a corner label. Text stays clear of the dot strip.
* `ggsave_watermark()` saves with dots and writes provenance fields into PNG
  metadata; `read_watermark_metadata()` reads them back.
* `wm_id()` and `wm_uuid()` draw their randomness from the operating
  system's secure generator (`/dev/urandom`, or `openssl::rand_bytes()` where
  that is missing, as on Windows), and stop with an error if neither is
  available rather than fall back to a weaker source. R's random number
  generator is never touched, so `set.seed()` neither repeats them nor is
  disturbed by them. `wm_uuid(version = 7)` makes UUIDs that sort by
  creation time to the millisecond.
