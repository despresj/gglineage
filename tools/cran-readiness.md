# gglineage 0.1.0: CRAN readiness

## Hardening pass, 2026-10-01 (branch `cran-hardening`)

Branched from local `main` at `bb48c6e` (16 commits ahead of `origin/main`,
unpushed). Nothing submitted, uploaded, pushed or emailed.

**Bugs found and fixed**

- *Silent lineage split (fixed).* A plot already carrying a strip or tiles
  could take a second, different ID through `+`, `add_watermark()` or
  `ggsave_watermark(id = ...)`. Observed: metadata and return value
  `OTHER-7`, dots decoding to `RUN-42`; tiles `TILEA` under a strip
  `SAVEB`. Now an error; `ggsave_watermark()` defaults to the plot's own ID.
- *Metadata that could not be read back as written (fixed).* Names over 69
  bytes were truncated by libpng with only a warning; repeated names and
  non-atomic values were stored ambiguously. Now refused before saving.
- *Tile checksum bound (documented, not changed).* Folded votes of two tile
  IDs produced a third ID once in 20,000 simulated mixtures. Decoder
  variants cost 12-68% of damaged decodes without a measurable gain, so
  the CRC-16 limit is documented instead. See `tools/lineage-fuzz-report.md`.

**Observed results (final tarball, SHA-256
`c606fc71ed30e2220ea8d2585e64a1385839dd797c1d9a90e17803ea3bb81903`,
694,489 bytes)**

| Where | Command | Result |
|---|---|---|
| macOS 26.6.2 aarch64, R 4.6.1, ggplot2 4.0.3 | `R CMD check --as-cran --no-manual`, CRAN mode, remote URL checks on | **1 NOTE**: new submission + 6 README URLs that 404 until the files are on GitHub `main`. Tests `[ FAIL 0 \| WARN 0 \| SKIP 97 \| PASS 4734 ]`, 60 s |
| Linux x86_64 (emulated), R-devel 2026-09-29 r90598, r-hub `ubuntu-clang` | `R CMD check --as-cran` | 3 NOTEs: new submission; and two environmental (no `curl` for URL/DOI checks, no `pandoc`, no `V8` in this container). PDF manual OK. Tests `[ FAIL 0 \| WARN 0 \| SKIP 97 \| PASS 4734 ]` |
| Linux R-devel (same container), full suite `NOT_CRAN=true`, installed tarball | `testthat::test_dir()` | 251 test blocks, 5,326 expectations, 0 failed, 7 skipped (real-world tool tests: no ffmpeg/sips/Chrome in the container) |
| macOS, full suite `NOT_CRAN=true` at `9953c4f` | `testthat::test_local()` | 19 files, 251 test blocks, 5,353 expectations, 0 failed, 0 skipped |
| macOS, ggplot2 3.5.0 (Imports minimum) | lineage, dots, save, tiles, UUID tests, `NOT_CRAN=true` | 0 failed |
| Fuzz campaign, seed 2027 | `tools/lineage-fuzz-campaign.R 100000 5000 1500 2027` | 0 wrong IDs |

**Before submitting**

- [ ] Push local `main` (16 commits) and merge `cran-hardening`, so the 6
      README URLs resolve and CI runs the new matrix; confirm it green on
      all three OSes.
- [ ] Repository name: renaming to `gglineage` changes the pkgdown URL in
      DESCRIPTION (GitHub Pages does not redirect), so either rename
      *before* submitting and update `URL`, `BugReports`, badges and README
      links, or submit as `watermark` and rename later with a DESCRIPTION
      update in the next release.
- [ ] Optional: win-builder (`devtools::check_win_devel()`; it emails the
      maintainer). The GitHub Actions Windows jobs cover the code.
- [ ] Rebuild the tarball from the final commit and submit.

## Earlier record

Prepared 2026-09-30 from actual runs of commit `322ae8a` on branch
`worktree-gglineage`. Nothing has been submitted, uploaded, pushed or emailed.
`tools/` and `cran-comments.md` are in `.Rbuildignore`, so later commits that
touch only them leave the tarball unchanged.

## Tarball

`gglineage_0.1.0.tar.gz`, 666,128 bytes, built with `R CMD build` from
`git archive 322ae8a`. SHA-256
`c6f691922bfbaede1dbdbb50241325bfcbab9ef5c80173f11e71fa20b7b2e1f3`.
A copy and all check logs are in `/Users/joe/watermark/.claude/cran-gglineage/`
(untracked). Rebuild after any change to shipped files.

## Check results (observed)

| Where | Command | Result |
|---|---|---|
| Linux, R-devel 2026-09-28 r90591 (r-hub `ubuntu-clang` container, with pandoc, curl, V8, TinyTeX, qpdf, tidy) | `R CMD check --as-cran` | **Status: 1 NOTE** ("New submission") |
| same container | full suite, `NOT_CRAN=true` | 112 tests, 3522 expectations, 0 failed, 0 skipped |
| macOS 26.6.2 aarch64, R 4.6.1 | `R CMD check --as-cran` | 1 ERROR, 1 WARNING, 3 NOTEs, all accounted for below; tests (28 s) and examples (max 0.66 s) OK |
| macOS, ggplot2 3.5.0 (Imports minimum) | full suite, `NOT_CRAN=true` | 112 tests, 3522 expectations, 0 failed |
| macOS, ggplot2 3.5.2 | full suite, `NOT_CRAN=true` | 112 tests, 3522 expectations, 0 failed |
| macOS, ggplot2 4.0.3 | full suite, `NOT_CRAN=true` (Fable, final tree) | 3522 passed, 0 failed |

### Every macOS issue, accounted for

