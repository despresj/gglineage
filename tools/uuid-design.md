# Carrying a UUID in the dot code

Design notes for adding full 128-bit UUIDs to `watermark_dots()` /
`extract_watermark()`. `tools/` is in `.Rbuildignore`, so none of this ships.

Everything marked **observed** was measured on this machine (macOS arm64,
R 4.6.1, ggplot2 4.0.3, ragg) with the scripts in this directory. Everything
else is inference.

## 1. Requirements

- All 128 bits of a caller-supplied UUID, recovered from pixels alone: no
  truncation, no hashing to a short code, no reliance on PNG metadata.
- Canonical hyphenated input in either case; lowercase output. (RFC 9562
  section 4 allows upper, lower or mixed case; lowercase output is the
  convention of the obsoleted RFC 4122 section 3 and of ITU-T X.667. An
  earlier draft of this note misquoted RFC 9562 on this.)
- Versioned framing with error detection; existing text IDs keep encoding
  and decoding bit-for-bit; images already made keep decoding.
- Never a wrong ID. The 32-bit check stays (CRC-8 produced real wrong IDs
  once the decoder retried more; see commit 922c32a).
- Measured, documented limits; no promises the tests don't hold.

## 2. Starting point (commit 922c32a, unchanged since)

```
sync_start(16) | header(8) | payload | check(32) | sync_end(16)
```

Header: bit 7 = packed, bits 0-6 = length 1..16. Packed IDs (Crockford
base32) use 5 bits/char, other text 8 bits/byte. `wm_id()` (8 chars) is a
112-bit frame. Dots sit at fractions 0.04..0.96 of the figure width, so pitch
= 0.92 W / (n - 1) px, and the dot radius is min(0.6 mm, 0.4 pitch).

At 7 x 5 in, 150 dpi (W = 1050 px):

| frame | bits | pitch px | dot diameter px |
|---|---:|---:|---:|
| `wm_id(8)` | 112 | 8.70 | 6.96 |
| UUID row (this design) | 136 | 7.16 | 5.72 |
| UUID as one row | 200 | 4.85 | 3.88 |

Above ~1.2 mm the dot diameter is capped by `size`; below it the dot is 0.8
of a pitch wide, so what matters for survival is pitch in pixels, i.e. the
image's pixel width divided by the frame length.

## 3. Options considered

### A. One row, 128 raw bits (200-bit frame)

Simplest: a new header code, `frame_lengths` already contains 200 (the
16-byte text frame). No new drawing or decoding geometry.

**Observed (`tools/uuid-measure.R` with `GGLINEAGE_UUID_PROXY=1`, which
uses a 16-byte text ID: same 200-bit frame, same dots).** Pass counts over
3 IDs x 2 plots:

| transform | 1050 | 900 | 800 | 700 | 640 | 600 | 552 | 520 | 480 | 430 | 400 | 360 | 320 | 280 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| resize | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 4/6 | 6/6 | 0/6 | 2/6 | 0/6 | 0/6 | 0/6 |
| jpeg75 | 6/6 | 4/6 | 4/6 | 4/6 | 0/6 | 0/6 | 0/6 | 0/6 | 0/6 | 0/6 | 0/6 | 0/6 | 0/6 | 0/6 |
| jpeg50 | 4/6 | 4/6 | 0/6 | 0/6 | 0/6 | 0/6 | 0/6 | 0/6 | 0/6 | 0/6 | 0/6 | 0/6 | 0/6 | 0/6 |
| jpeg35 | 2/6 | 2/6 | 0/6 | 0/6 | 0/6 | 0/6 | 0/6 | 0/6 | 0/6 | 0/6 | 0/6 | 0/6 | 0/6 | 0/6 |
| pad+jpeg50 | 6/6 | 4/6 | 0/6 | 0/6 | 0/6 | 0/6 | 0/6 | 0/6 | 0/6 | 0/6 | 0/6 | 0/6 | 0/6 | 0/6 |
| screenshot chain | 6/6 | 6/6 | 6/6 | 4/6 | 4/6 | 0/6 | 2/6 | 0/6 | 0/6 | 0/6 | 0/6 | 0/6 | 0/6 | 0/6 |

