# Frame layout (every field LSB-first):
#
#   sync_start (16) | header (8) | payload | check (32) | sync_end (16)
#
# The header byte says what the payload is (the frame type registry below).
# For text, the check is two CRC-16s (CCITT-FALSE and ARC) over the header
# and the payload bytes: 32 bits, so a damaged frame that happens to pass is
# about a one-in-four-billion event per reading attempt. A frame whose header
# is not in the registry is rejected outright, so a decoder never guesses at
# a format it does not know.
#
# Frame types (header byte):
#
#   0x01-0x10  text, UTF-8 bytes, 1-16 of them; payload is 8 bits per byte
#   0x81-0x90  text, Crockford base32, 1-16 characters, 5 bits each
#   0x40       UUID, first row: bytes 1-8 of the UUID (64 bits)
#   0x41       UUID, second row: bytes 9-16
#   others     reserved
#
# The text types are the original (0.1.0) format, unchanged. A UUID is drawn
# as two of these frames on two rows; their headers say which half they hold.
# A UUID row's 32 check bits are split in two:
#
#   own  (16)  CRC over the row's header and its own 8 bytes, so the row
#              scanner can recognise a row on its own;
#   pair (16)  CRC over the row's header and all 16 bytes of the UUID, so a
#              row only fits the other half of its own UUID.
#
# Row 1 uses ARC for its own check and CCITT-FALSE for the pair check; row 2
# the other way round. CRCs are linear, so two checks of one kind over the
# same UUID would fail or pass together; with one of each, a first half from
# one UUID and a second half from another (two stacked charts, say) pass
# both pair checks about once in four billion tries. A UUID is accepted only
# when all four checks agree: 64 bits in all.
#
# Decoders from before the UUID types read 0x40/0x41 as an impossible text
# length and return NULL.
#
# The first and last bits are always 1, so the outermost dots mark the frame
# edges. The alternating start sync gives the decoder its bit pitch.

sync_start <- rep(c(1L, 0L), 8)
sync_end <- rep(c(0L, 1L), 8)
max_id_bytes <- 16L
base32_alphabet <- strsplit("0123456789ABCDEFGHJKMNPQRSTVWXYZ", "")[[1]]

header_uuid <- c(0x40L, 0x41L)
uuid_row_bytes <- 8L

frame_bits <- function(payload_bits) 72L + payload_bits

# Every possible frame length, shortest first: packed text uses 5 bits per
# character, byte text 8, and a UUID row carries 64 bits.
frame_lengths <- sort(unique(frame_bits(c(
  c(5L, 8L) %o% seq_len(max_id_bytes),
  8L * uuid_row_bytes
))))

#' @noRd
crc16_ccitt <- function(bytes) {
  crc <- 0xFFFFL
  for (b in as.integer(bytes)) {
    crc <- bitwXor(crc, bitwShiftL(b, 8L))
    for (i in 1:8) {
      shifted <- bitwAnd(bitwShiftL(crc, 1L), 0xFFFFL)
      crc <- if (bitwAnd(crc, 0x8000L) != 0L) bitwXor(shifted, 0x1021L) else shifted
    }
  }
  crc
}

#' @noRd
crc16_arc <- function(bytes) {
  crc <- 0L
  for (b in as.integer(bytes)) {
    crc <- bitwXor(crc, b)
    for (i in 1:8) {
      shifted <- bitwShiftR(crc, 1L)
      crc <- if (bitwAnd(crc, 1L) != 0L) bitwXor(shifted, 0xA001L) else shifted
    }
  }
  crc
}

int_to_bits <- function(x, width) as.integer(bitwAnd(bitwShiftR(x, 0:(width - 1L)), 1L))

bits_to_int <- function(bits) sum(bits * 2L^(seq_along(bits) - 1L))

check_bits <- function(header, bytes) {
  content <- c(as.raw(header), bytes)
  c(int_to_bits(crc16_ccitt(content), 16L), int_to_bits(crc16_arc(content), 16L))
}

# The own and pair checks of each UUID row (see the frame layout above).
uuid_own_crc <- list(crc16_arc, crc16_ccitt)
uuid_pair_crc <- list(crc16_ccitt, crc16_arc)

uuid_own_check <- function(half, part) {
  uuid_own_crc[[half]](c(as.raw(header_uuid[half]), part))
}

uuid_pair_check <- function(half, uuid) {
  uuid_pair_crc[[half]](c(as.raw(header_uuid[half]), uuid))
}

# Validate an ID and say how it will be carried: as text (at most 16 UTF-8
# bytes) or as a UUID (canonical 8-4-4-4-12 hex, returned lowercase).
parse_id <- function(id, arg = "id") {
  if (!is.character(id) || length(id) != 1L || is.na(id) || !nzchar(id)) {
    stop("`", arg, "` must be a single non-empty string.", call. = FALSE)
  }
  # The dots carry UTF-8 and the decoder rejects anything else, so an ID
  # that can't be written as valid UTF-8 could never be read back.
  if (Encoding(id) == "bytes" || !validUTF8(enc2utf8(id))) {
    stop("`", arg, "` must be valid UTF-8 text.", call. = FALSE)
  }
  # Whitespace-only IDs round-trip, but they are almost always a bug (an
  # empty variable pasted in), and nobody could tell them apart when read.
  if (!grepl("[^[:space:]\u00a0\u200b-\u200d\u2060\ufeff]", enc2utf8(id), perl = TRUE)) {
    stop("`", arg, "` has no visible characters.", call. = FALSE)
  }
  uuid <- parse_uuid(id)
  if (!is.null(uuid)) {
    return(list(kind = "uuid", id = format_uuid(uuid), bytes = uuid))
  }
  bytes <- charToRaw(enc2utf8(id))
  if (length(bytes) > max_id_bytes) {
    problem <- uuid_problem(id)
    stop(
      "`", arg, "` is ", length(bytes), " bytes; the dot code holds at most ",
      max_id_bytes, " bytes of text, or a UUID written as 8-4-4-4-12 hex digits.",
      if (is.null(problem)) " Use a short ID such as `wm_id()`, or a UUID." else
        paste0(" It looks like a UUID that ", problem, "."),
      call. = FALSE
    )
  }
  list(kind = "text", id = id, bytes = bytes)
}

