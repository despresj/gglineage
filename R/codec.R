# Frame layout (every field LSB-first):
#
#   sync_start (16) | header (8) | payload | check (32) | sync_end (16)
#
# The header holds the ID's length in characters (low 7 bits) and whether the
# payload is packed (high bit). IDs made only of Crockford base32 characters,
# like those from wm_id(), are packed at 5 bits per character; anything else
# is stored as UTF-8 bytes. The check is two CRC-16s (CCITT-FALSE and ARC)
# over the header and the ID's UTF-8 bytes: 32 bits, so a damaged frame that
# happens to pass is about a one-in-four-billion event per reading attempt.
#
# The first and last bits are always 1, so the outermost dots mark the frame
# edges. The alternating start sync gives the decoder its bit pitch.

sync_start <- rep(c(1L, 0L), 8)
sync_end <- rep(c(0L, 1L), 8)
max_id_bytes <- 16L
base32_alphabet <- strsplit("0123456789ABCDEFGHJKMNPQRSTVWXYZ", "")[[1]]

frame_bits <- function(payload_bits) 72L + payload_bits

# Every possible frame length, shortest first: packed IDs use 5 bits per
# character, byte IDs 8.
frame_lengths <- sort(unique(frame_bits(c(5L, 8L) %o% seq_len(max_id_bytes))))

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

check_id <- function(id, arg = "id") {
  if (!is.character(id) || length(id) != 1L || is.na(id) || !nzchar(id)) {
    stop("`", arg, "` must be a single non-empty string.", call. = FALSE)
  }
  n <- length(charToRaw(enc2utf8(id)))
  if (n > max_id_bytes) {
    stop(
      "`", arg, "` is ", n, " bytes; the dot code holds at most ",
      max_id_bytes, ". Use a short ID such as `wm_id()`.",
      call. = FALSE
    )
  }
  invisible(id)
}

is_packable <- function(id) {
  chars <- strsplit(id, "")[[1]]
  all(chars %in% base32_alphabet)
}

#' Encode an ID into a framed bit vector
#' @noRd
encode_bits <- function(id) {
  check_id(id)
  bytes <- charToRaw(enc2utf8(id))
  packed <- is_packable(id)
  if (packed) {
    chars <- strsplit(id, "")[[1]]
    payload <- unlist(lapply(match(chars, base32_alphabet) - 1L, int_to_bits, 5L))
    header <- 128L + length(chars)
  } else {
    payload <- as.integer(rawToBits(bytes))
    header <- length(bytes)
  }
  c(sync_start, int_to_bits(header, 8L), payload, check_bits(header, bytes), sync_end)
}

#' Decode a framed bit vector; NULL unless syncs, length and check all agree
#' @noRd
decode_bits <- function(bits) {
  n <- length(bits)
  if (n < frame_bits(5L)) return(NULL)
  if (!identical(as.integer(bits[1:16]), sync_start)) return(NULL)
  if (!identical(as.integer(bits[(n - 15L):n]), sync_end)) return(NULL)

  header <- bits_to_int(bits[17:24])
  packed <- header >= 128L
  len <- header %% 128L
  if (len < 1L || len > max_id_bytes) return(NULL)
  if (frame_bits(len * if (packed) 5L else 8L) != n) return(NULL)
  payload <- bits[25:(n - 48L)]

  if (packed) {
    codes <- vapply(seq_len(len), function(i) {
      bits_to_int(payload[(5L * i - 4L):(5L * i)])
    }, numeric(1))
    id <- paste(base32_alphabet[codes + 1L], collapse = "")
    bytes <- charToRaw(id)
  } else {
    bytes <- packBits(as.integer(payload), "raw")
    if (any(bytes == as.raw(0L))) return(NULL)
    id <- rawToChar(bytes)
    Encoding(id) <- "UTF-8"
    if (!validUTF8(id)) return(NULL)
  }

  if (!identical(as.integer(bits[(n - 47L):(n - 16L)]), check_bits(header, bytes))) {
    return(NULL)
  }
  id
}