For comparison the 8-character `wm_id()` frame in the same run:

| transform | 1050 | 900 | 800 | 700 | 640 | 600 | 552 | 520 | 480 | 430 | 400 | 360 | 320 | 280 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| resize | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 |
| jpeg75 | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 4/6 | 2/6 |
| jpeg50 | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 4/6 | 1/6 | 2/6 | 1/6 | 0/6 |
| jpeg35 | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 5/6 | 6/6 | 4/6 | 6/6 | 0/6 | 2/6 | 0/6 | 0/6 |
| pad+jpeg50 | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 4/6 | 2/6 | 0/6 | 0/6 | 0/6 |
| screenshot chain | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 | 6/6 |

(0 wrong IDs in 1008 decodes; 427 s.)

A single 200-bit row does not survive JPEG quality 50 even at the full 1050
px, and quality 75 fails below 900 px. It is only usable for lossless copies.
**Rejected.**

### B. Forward error correction on a single row

The natural question: keep one row but add a BCH/RS code. To decide, the
number of wrong bits at the true geometry was measured for frames just past
their limit (`tools/uuid-bit-errors.R`: the decoder's own sampler at the
known dot row +-3 rows, all edge nudges, best case).

**Observed**, minimum wrong bits per image (3 IDs), `ok` = decoded:

| frame / transform | 800 | 700 | 640 | 600 | 552 | 520 | 480 | 430 | 400 | 360 | 320 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 112 / jpeg50 | ok | ok | ok | ok | ok | ok | ok | ok ok 4 | ok ok 2 | ok 2 6 | ok 6 7 |
| 112 / jpeg35 | ok | ok | ok | ok ok 1 | ok | ok | 1 2 ok | ok ok 2 | 1 2 5 | 1 4 6 | 1 8 9 |
| 200 / resize | ok | ok | ok | ok | ok | ok | ok ok 1 | 3 7 20 | 1 3 6 | 10 24 23 | 1 5 13 |
| 200 / jpeg50 | 3 11 13 | 13 16 19 | 7 25 19 | 14 20 26 | 15 22 26 | 14 26 19 | 18 18 20 | 23 19 28 | 25 27 42 | 49 53 60 | 44 49 63 |
| 200 / jpeg35 | 10 23 23 | 11 20 20 | 11 24 19 | 9 21 16 | 13 15 18 | 15 16 27 | 27 32 43 | - - 121 | 54 61 67 | - - 104 | 57 66 79 |

Two things follow.

1. Errors grow quickly with dot density. For the 112-bit frame the first
   failures have 1-4 wrong bits, but 30% less width later they have 6-9. A
   t-error-correcting code costs about m*t parity bits (32 bits for t = 4
   with an 8-bit field), which on a 200-bit frame is 16% more dots, i.e. the
   same error profile 16% narrower. From the table, the 200-bit frame at
   0.86x the width has 13-26 errors at quality 50, well past t = 4. FEC
   does not buy back what its parity bits cost here. **Rejected.**

