test_that("box_mean matches a direct window mean with replicated edges", {
  set.seed(1)
  g <- matrix(runif(12 * 9), 12)
  pad <- g[c(1, 1, 1:12, 12, 12), c(1, 1, 1:9, 9, 9)]
  direct <- outer(1:12, 1:9, Vectorize(function(i, j) mean(pad[i:(i + 4), j:(j + 4)])))
  expect_equal(box_mean(g, 2L), direct)
})

test_that("box_mean handles one-row and one-column matrices", {
  expect_equal(box_mean(matrix(1:5, 1), 1L), matrix(c(4 / 3, 2, 3, 4, 14 / 3), 1))
  expect_equal(box_mean(matrix(1:5, 5), 1L), matrix(c(4 / 3, 2, 3, 4, 14 / 3), 5))
})

test_that("local_stats gives a positive residual on a faint dot and near-zero sd on flat ground", {
  g <- matrix(0.92, 41, 41)
  g[20:22, 20:22] <- 0.88
  s <- local_stats(g, 6L)
  expect_gt(s$res[21, 21], 0.03)
  expect_lt(s$sd[5, 5], 1e-6)
})

test_that("block_downsample averages whole blocks and drops the remainder", {
  g <- matrix(1:20, 4, 5)
  expect_equal(block_downsample(g, 2L), matrix(c(3.5, 5.5, 11.5, 13.5), 2, 2))
  expect_identical(block_downsample(g, 1L), g)
})
