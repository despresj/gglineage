test_that("period_phase recovers a non-integer period and its phase", {
  t <- 0:999
  x <- as.numeric((t - 3.4) %% 7.3 < 1.5)
  pp <- period_phase(x)
  expect_equal(pp$period, 7.3, tolerance = 0.005)
  d <- (pp$phase - 4.15 + 7.3 / 2) %% 7.3 - 7.3 / 2
  expect_lt(abs(d), 1)
})

test_that("period_phase returns NULL on flat or aperiodic input", {
  expect_null(period_phase(rep(1, 500)))
  set.seed(2)
  expect_null(period_phase(stats::rnorm(500)))
})

test_that("estimate_lattice and sample_votes recover a synthetic lattice", {
  s <- synthetic_lattice()
  lat <- estimate_lattice(s$g)
  expect_equal(lat$px, 7.3, tolerance = 0.005)
  expect_equal(lat$py, 7.3, tolerance = 0.005)
  sv <- sample_votes(s$g, lat)
  k <- min(nrow(sv$votes), nrow(s$bits))
  v <- sv$votes[1:k, 1:k]
  b <- s$bits[1:k, 1:k]
  expect_gt(sv$known_frac, 0.8)
  expect_gt(mean((v[v != 0L] == 1L) == (b[v != 0L] == 1L)), 0.97)
})

test_that("estimate_lattice finds the rendered pitch", {
  skip_if_no_raster()
  skip_on_cran()
  pitch <- formals(watermark_tiles)$pitch
  g <- as_gray(render_plot(base_plot() + watermark_tiles("K7Q2M9XD"), dpi = 150))
  lat <- estimate_lattice(g)
  expect_equal(lat$px, pitch / 25.4 * 150, tolerance = 0.01)
  expect_equal(lat$py, pitch / 25.4 * 150, tolerance = 0.01)
})

test_that("rendered tile contrast is faint but measurable", {
  skip_if_no_raster()
  skip_on_cran()
  cc <- tile_contrast(render_plot(base_plot() + watermark_tiles("K7Q2M9XD"), dpi = 150))
  expect_gt(cc, 0.01)
  expect_lt(cc, 0.08)
})

test_that("period_phase stays precise when the profile has flat padding", {
  t <- 0:1049
  x <- c(rep(0, 60), 0.3 * as.numeric((t - 8.4) %% 17.717 < 6), rep(0, 60))
  expect_equal(period_phase(x, max_lag = 60)$period, 17.717, tolerance = 0.001)
})

test_that("period_phase prefers the fundamental when a harmonic dominates the autocorrelation", {
  t <- 0:1049
  x <- as.numeric((t - 3) %% 17.717 < 6) + as.numeric((t - 3) %% 35.434 < 6)
  expect_equal(period_phase(x, max_lag = 60)$period, 17.717, tolerance = 0.002)
})

test_that("estimate_lattice on an unwatermarked plot returns a lattice or NULL, never an error", {
  skip_if_no_raster()
  skip_on_cran()
  g <- as_gray(render_plot(base_plot(), dpi = 100))
  expect_no_error(lat <- estimate_lattice(g))
  if (!is.null(lat)) expect_true(lat$px >= 3 && lat$py >= 3)
})