2. Where the wrong bits are: inside dense runs of 1s, mostly 1 read as 0
   (contexts like `0011[1]10`, `1001[1]11`, and a 7-error cluster inside
   `1111101 1111011 …`). That is the running-median background estimate
   drifting up to the dot level inside a dense run: once more than half the
   pixels in the window (about 12 bits wide) are dot, the median *is* the
   dot level, and the dots read as background. A UUID row has 64 random
   payload bits, so this happens to some UUIDs at every width; in the first
   two-row sweep the failures were identical on both plot types and
   concentrated on one of the three UUIDs (17 of its 24 large-width JPEG
   cases), i.e. ID-dependent, not layout-dependent.

   Fix (adopted, §5): bits are now read against a background on the dots'
   far side, the running maximum of the row for dark dots or the running
   minimum for light ones, which cannot drift into a run of dots as long as
   a dozen-bit window still contains a gap. That holds for random payloads
   but not for long runs of 1 bits (review, 2026-09-30: the max UUID and
   `ZZZZZZZZZZZZZZZZ` fail, to NULL, at 525 px padded + JPEG 50 where a
   random v4 passes), so limits are ID-dependent. The median stays as the locator
   for the run detection and the polarity decision.

   **Observed** A/B (`tools/uuid-ab.R`: same 3 UUIDs and 3 `wm_id(8)` as
   the recorded sweep, scatter plot, widths 1050..360, before>after out
   of 3):

   | frame / transform | 1050 | 900 | 800 | 700 | 640 | 600 | 552 | 520 | 480 | 430 | 400 | 360 |
   |---|---|---|---|---|---|---|---|---|---|---|---|---|
   | wm_id(8) / jpeg50 | 3>3 | 3>3 | 3>3 | 3>3 | 3>3 | 3>3 | 3>3 | 3>3 | 2>3 | 0>3 | 0>3 | 0>3 |
   | wm_id(8) / jpeg35 | 3>3 | 3>3 | 2>3 | 1>3 | 3>3 | 3>3 | 2>3 | 3>3 | 1>3 | 0>3 | 0>3 | 0>3 |
   | wm_id(8) / pad+jpeg50 | 3>3 | 3>3 | 3>3 | 3>3 | 3>3 | 3>3 | 3>3 | 3>3 | 3>3 | 0>3 | 0>3 | 0>0 |
   | UUID / jpeg75 | 3>3 | 1>3 | 2>3 | 2>3 | 2>3 | 3>3 | 3>3 | 2>3 | 0>3 | 0>3 | 0>3 | 0>3 |
   | UUID / jpeg50 | 2>3 | 2>3 | 2>3 | 3>3 | 2>3 | 2>3 | 0>3 | 0>3 | 0>3 | 0>3 | 0>3 | 0>3 |
   | UUID / jpeg35 | 0>3 | 2>3 | 1>3 | 1>3 | 0>3 | 1>3 | 0>3 | 0>3 | 0>3 | 0>0 | 0>3 | 0>0 |
   | UUID / pad+jpeg50 | 2>3 | 2>3 | 2>3 | 3>3 | 2>3 | 2>3 | 0>3 | 0>3 | 0>3 | 0>2 | 0>3 | 0>3 |

   All 432 cells: 291 exact before, 422 after, 0 wrong. The resize and
   screenshot-chain rows (not shown) went 3>3 throughout. So the "FEC"
   this decoder needed was a better background estimate, at no cost in
   dots; the limits in §7 are measured with it.

The practical alternative to FEC in this decoder is the one it already
uses: many candidate rows (every pixel row through a dot, plus 3-row
averages) and a 32-bit check that makes retries safe.

### C. Two rows (chosen)

Draw the UUID as two independent 136-bit frames, one above the other:

```
row 1 (2.4 mm up):  sync | 0x40 | UUID bytes 1-8  | CRC32 | sync
row 2 (4.6 mm up):  sync | 0x41 | UUID bytes 9-16 | CRC32 | sync
```

Each row is a complete frame of the existing kind, so every part of the
existing decoder (row scan, 3-row averaging, figure-geometry fallback,
sub-pixel sampling, edge nudges) finds and checks it unchanged. Only the
header codes are new. The header says which half a row holds, so row order
never matters to the decoder. When a half is found, the other is read at the
same horizontal geometry in the rows just above and below (§5).

Cost: 272 dots instead of 200 (36% more), a taller reserved band, and a
2 x 32-bit check instead of one. Gain: pitch 7.16 px instead of 4.85 at
1050 px, 1.48x. Since survival is set by pitch, the UUID's limits should sit
at about 135/111 = 1.22x the width of the 8-character frame's, versus
199/111 = 1.79x for one row. Measured in §7.

Variants considered and not taken:

- *Three rows of ~115 bits* (pitch 8.47 px): only 18% better than two, for
  a third row to find, a 3 mm taller band and three dotted lines under every
  plot.
- *Second row without its own sync/header* (row 1: 44 payload bits, row 2:
  84 + check; both 116 bits): pitch equal to the 8-char frame's, but row 2
  could only be found through row 1, has no known bits to set its threshold,
  and the geometry pass could not gate it. Too clever for the gain.
