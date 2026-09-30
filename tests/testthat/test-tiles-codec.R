test_that("crc16 matches the CCITT-FALSE check value", {
  expect_equal(crc16_ccitt(charToRaw("123456789")), 0x29B1L)
})

test_that("encode_tile lays out sync, body, and complement", {
  bits <- encode_tile("K7Q2M9XD")
  expect_length(bits, 144L)
  expect_true(all(bits %in% c(0L, 1L)))
  expect_equal(bits[1:16], TILE_SYNC)
  expect_equal(bits[129:144], 1L - TILE_SYNC)
})

test_that("tile payload round-trips spaces, punctuation, UTF-8, and every length", {
  for (id in c("A", "ab", "  A B  ", "trailing  ", "~!@#$%^&*()_", "JD-2026-0928", "h\u00e9llo")) {
    expect_identical(decode_tile(encode_tile(id)), id, info = id)
  }
})

test_that("scrambling keeps dot density near half for degenerate IDs", {
  for (id in c("A", "000000000000", "zzzzzzzzzzzz")) {
    d <- mean(encode_tile(id))
    expect_gt(d, 0.3)
    expect_lt(d, 0.7)
  }
})

test_that("a single flipped data or CRC bit fails the check", {
  bits <- encode_tile("K7Q2M9XD")
  for (i in c(17L, 60L, 112L, 120L)) {
    b <- bits
    b[i] <- 1L - b[i]
    expect_null(decode_tile(b), info = i)
  }
})

test_that("tile IDs are at most 12 bytes, on top of check_id()", {
  expect_error(check_tile_id("thirteen-char"), "tiles hold at most 12 bytes")
  expect_error(check_tile_id(""), "non-empty")
  expect_error(check_tile_id(strrep("a", 20)), "bytes")
  expect_error(check_tile_id("h\u00e9llo-world!"), "tiles hold at most 12 bytes")
})