# The canonical form of a valid ID (invisibly), or an error.
check_id <- function(id, arg = "id") invisible(parse_id(id, arg)$id)

is_packable <- function(id) {
  chars <- strsplit(id, "")[[1]]
  all(chars %in% base32_alphabet)
}

frame <- function(header, payload, bytes) {
  c(sync_start, int_to_bits(header, 8L), payload, check_bits(header, bytes), sync_end)
}

text_frame <- function(id) {
  bytes <- charToRaw(enc2utf8(id))
  if (is_packable(id)) {
    chars <- strsplit(id, "")[[1]]
    payload <- unlist(lapply(match(chars, base32_alphabet) - 1L, int_to_bits, 5L))
    frame(128L + length(chars), payload, bytes)
  } else {
    frame(length(bytes), as.integer(rawToBits(bytes)), bytes)
  }
}

uuid_frame <- function(bytes, half) {
  part <- bytes[(half - 1L) * uuid_row_bytes + seq_len(uuid_row_bytes)]
  c(sync_start, int_to_bits(header_uuid[half], 8L), as.integer(rawToBits(part)),
    int_to_bits(uuid_own_check(half, part), 16L),
    int_to_bits(uuid_pair_check(half, bytes), 16L), sync_end)
}

#' Encode an ID as the rows of framed bits drawn by watermark_dots()
#'
#' Text IDs take one row; a UUID takes two (bytes 1-8 on the first, drawn
#' lowest, and 9-16 on the second).
#' @noRd
encode_rows <- function(id) {
  parsed <- parse_id(id)
  if (parsed$kind == "uuid") {
    list(uuid_frame(parsed$bytes, 1L), uuid_frame(parsed$bytes, 2L))
  } else {
    list(text_frame(parsed$id))
  }
}

#' Encode a text ID into a single framed bit vector
#' @noRd
encode_bits <- function(id) {
  rows <- encode_rows(id)
  if (length(rows) != 1L) {
    stop("`", id, "` needs ", length(rows), " rows; use encode_rows().", call. = FALSE)
  }
  rows[[1]]
}

#' Parse a framed bit vector
#'
#' `NULL` unless the syncs, header, length and check all agree. Otherwise a
#' list: `kind = "text"` with the `id`, or `kind = "uuid"` with `half` (1 or
#' 2), the 8 `bytes` of that half and its `pair` check, which only
#' `assemble_uuid()` can verify. For a UUID row only the own check (16 bits)
#' is verified here.
#' @noRd
parse_frame <- function(bits) {
  n <- length(bits)
  if (n < frame_bits(5L)) return(NULL)
  bits <- as.integer(bits)
  if (!identical(bits[1:16], sync_start)) return(NULL)
  if (!identical(bits[(n - 15L):n], sync_end)) return(NULL)

  header <- bits_to_int(bits[17:24])
  payload <- bits[25:(n - 48L)]
  check <- bits[(n - 47L):(n - 16L)]

  if (header %in% header_uuid) {
    if (n != frame_bits(8L * uuid_row_bytes)) return(NULL)
    half <- match(header, header_uuid)
    bytes <- packBits(payload, "raw")
    if (bits_to_int(check[1:16]) != uuid_own_check(half, bytes)) return(NULL)
    return(list(kind = "uuid", half = half, bytes = bytes,
                pair = bits_to_int(check[17:32])))
  }

  packed <- header >= 128L
  len <- header %% 128L
  if (len < 1L || len > max_id_bytes) return(NULL)
  if (frame_bits(len * if (packed) 5L else 8L) != n) return(NULL)

  if (packed) {
    codes <- vapply(seq_len(len), function(i) {
      bits_to_int(payload[(5L * i - 4L):(5L * i)])
    }, numeric(1))
    id <- paste(base32_alphabet[codes + 1L], collapse = "")
    bytes <- charToRaw(id)
  } else {
    bytes <- packBits(payload, "raw")
    if (any(bytes == as.raw(0L))) return(NULL)
    id <- rawToChar(bytes)
    Encoding(id) <- "UTF-8"
    if (!validUTF8(id)) return(NULL)
  }
  if (!identical(check, check_bits(header, bytes))) return(NULL)
  list(kind = "text", id = id)
}

#' Decode a single-row frame to its text ID; NULL for anything else
#' @noRd
decode_bits <- function(bits) {
  parsed <- parse_frame(bits)
  if (is.null(parsed) || parsed$kind != "text") return(NULL)
  parsed$id
}

# Put the two halves of a UUID back together: the canonical string, or NULL
# unless both rows' pair checks agree with the whole UUID, which is what
# stops halves of two different UUIDs being joined.
assemble_uuid <- function(first, second) {
  if (!identical(c(first$half, second$half), 1:2)) return(NULL)
  uuid <- c(first$bytes, second$bytes)
  if (first$pair != uuid_pair_check(1L, uuid)) return(NULL)
  if (second$pair != uuid_pair_check(2L, uuid)) return(NULL)
  format_uuid(uuid)
}
