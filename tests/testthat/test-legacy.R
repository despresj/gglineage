# Compatibility with the original (0.1.0, commit 922c32a) dot code. The
# fixtures under fixtures/legacy were rendered by that code itself (see
# make-fixtures.R there), and the golden frames below were printed by its
# encode_bits(). Text IDs must keep encoding to exactly these bits, and the
# images must keep decoding, for as long as the text format is supported.

legacy_frames <- c(
  "K7Q2M9XD" = paste0(
    "1010101010101010000100011100111100111010100000101100101011110110",
    "000101010000100010110011100010010101010101010101"
  ),
  "RUN-42" = paste0(
    "1010101010101010011000000100101010101010011100101011010000101100",
    "01001100110100100101001011101110010100010101010101010101"
  ),
  "café" = paste0(
    "1010101010101010101000001100011010000110011001101100001110010101",
    "011011101101101111010101000011000101010101010101"
  )
)

test_that("text IDs still encode to the original frames, bit for bit", {
  for (id in names(legacy_frames)) {
    expect_identical(paste(encode_bits(id), collapse = ""), legacy_frames[[id]],
                     label = id)
    expect_length(encode_rows(id), 1L)
  }
})

test_that("the original frames still decode", {
  for (id in names(legacy_frames)) {
    bits <- as.integer(strsplit(legacy_frames[[id]], "")[[1]])
    expect_identical(decode_bits(bits), id)
    expect_identical(parse_frame(bits)$kind, "text")
  }
})

test_that("images rendered by the original code decode", {
  fixtures <- c(
    "K7Q2M9XD-400px.png" = "K7Q2M9XD",
    "RUN-42-400px.png" = "RUN-42",
    "cafe-400px.png" = "café",
    "ZZ0123456789ABCD-600px.png" = "ZZ0123456789ABCD",
    "K7Q2M9XD-500px-q60.jpg" = "K7Q2M9XD"
  )
  for (file in names(fixtures)) {
    if (grepl("jpg$", file)) skip_if_not_installed("jpeg")
    path <- test_path("fixtures", "legacy", file)
    expect_identical(extract_watermark(path), fixtures[[file]], label = file)
  }
})

test_that("legacy images survive a screenshot-style copy", {
  skip_if_not_installed("jpeg")
  # 400 px is near the small-image limit, so a mild JPEG: the README's
  # limits table is the authority on how far these go.
  img <- png::readPNG(test_path("fixtures", "legacy", "K7Q2M9XD-400px.png"))
  expect_identical(extract_watermark(tf_jpeg(tf_pad(img, 30), 80)), "K7Q2M9XD")
  img <- png::readPNG(test_path("fixtures", "legacy", "ZZ0123456789ABCD-600px.png"))
  expect_identical(extract_watermark(tf_jpeg(tf_pad(img, 30), 80)), "ZZ0123456789ABCD")
})
