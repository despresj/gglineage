# Frame layout (bits are LSB-first within each byte):
#
#   sync_start (16) | length (8) | payload (8 * n) | crc8 (8) | sync_end (16)
#
# The first and last bits are always 1, so the leftmost and rightmost dots mark
# the frame edges. The alternating start sync gives the decoder its bit pitch.

sync_start <- rep(c(1L, 0L), 8)
sync_end <- rep(c(0L, 1L), 8)
max_id_bytes <- 16L

frame_bits <- function(n_bytes) 48L + 8L * n_bytes

#' @noRd
crc8 <- function(bytes) {
  crc <- 0L
  for (b in as.integer(bytes)) {
    crc <- bitwXor(crc, b)
    for (i in 1:8) {
      shifted <- bitwAnd(bitwShiftL(crc, 1L), 0xFFL)
      crc <- if (bitwAnd(crc, 0x80L) != 0L) bitwXor(shifted, 0x07L) else shifted
    }
  }
  crc
}

bytes_to_bits <- function(bytes) as.integer(rawToBits(as.raw(bytes)))

bits_to_bytes <- function(bits) packBits(as.integer(bits), "raw")

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

#' Encode an ID into a framed bit vector
#' @noRd
encode_bits <- function(id) {
  check_id(id)
  payload <- c(as.raw(length(charToRaw(enc2utf8(id)))), charToRaw(enc2utf8(id)))
  c(
    sync_start,
    bytes_to_bits(payload),
    bytes_to_bits(crc8(payload)),
    sync_end
  )
}

#' Decode a framed bit vector; NULL unless syncs, length and CRC all check out
#' @noRd
decode_bits <- function(bits) {
  n <- length(bits)
  if (n < frame_bits(1L) || (n - 48L) %% 8L != 0L) return(NULL)
  if (!identical(as.integer(bits[1:16]), sync_start)) return(NULL)
  if (!identical(as.integer(bits[(n - 15L):n]), sync_end)) return(NULL)

  body <- bits_to_bytes(bits[17:(n - 24L)])
  len <- as.integer(body[1])
  if (len < 1L || len > max_id_bytes || frame_bits(len) != n) return(NULL)

  crc <- as.integer(bits_to_bytes(bits[(n - 23L):(n - 16L)]))
  if (crc8(body) != crc) return(NULL)

  out <- rawToChar(body[-1])
  Encoding(out) <- "UTF-8"
  out
}