- *Binding the halves* (each row's CRC over all 16 bytes, or a pair tag):
  would catch a row spliced in from a different image. But a spliced text
  row already yields that image's text ID, so this is not a protection the
  text frames have either; splicing is deliberate tampering, outside what
  the package claims (README: "provenance, not security"). Independent
  checks keep each row findable on its own. Not done; documented in §9.
- *Using more of the width* (inset 0.02 instead of 0.04): +4% pitch. The
  margin beside the frame is what the exact background estimate reads from,
  so this trades robustness for very little.
- *Base32 text of 26 characters* (130 bits): 2 bits more than raw and an
  extra alphabet mapping for nothing.

## 4. Frame format, bit level

Unchanged outer layout, every field LSB-first:

```
sync_start  16   1010101010101010
header       8   frame type (below)
payload      n   see type
check       32   CRC-16/CCITT-FALSE then CRC-16/ARC, each over
                 (header byte || payload bytes), 16 bits each, LSB-first
sync_end    16   0101010101010101
```

Frame type registry (header byte):

| header | type | payload | frame bits |
|---|---|---|---|
| `0x01`-`0x10` | text, UTF-8 bytes, 1-16 | 8 bits/byte, `rawToBits` order | 80..200 |
| `0x81`-`0x90` | text, Crockford base32, 1-16 chars | 5 bits/char, LSB-first | 77..152 |
| `0x40` | UUID, first half | bytes 1-8 of the UUID, `rawToBits` order | 136 |
| `0x41` | UUID, second half | bytes 9-16 | 136 |
| anything else | reserved | | rejected |

The UUID bytes are the 16 bytes of the canonical hex string in order
(RFC 9562 network byte order); nothing in them is interpreted, so nil, max
and any version pass through. Row 1 is drawn lowest.

`0x40`/`0x41` were chosen from the range that the 922c32a decoder rejects
as an impossible text length (17..127), so old decoders return NULL on new
images rather than a wrong ID (verified, §6). A frame of 136 bits is also a
valid length for 8-byte text (`0x08`); the header and the check tell them
apart. The header is inside the CRC, so a header bit error (including
`0x40` <-> `0x41`) is caught.

"Versioning" here is the type byte, not a separate version field: each
format is a code, unknown codes are rejected, and there is room for 200-odd
more. A version field on top would cost 8 bits per row for no present use.

## 5. Decoder changes

- `parse_frame(bits)` replaces the string-returning decoder internally and
  returns `list(kind = "text", id)` or `list(kind = "uuid", half, bytes)`.
  `decode_bits()` remains as the text-only wrapper the tests use.
- `find_watermark()`: the three existing passes find the first frame. A
  text frame is the answer. A UUID half triggers `find_partner()`: read rows
  at offsets 1..(7 * pitch + 3) px above and below, nearest first, at the
  found row's exact `left`/`right`/polarity, single row and 3-row average,
  with a sync gate on the cheap median background before the
  running-extreme one is computed (§3B). The reach comes from the row gap
  being fixed in mm while the pitch in mm
  depends on figure width: gap/pitch = 2.2 mm / (0.92 W_mm / 135) is 0.65
  for a 15-in figure and 6.5 for a 3-in one.
- Both halves must pass their own 32-bit check; a lone half is NULL. The
  result carries both rows for `debug = TRUE`.
- `extract_watermark()` returns a plain character string. A UUID is
  `format_uuid()`'s lowercase canonical form. No attribute or class: user
  code compares IDs with `==`/`identical()` and `expect_equal()`, which
  attributes would break, and the shape already says which kind it is
  (text is at most 16 bytes, so nothing but a UUID has 36 characters).

### False positives

Per `parse_frame` call on a frame of length n whose 32 sync bits already
agree, a random payload passes with probability (number of registered
headers consistent with n) / 256 * 2^-32. For n = 136 that is 3/256 *
2^-32 = 2.7e-12; for n = 112 it is 2/256 * 2^-32 (`0x88`, and `0x05`).
The decoder only reaches `parse_frame` after a row passes the peak gate,
yields 8 evenly spaced runs (or, in the geometry pass, a strong start-sync
correlation), and passes the 26-of-32 sync gate; then it tries up to 81
edge nudges. A pathological image (dotted grid lines on every row) might
reach 10^5 calls: 3e-7 per image. The partner search adds ~200 gated
calls after a half already passed a 2^-32 check, so a wrong UUID needs a
wrong half: the same order as a wrong text ID.

**Observed:** 0 wrong IDs in 1008 (proxy sweep) + the UUID sweep (§7) +
the test suite's never-wrong properties over random IDs past the limits,
random-bit frames with valid syncs (5000), plain plots, noise and blank
images.

## 6. Legacy compatibility

- Text frames are unchanged. `tests/testthat/test-legacy.R` pins the exact
  bit strings that the 922c32a `encode_bits()` printed for `K7Q2M9XD`,
  `RUN-42` and `café`, and decodes five images rendered by the 922c32a
  code itself (PNG 400-600 px, JPEG q60), made by
  `tests/testthat/fixtures/legacy/make-fixtures.R` from a `git archive` of
  that commit (78 KB total).
- New decoder on old images: all five fixtures decode (**observed**, also
  after pad + JPEG 60).
- Old decoder on new images: the 922c32a tree loaded with pkgload reads a
  new text image (`K7Q2M9XD`) and returns NULL with "No valid watermark
  found" on a new UUID image (**observed**).
- `wm_uuid()` output shape is unchanged (v4 by default). Its PNG metadata
  `id` field is now the canonical lowercase form; before, a UUID could not
  be passed as `id` at all.
- Layout: a text ID's bottom margin stays 14pt. A UUID's is 20pt, and the
  strip that `watermark_text()` keeps clear grows from 4.2 mm to 6.4 mm for
  everyone (corner labels sit 2.2 mm higher). The text layer cannot know
  how many rows the dots have, and a constant is simpler and safer than
  reconciling the two layers at `+` time. The package is unreleased, so no
  existing users' figures shift; the README hero was rendered before this
  and is owned by another session.

No format break. NEWS records the additions.

## 7. Measured limits (two-row UUID)

Sweep: `tools/uuid-measure.R 3` (3 random UUIDs from `wm_uuid()`, 3 random
`wm_id(8)`, two plots: a scatter and a faceted plot with a bottom legend;
7 x 5 in at 150 dpi, then resized to each width; JPEG via the jpeg package;
pad = 40 px of light grey; screenshot chain = 2x upscale, 80 px chrome,
shrink to width, JPEG 80). Pass counts are exact decodes out of 6.

**Observed**, with the running-extreme estimator (§3B); exact decodes of 6:

`wm_id(8)`, one 112-bit row:

| transform | 1050 | 800 | 640 | 552 | 480 | 430 | 400 | 360 | 320 | 300 | 280 | 260 | 240 | 220 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| resize | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 6 |
| jpeg75 | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 4 |
| jpeg50 | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 4 | 0 | 0 | 0 |
| jpeg35 | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 0 | 0 | 0 | 0 | 0 |
| pad+jpeg50 | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| screenshot chain | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 0 | 6 | 6 |

UUID, two 136-bit rows:

| transform | 1050 | 800 | 640 | 552 | 480 | 430 | 400 | 360 | 320 | 300 | 280 | 260 | 240 | 220 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| resize | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 6 |
| jpeg75 | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 4 | 0 | 0 | 0 |
| jpeg50 | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 0 | 0 | 0 | 0 | 0 | 0 |
| jpeg35 | 6 | 6 | 6 | 6 | 6 | 0 | 6 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| pad+jpeg50 | 6 | 6 | 6 | 6 | 6 | 4 | 6 | 6 | 0 | 0 | 0 | 0 | 0 | 0 |
| screenshot chain | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 6 | 0 | 2 | 0 |

(0 wrong IDs in 1008 decodes; 241 s.) The isolated zeros at 430 px (UUID
jpeg35) and 260 px (screenshot chain, both kinds) sit between passing
widths: at those exact resampling ratios the dot centres land badly on the
pixel grid. They are real, so the limits below are quoted from the last
width that passed *and* had no failure above it.

Limits, 7 x 5 in figure at 150 dpi resized down (the pixel width is what
matters, so read these as pitch: width x 0.92 / 111 or / 135):

| treatment | `wm_id(8)` | UUID | UUID / 8-char |
|---|---:|---:|---:|
| plain resize | <= 220 px (pitch 1.8) | <= 220 px (pitch 1.5) | - |
| JPEG 75 | 240 px | 300 px | 1.25 |
| JPEG 50 | 300 px | 360 px | 1.20 |
| JPEG 35 | 320 px | 480 px (400 also passes) | 1.5 |
| 40 px chrome + JPEG 50 | 400 px | 400 px | 1.0 |
| retina screenshot chain, JPEG 80 | 280 px | 280 px | 1.0 |

For comparison, before the estimator change the 8-character limits were
JPEG 50 at 480 px and JPEG 35 at ~520 px, and the README quoted 360/520.
The two-row UUID costs about 20% of width at JPEG 50 and nothing in the
padded-screenshot case, where the row scanner's run detection, not the
pitch, is the limit for both. 220 px was the smallest width in this sweep,
not a floor: the README's knit-time scan (one ID each, 400 px down to 100
in steps of 10, plain resize) puts the lossless floor at **120 px** for the
8-character ID and **150 px** for a UUID (**observed**), about one pixel
per bit; the figure-geometry pass has no minimum pitch.

