## R CMD check results

0 errors | 0 warnings | 1 note

* This is a new release.

## Test environments

* Linux (Ubuntu 22.04, x86_64, r-hub `ubuntu-clang` container), R-devel
  (2026-09-28 r90591): `R CMD check --as-cran`, 1 NOTE (new submission).
* macOS 26.6.2 (aarch64), R 4.6.1: `R CMD check --as-cran`; tests and
  examples pass. The PDF-manual and HTML-validation steps could not run on
  this machine (no pdflatex, an old HTML Tidy); they pass on the Linux
  R-devel check above.
* The full test suite, including the slower tests skipped on CRAN, also
  passes against ggplot2 3.5.0 (the minimum in Imports) and 3.5.2.

## Notes for reviewers

* Tests render plots to PNG files in `tempdir()` and read them back. The
  slow image-transform matrices are skipped on CRAN; the CRAN-mode test run
  takes about 30 seconds (48 s elapsed under emulation on the Linux check).
* The package never reads or writes `.Random.seed`. `wm_id()` and
  `wm_uuid()` take random bytes from `/dev/urandom`, or from
  `openssl::rand_bytes()` where that is not available (openssl is in
  Suggests), and stop with an error if neither is available.
* The README shows an animated GIF (`man/figures/lineage.gif`, 392 KB); it is
  the only large file in the tarball (666 KB in total).
