# Lineage fuzz campaigns

Runs of `Rscript tools/lineage-fuzz-campaign.R 100000 5000 1500 <seed>` on
macOS 26.6.2 (aarch64), R 4.6.1, ggplot2 4.0.3, 2026-10-01. The invariant
throughout: a decode returns an ID that was drawn, or `NULL`.

## Seed 2027 (final code)

| Stage | Trials | Result |
|---|---:|---|
| Codec round trip (random text, base32 and UUID IDs) | 100000 | 100000 exact |
| Codec corruption (1-24 flipped bits per damaged row) | 100000 | 0 decoded (all to the original), rest NULL |
| Rows of two UUIDs sharing bytes, cross-joined | 100000 | all NULL |
| Repair of own damaged row against true partner | 4691 | 2477 repaired exactly, rest NULL |
| Repair of another UUID's row against a partner | 4994 | 2 accepted, each only where the row carried the partner's own 8 bytes |
| Composed, perturbed images (pool includes tiles-only charts) | 1500 | 849 decoded to a drawn ID, 651 NULL; median 0.47 s, max 11.7 s |

**Wrong IDs: 0.** 25.9 minutes.

## Seed 2026

Ran before tiles-only charts joined the image pool, and before the
foreign-repair check was stated precisely.

| Stage | Trials | Result |
|---|---:|---|
| Codec round trip | 100000 | 100000 exact |
| Codec corruption (1-24 flipped bits per damaged row) | 100000 | 0 decoded, rest NULL |
| Rows of two UUIDs sharing bytes, cross-joined | 100000 | all NULL |
| Repair of own damaged row against true partner | 4656 | 2468 repaired exactly, rest NULL |
| Repair of another UUID's row against a partner | 4994 | 1 accepted (below) |
| Composed, perturbed images | 1500 | 915 decoded to a drawn ID, 585 NULL; median 0.36 s, max 23.1 s |

The one accepted foreign row: a row of `4f77baf8-9f08-2124-23d1-bc9c2aaedb7c`
completed the partner `4f77baf8-9f08-2124-e851-88c49df21030`. The two UUIDs
share bytes 1-8, so their first rows carry the same payload and differ only
in two pair-check bits, which repair corrected. The result is the partner's
UUID with every byte read from the image; no third ID was formed. Read
cleanly (without repair) the same rows are rejected.
`tests/testthat/test-lineage-fuzz.R` pins this case and states the
invariant precisely: a foreign row may complete only the partner's own UUID,
and only when it carries that UUID's bytes exactly.

## Tile votes (separate simulation)

Folded tile votes mixing two IDs (weights 0.3-0.7, noise) were decoded with
`decode_tile_votes()`: 1 wrong ID in 20,000 mixtures with one seed, 0 in
100,000 with another. That is the CRC-16 bound (about 1 in 65,536 per
corrupted reading), now documented in `?extract_watermark`,
`?watermark_tiles` and the README. Treating weak cells as erasures or
enumerating them was tried and rejected: it cost 12-68% of damaged single-ID
decodes, and enumerating up to 14 cells made wrong IDs more frequent (26 in
20,000), not less.