Not measured: figures rendered natively at small pixel sizes (different
antialiasing from a downscale), other renderers than ragg, `alpha` other
than 0.15, dark themes at small sizes.

Row gap (`tools/uuid-row-gap.R 4`, 4 UUIDs, scatter plot, with the
running-extreme estimator; exact decodes of 4):

| transform / gap | 480 | 400 | 360 | 320 | 300 | 280 | 260 |
|---|---:|---:|---:|---:|---:|---:|---:|
| jpeg50, 1.6 mm | 4 | 4 | 4 | 0 | 0 | 0 | 0 |
| jpeg50, 2.2 mm | 4 | 4 | 3 | 0 | 0 | 0 | 0 |
| jpeg50, 2.8 mm | 4 | 4 | 1 | 0 | 0 | 0 | 0 |
| jpeg35, 1.6 mm | 4 | 0 | 0 | 0 | 0 | 0 | 0 |
| jpeg35, 2.2 mm | 4 | 3 | 0 | 0 | 0 | 0 | 0 |
| jpeg35, 2.8 mm | 4 | 1 | 1 | 0 | 0 | 0 | 0 |
| pad+jpeg50, 1.6 mm | 4 | 4 | 0 | 0 | 0 | 0 | 0 |
| pad+jpeg50, 2.2 mm | 4 | 4 | 2 | 0 | 0 | 0 | 0 |
| pad+jpeg50, 2.8 mm | 4 | 4 | 0 | 0 | 0 | 0 | 0 |