| Item | Cause | Real blocker? |
|---|---|---|
| ERROR "PDF version of manual without index": `pdflatex is not available` | No LaTeX on this Mac | No. Environment. The manual builds on the Linux check (`checking PDF version of manual ... OK`). |
| WARNING "PDF version of manual": LaTeX errors | Same missing pdflatex | No. Environment. |
| NOTE "HTML version of manual": Tidy too old, V8 missing | macOS ships 2006 HTML Tidy | No. Environment. Linux: `checking HTML version of manual ... OK`. |
| NOTE "non-standard things in the check directory": `gglineage-manual.tex` | Left behind by the failed pdflatex run | No. Environment. |
| NOTE "CRAN incoming feasibility": 5 README URLs return 404 | They point at `github.com/despresj/watermark/blob/main/...` files that exist only on this unpushed branch | **Yes, until the branch is on GitHub main.** Confirmed 404 with curl from the host and from the container on 2026-09-30. The Linux R-devel check did not report them, but CRAN's incoming checks may. |

The five URLs: `data-raw/lineage-demo.R`, `data-raw/lineage-demo/screenshot.jpg`,
`man/figures/lineage-mobile.gif`, `man/figures/lineage-still.png`,
`tools/uuid-design.md`.

## Checklist

Done and verified:

- [x] Name: `gglineage` is not on CRAN (current or archived), Bioconductor or
      GitHub (checked 2026-09-30 by the previous session; the incoming check
      raised no name conflict).
- [x] DESCRIPTION: single maintainer with email (Joe Despres
      <joe.r.despres@gmail.com>, aut/cre/cph); title in title case; software
      names quoted ('ggplot2'); RFC cited as `<doi:10.17487/RFC9562>`; the
      description does not start with the package name.
- [x] License: `MIT + file LICENSE`, with the CRAN two-line `LICENSE` (YEAR
      2026, COPYRIGHT HOLDER Joe Despres); `LICENSE.md` is Rbuildignored.
- [x] Dependencies: Imports ggplot2 (>= 3.5.0), grid, png, scales, stats,
      utils; Depends R (>= 4.1.0). `%||%` is defined in the package, so
      R >= 4.4 is not needed. The minimum ggplot2 was tested (3.5.0).
      Suggests: jpeg, knitr, openssl, ragg, rmarkdown, testthat, each used
      conditionally.
- [x] Exclusions: tarball has no `data-raw/`, `tools/`, `.claude/`,
      `README.Rmd`, `cran-comments.md`, the still PNG or the phone GIF. The
      only large file is `man/figures/lineage.gif` (392 KB), used by
      README.md.
- [x] No writes outside `tempdir()` in examples or tests; no use of
      `.Random.seed`; examples each under 1 s; CRAN-mode tests about 30 s.
- [x] Spelling: `spelling::spell_check_package()` flagged only real words,
      now in `inst/WORDLIST` (the curly-apostrophe hits in README.md come
      from knitr and are harmless).
- [x] `cran-comments.md` written from these results.

Before submitting (Joe's actions or decisions):

- [ ] **Get this branch onto GitHub main** so the five README URLs resolve,
      then re-run `R CMD check --as-cran` (or `urlchecker::url_check()`) and
      confirm the URL NOTE is gone. Needs Joe's push authorization.
- [ ] **Decide the repository name.** DESCRIPTION `URL`/`BugReports` and the
      README point at `github.com/despresj/watermark` while the package is
      `gglineage`. Recommended: rename the repo to `despresj/gglineage` (GitHub
      redirects the old URLs), then update `URL`, `BugReports`, the badges and
      the absolute README links, re-knit and rebuild. Keeping the old name is
      allowed by CRAN, just confusing.
- [ ] **Windows.** The Windows entropy path (`openssl::rand_bytes()`) is
      covered by a mocked test on macOS only. Recommended: after pushing, let
      GitHub Actions run on Windows, and/or run
      `devtools::check_win_devel()` (uploads to win-builder and emails the
      maintainer, so it needs Joe's go-ahead).
- [ ] Rebuild the tarball from the final commit and compare with the
      SHA-256 above if nothing shipped has changed.
- [ ] Submit at <https://CRAN.R-project.org/submit.html> and confirm the
      emailed link. Not done here, by instruction.

## Submission form comment (cover text)

> This is a new submission of gglineage, a 'ggplot2' extension that stamps
> plots with a faint dot code carrying a short ID or a full UUID and reads it
> back from screenshots and recompressed copies.
>
> R CMD check --as-cran on R-devel (Linux) gives 0 errors, 0 warnings and
> 1 NOTE (new submission). Tests write only to tempdir(), and the slow image
> tests are skipped on CRAN. The package never touches .Random.seed: IDs
> use /dev/urandom or, where that is unavailable, openssl::rand_bytes()
> (Suggests).
>
> Thank you for your time.

## UUID evidence behind the README claims

- Pair integrity: 64 check bits per UUID (16 own + 16 pair on each row,
  different CRCs per row). Tests: every one-bit-different UUID and 300
  random pairs never join; transplanted rows, stacked strip charts and thin
  charts in reach return one of the real UUIDs or `NULL`. The extractor
  tests fail on the pre-fix commit `c5b1b68` with wrong UUIDs.
- Limits: `tools/uuid-measure.R 6` on `176af3b`, 2016 decodes, 0 wrong IDs
  (`tools/uuid-measure-176af3b.csv`, summary in `tools/uuid-design.md` §10).
- RFC 9562 checked against the rfc-editor text: v4/v7 version nibble and
  variant bits, and the 48-bit big-endian Unix-ms v7 timestamp. Monotonicity
  within a millisecond is optional (§6.2) and not provided; the docs say
  so. §6.9 asks for a CSPRNG, and both sources are one.
