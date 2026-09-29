## Test environments

* local macOS (aarch64), R 4.6.1
* GitHub Actions: macOS (release), Windows (release), Ubuntu (devel,
  release, oldrel-1)
* Tests also run locally against ggplot2 3.5.2, the oldest supported
  version.

## R CMD check results

0 errors | 0 warnings | 1 note

* This is a new release.

## Notes for reviewers

* Tests render plots to PNG in `tempdir()` and read them back. Slow
  image-transform chains are skipped on CRAN; the CRAN test run takes about
  15 seconds.
* The package does not use or modify `.Random.seed`; IDs come from a
  generator whose state is kept in the package namespace.
