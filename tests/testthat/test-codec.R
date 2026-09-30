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
  # Bytes that aren't UTF-8 could be drawn but never read back.
  latin1 <- "caf\xe9"
  expect_error(encode_bits(latin1), "valid UTF-8")
  expect_error(encode_bits(iconv("café", "UTF-8", "latin1")), NA)
  bytes <- "caf\xc3\xa9"
  Encoding(bytes) <- "bytes"
  expect_error(encode_bits(bytes), "valid UTF-8")
})

# UUID frames: two rows with their own header codes, each checked on its
# own and bound to the other by a check over the whole UUID.

uuid_example <- "f47ac10b-58cc-4372-a567-0e02b2c3d479"

test_that("a UUID becomes two 136-bit rows that reassemble exactly", {
  rows <- encode_rows(uuid_example)
  expect_length(rows, 2L)
  expect_equal(lengths(rows), c(136L, 136L))
  halves <- lapply(rows, parse_frame)
  expect_equal(vapply(halves, `[[`, "", "kind"), c("uuid", "uuid"))
  expect_equal(vapply(halves, `[[`, 1L, "half"), 1:2)
  expect_equal(assemble_uuid(halves[[1]], halves[[2]]), uuid_example)
  for (bits in rows) {
    expect_equal(bits[1], 1L)
    expect_equal(bits[length(bits)], 1L)
  }
  # Each row carries its own bytes: the two differ and neither is text.
  expect_false(identical(rows[[1]], rows[[2]]))
  expect_null(decode_bits(rows[[1]]))
  expect_null(decode_bits(rows[[2]]))
})

test_that("encode_bits() refuses a UUID, which needs two rows", {
  expect_error(encode_bits(uuid_example), "2 rows")
})

test_that("frames with header codes outside the registry are rejected", {
  # Well-formed frames (syncs and a check that agrees with the header) whose
  # header is unassigned: a decoder must not guess at them.
  make <- function(header, bytes) {
    c(sync_start, int_to_bits(header, 8L), as.integer(rawToBits(bytes)),
      check_bits(header, bytes), sync_end)
  }
  eight <- as.raw(1:8)
  expect_type(parse_frame(encode_rows(uuid_example)[[1]]), "list")  # registered
  for (header in c(0x00L, 0x11L, 0x20L, 0x42L, 0x7FL, 0x80L, 0x91L, 0xC0L, 0xFFL)) {
    expect_null(parse_frame(make(header, eight)), label = sprintf("header 0x%02X", header))
  }
  # The text code for 8 bytes and the UUID code give frames of the same
  # length; the header and check tell them apart.
  text8 <- make(0x08L, charToRaw("abcdefgh"))
  expect_equal(parse_frame(text8)$id, "abcdefgh")
  relabelled <- text8
  relabelled[17:24] <- int_to_bits(0x41L, 8L)
  expect_null(parse_frame(relabelled))
  as_text <- encode_rows(uuid_example)[[2]]
  as_text[17:24] <- int_to_bits(0x08L, 8L)
  expect_null(parse_frame(as_text))
})

# Parse both rows and join them, as the extractor does; NULL on any failure.
read_pair <- function(rows) {
  halves <- lapply(rows, parse_frame)
  if (any(vapply(halves, is.null, logical(1)))) return(NULL)
  assemble_uuid(halves[[1]], halves[[2]])
}

test_that("any single or double bit error in a UUID row is rejected", {
  rows <- encode_rows(uuid_example)
  expect_equal(read_pair(rows), uuid_example)
  for (half in 1:2) {
    bits <- rows[[half]]
    for (i in seq_along(bits)) {
      corrupted <- rows
      corrupted[[half]][i] <- 1L - bits[i]
      expect_null(read_pair(corrupted), label = paste("row", half, "flip at bit", i))
    }
    set.seed(4)
    for (trial in 1:300) {
      corrupted <- rows
      flip <- sample(seq_along(bits), 2)
      corrupted[[half]][flip] <- 1L - bits[flip]
      expect_null(read_pair(corrupted))
    }
  }
})

test_that("halves of two different UUIDs never join", {
  # Each row passes its own check, so only the pair checks can catch this:
  # stacked or copied charts put rows of different UUIDs next to each other.
  set.seed(11)
  ids <- replicate(300, format_uuid(as.raw(sample(0:255, 16, replace = TRUE))))
  rows <- lapply(ids, encode_rows)
  for (i in seq_along(ids)) {
    j <- if (i == length(ids)) 1L else i + 1L
    expect_null(read_pair(list(rows[[i]][[1]], rows[[j]][[2]])))
    expect_null(read_pair(list(rows[[j]][[1]], rows[[i]][[2]])))
    expect_equal(read_pair(rows[[i]]), ids[[i]])
  }
  # UUIDs that differ in a single bit of either half, the case a linear
  # check is weakest on.
  base <- parse_uuid(uuid_example)
  for (byte in 1:16) {
    for (bit in 0:7) {
      other <- base
      other[byte] <- xor(other[byte], as.raw(bitwShiftL(1L, bit)))
      a <- encode_rows(uuid_example)
      b <- encode_rows(format_uuid(other))
      expect_null(read_pair(list(a[[1]], b[[2]])))
      expect_null(read_pair(list(b[[1]], a[[2]])))
    }
  }
  # Halves in the wrong order, or the same half twice, are not a UUID.
  halves <- lapply(encode_rows(uuid_example), parse_frame)
  expect_null(assemble_uuid(halves[[2]], halves[[1]]))
  expect_null(assemble_uuid(halves[[1]], halves[[1]]))
})

test_that("random 136-bit frames with valid syncs never parse", {
  set.seed(43)
  hits <- vapply(1:3000, function(i) {
    random <- sample(0:1, 136, replace = TRUE)
    random[1:16] <- sync_start
    random[121:136] <- sync_end
    !is.null(parse_frame(random))
  }, logical(1))
  expect_false(any(hits))
})

test_that("a UUID row with the other half's header fails its check", {
  rows <- encode_rows(uuid_example)
  swapped <- rows[[1]]
  swapped[17:24] <- int_to_bits(0x41L, 8L)
  expect_null(parse_frame(swapped))
})
