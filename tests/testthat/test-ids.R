test_that("wm_id() uses Crockford base32 at the requested length", {
  for (n in c(1, 8, 16)) {
    expect_match(wm_id(n), sprintf("^[0-9A-HJKMNP-TV-Z]{%d}$", n))
  }
  expect_error(wm_id(0))
  expect_error(wm_id(17))
  expect_error(wm_id("8"))
})

test_that("IDs are unique across rapid calls", {
  ids <- replicate(2000, wm_id())
  expect_equal(anyDuplicated(ids), 0L)
})

test_that("wm_uuid() is a version 4 UUID", {
  expect_match(
    wm_uuid(),
    "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
  )
})

test_that("IDs neither consume nor depend on the session RNG", {
  set.seed(1)
  expected <- runif(3)
  set.seed(1)
  a <- wm_id()
  u <- wm_uuid()
  expect_equal(runif(3), expected)

  set.seed(1)
  b <- wm_id()
  expect_false(identical(a, b))
})

test_that("IDs leave a fresh session without a seed", {
  had <- exists(".Random.seed", globalenv())
  if (had) {
    old <- get(".Random.seed", globalenv())
    on.exit(assign(".Random.seed", old, globalenv()))
    rm(".Random.seed", envir = globalenv())
  }
  wm_id()
  expect_false(exists(".Random.seed", globalenv()))
})
