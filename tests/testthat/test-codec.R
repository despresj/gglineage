test_that("crc8 matches the CRC-8/SMBUS check value", {
  expect_equal(crc8(charToRaw("123456789")), 0xF4)
  expect_equal(crc8(raw()), 0L)
})

test_that("frames round-trip for IDs of every length", {
  for (n in 1:16) {
    id <- strrep("Z", n)
    bits <- encode_bits(id)
    expect_length(bits, 48 + 8 * n)
    expect_equal(decode_bits(bits), id)
  }
})

test_that("frames round-trip for mixed characters and UTF-8", {
  for (id in c("a1b2c3d4", "RUN-42", "x", "fig 2 (v3)", "café", "αβ")) {
    expect_equal(decode_bits(encode_bits(id)), id)
  }
})

test_that("frames start and end with a dot", {
  bits <- encode_bits("K7Q2M9XD")
  expect_equal(bits[1], 1L)
  expect_equal(bits[length(bits)], 1L)
})

test_that("any single flipped bit is rejected, never misread", {
  bits <- encode_bits("K7Q2M9XD")
  for (i in seq_along(bits)) {
    corrupted <- bits
    corrupted[i] <- 1L - corrupted[i]
    expect_null(decode_bits(corrupted), label = paste("flip at bit", i))
  }
})

test_that("truncated, padded and random frames are rejected", {
  bits <- encode_bits("K7Q2M9XD")
  expect_null(decode_bits(bits[-length(bits)]))
  expect_null(decode_bits(c(bits, 0L)))
  expect_null(decode_bits(integer()))
  set.seed(42)
  hits <- vapply(1:2000, function(i) {
    !is.null(decode_bits(sample(0:1, 112, replace = TRUE)))
  }, logical(1))
  expect_false(any(hits))
})

test_that("invalid IDs are rejected with a clear message", {
  expect_error(encode_bits(""), "non-empty")
  expect_error(encode_bits(NA_character_), "non-empty")
  expect_error(encode_bits(c("a", "b")), "single")
  expect_error(encode_bits(42), "single")
  expect_error(encode_bits(strrep("a", 17)), "17 bytes")
  expect_error(encode_bits(strrep("é", 9)), "18 bytes")
})