(0 wrong in 252.) An earlier run with the median estimator, at 640-360 px,
had ordered the gaps 2.8 >= 2.2 > 1.6 within noise. With the adopted
estimator 2.2 mm is best or tied in two transforms of three, and the
differences are within what 4 IDs can resolve. 2.2 mm is kept: it is the
smallest gap that keeps the two rows more than a dot diameter apart at
every plot width (dots are at most 1.2 mm), and it costs 2.2 mm of band.

Footprint at the standard 7 x 5 in, 150 dpi render: 2 rows x 136 positions,
pitch 7.16 px (1.21 mm), dots 5.7 px (0.97 mm) in diameter, rows 2.4 and
4.6 mm above the bottom edge (13 px apart), 20pt bottom margin.

## 8. API

- `watermark_dots(id)`, `add_watermark(plot, id)`, `ggsave_watermark(id =)`:
  `id` is text of up to 16 bytes, as before, **or** a UUID. Detection is
  automatic: a string that is a canonical UUID (`8-4-4-4-12` hex, either
  case, optionally `{...}` or `urn:uuid:`) is a UUID. No `format=` argument:
  a 36-character string cannot be a text ID (16-byte limit), so there is
  nothing for such an argument to disambiguate, and the only behavioural
  difference (lowercase output) is one a UUID user expects. The braces and
  URN forms are the two other standard spellings and cannot mean anything
  else.
- Not detected: 32 hex digits without hyphens. That could as well be an MD5
  and would come back reformatted; it is rejected with "has no hyphens;
  write it as 8-4-4-4-12". Other near-misses get a specific reason: bad
  character, digit count, hyphen placement, surrounding whitespace.
