test_that("CRCs match the standard check values", {
  check <- charToRaw("123456789")
  expect_equal(crc16_ccitt(check), 0x29B1)
  expect_equal(crc16_arc(check), 0xBB3D)
})

test_that("base32 IDs are packed at 5 bits per character", {
  for (n in 1:16) {
    id <- wm_id(n)
    bits <- encode_bits(id)
    expect_length(bits, 72 + 5 * n)
    expect_equal(decode_bits(bits), id)
  }
})

test_that("other IDs are stored as UTF-8 bytes", {
  for (n in 1:16) {
    id <- strrep("z", n)
    bits <- encode_bits(id)
    expect_length(bits, 72 + 8 * n)
    expect_equal(decode_bits(bits), id)
  }
})

test_that("frames round-trip for mixed characters and UTF-8", {
  for (id in c("a1b2c3d4", "RUN-42", "x", "fig 2 (v3)", "café", "αβ",
               "K7Q2M9XD", "0", "ZZZZZZZZZZZZZZZZ")) {
    expect_equal(decode_bits(encode_bits(id)), id)
  }
})

test_that("frames start and end with a dot", {
  for (id in c("K7Q2M9XD", "RUN-42")) {
    bits <- encode_bits(id)
    expect_equal(bits[1], 1L)
    expect_equal(bits[length(bits)], 1L)
  }
})

test_that("any single or double bit error is rejected, never misread", {
  for (id in c("K7Q2M9XD", "RUN-42")) {
    bits <- encode_bits(id)
    for (i in seq_along(bits)) {
      corrupted <- bits
      corrupted[i] <- 1L - corrupted[i]
      expect_null(decode_bits(corrupted), label = paste(id, "flip at bit", i))
    }
    set.seed(3)
    for (trial in 1:300) {
      corrupted <- bits
      flip <- sample(seq_along(bits), 2)
      corrupted[flip] <- 1L - corrupted[flip]
      expect_null(decode_bits(corrupted))
    }
  }
})

test_that("truncated, padded and random frames are rejected", {
  bits <- encode_bits("K7Q2M9XD")
  expect_null(decode_bits(bits[-length(bits)]))
  expect_null(decode_bits(c(bits, 0L)))
  expect_null(decode_bits(integer()))
  set.seed(42)
  for (n in c(112, 120)) {
    hits <- vapply(1:2000, function(i) {
      random <- sample(0:1, n, replace = TRUE)
      random[1:16] <- sync_start
      random[(n - 15):n] <- sync_end
      !is.null(decode_bits(random))
    }, logical(1))
    expect_false(any(hits))
  }
})

test_that("frames whose payload holds NUL or invalid UTF-8 are rejected", {
  frame <- function(bytes) {
    header <- length(bytes)
    c(sync_start, int_to_bits(header, 8L), as.integer(rawToBits(bytes)),
      check_bits(header, bytes), sync_end)
  }
  expect_null(decode_bits(frame(as.raw(c(0x41, 0x00, 0x42)))))
  expect_null(decode_bits(frame(as.raw(c(0xff, 0xfe)))))
  expect_equal(decode_bits(frame(charToRaw("ok"))), "ok")
})

test_that("invalid IDs are rejected with a clear message", {
  expect_error(encode_bits(""), "non-empty")
  expect_error(encode_bits(NA_character_), "non-empty")
  expect_error(encode_bits(c("a", "b")), "single")
  expect_error(encode_bits(42), "single")
  expect_error(encode_bits(strrep("a", 17)), "17 bytes")
  expect_error(encode_bits(strrep("é", 9)), "18 bytes")
})