- `extract_watermark()` returns the plain lowercase canonical string.
- `wm_uuid(version = 4)` (default) or `7`. Random bytes: `/dev/urandom`
  where present (macOS, Linux, other Unix-alikes); else
  `openssl::rand_bytes()` (Suggests; the Windows path); else an error. RFC
  9562 section 6.9 says implementations SHOULD use a CSPRNG and reseed it
  across forks; both sources do. (Revised after review: an earlier version
  fell back to the uuid package and then to a private Mersenne-Twister
  stream seeded from the clock and PID, which repeated the same UUIDs in
  forked `mclapply()` workers and is not a CSPRNG.) R's `.Random.seed` is
  never read or written. Version 7 fills all 74 non-timestamp bits with
  random data (RFC 9562 section 5.7, no counter), so IDs made in the same
  millisecond are not ordered among themselves; the docs say so.
- Boundary, stated in the docs: the dots carry the ID and nothing else.
  Lineage (script, data, run) is whatever the user recorded against the ID
  when saving; a UUID resolves a manifest row, it does not contain one.

## 9. Open risks and follow-ups

- Row-gap tolerance: the partner search reaches 7 pitches; figures wider
  than ~15 in (gap under 0.65 pitch) put the rows within a dot diameter of
  each other, where the 3-row average blurs them. Not measured; figures
  that wide are rare and `size` caps the dots at 1.2 mm.
- Splicing two images' rows produces a UUID from neither (§3C).
- The running-median background loses bits inside dense runs (§3B). A
  running upper/lower quantile for bit sampling would likely move every
  frame's limit; measure before changing, since the sync gate and
  geometry pass depend on the current estimator.
- Padded screenshots below ~430 px at JPEG 50 still fail often (both
  frame kinds): the figure-geometry pass assumes the image is the figure.
  A sync-correlation search over (x0, pitch) would generalise it.
- Alpha 0.15 is the real JPEG limit: the dots are 10% contrast, below the
  quantiser step for mid frequencies at quality 50. Raising `alpha` is the
  user's knob; not measured here.

## 10. Revisions after independent review (2026-09-30)

Two reviewers attacked commit c5b1b68. What changed, and the evidence:

- **Row-pair binding (format change).** Each UUID row had its own 32-bit
  check and nothing tied the rows together. Observed: two 12 x 0.6 in strip
  charts stacked, bottom 13 px cropped, decoded to a wrong UUID made of
  halves of both (6 of 6). Each row's 32 check bits are now 16 own + 16
  pair (see `R/codec.R`): row 1 = ARC(own) + CCITT-FALSE(all 16 bytes),
  row 2 = CCITT-FALSE(own) + ARC(all 16 bytes). Different CRCs on the two
  pair checks matter: CRCs are linear, so the same CRC over the same UUID
  on both rows would pass or fail together, leaving 16 bits of binding.
  The extractor also requires row 1 below row 2, looks for the partner
  only in that direction, and keeps scanning past a half whose partner
  does not verify. Tests: `test-codec.R` ("halves of two different UUIDs
  never join", including every single-bit-different UUID) and
  `test-uuid.R` (transplanted rows, stacked strips, thin charts within
  reach). The new extractor tests fail on c5b1b68 with wrong UUIDs and
  pass now. UUID images made with c4b16a9-c5b1b68 (never released) no
  longer decode.
- **Randomness.** The uuid-package and private Mersenne-Twister fallbacks
  are gone (the MT stream gave identical UUIDs in forked workers).
  `/dev/urandom`, else `openssl::rand_bytes()`, else an error.
- **Partner reach.** 7 pitches missed the partner on figures narrower than
  about 1.8 in at high dpi (the 2.2 mm gap is 323 / width-in-mm pitches);
  now 16 pitches, enough above 20 mm.
- **Decoder speed on images without a code.** Observed on a 1050 x 750
  PNG with dotted grid lines: 80-90 s. The 81 edge nudges are now read in
  one vectorised pass over the sync and header bits, and a whole frame is
  read only where those are exact: 8.6 s. Uniform RGB noise: 15 s ->
  13.6 s (bound by the number of candidate geometries, not addressed).
  Images with a code, and plain plots without one, take 0.1-1 s.

