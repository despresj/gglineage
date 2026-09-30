# Tile payload for watermark_tiles(): a 12 x 12 cell grid, read row by row.
#
#   sync (16) | ID bytes (96) | CRC-16/CCITT-FALSE (16) | complement of sync (16)
#
# Bytes are MSB-first. Cells 17-128 are XORed with a fixed LFSR sequence so dot
# density stays near 50% whatever the ID is.

TILE_SYNC <- c(1L, 0L, 0L, 0L, 0L, 1L, 0L, 1L, 0L, 1L, 1L, 1L, 0L, 1L, 1L, 0L)
tile_id_bytes <- 12L

tile_prbs <- function(n, seed = 0xACE1L) {
  s <- seed
  out <- integer(n)
  for (i in seq_len(n)) {
    bit <- bitwAnd(bitwXor(bitwXor(s, bitwShiftR(s, 2L)), bitwXor(bitwShiftR(s, 3L), bitwShiftR(s, 5L))), 1L)
    s <- bitwOr(bitwShiftR(s, 1L), bitwShiftL(bit, 15L))
    out[i] <- bitwAnd(s, 1L)
  }
  out
}

TILE_PRBS <- tile_prbs(112L)

# crc16_ccitt() is shared with the strip codec (R/codec.R).

tile_int_bits <- function(x, n) as.integer(bitwAnd(bitwShiftR(x, (n - 1L):0L), 1L))

tile_bits_int <- function(bits) sum(bits * 2^((length(bits) - 1L):0L))

check_tile_id <- function(id) {
  check_id(id)
  n <- length(charToRaw(enc2utf8(id)))
  if (n > tile_id_bytes) {
    stop("`id` is ", n, " bytes; tiles hold at most ", tile_id_bytes,
         " bytes. Use a short ID such as `wm_id()`.", call. = FALSE)
  }
  invisible(id)
}

encode_tile <- function(id) {
  check_tile_id(id)
  bytes <- as.integer(charToRaw(enc2utf8(id)))
  bytes <- c(bytes, rep(0L, tile_id_bytes - length(bytes)))
  body <- c(unlist(lapply(bytes, tile_int_bits, n = 8L)), tile_int_bits(crc16_ccitt(bytes), 16L))
  c(TILE_SYNC, bitwXor(body, TILE_PRBS), 1L - TILE_SYNC)
}

decode_tile <- function(bits) {
  if (length(bits) != 144L) return(NULL)
  body <- bitwXor(as.integer(bits[17:128]), TILE_PRBS)
  bytes <- vapply(0:11, function(i) tile_bits_int(body[i * 8L + 1:8]), numeric(1))
  if (tile_bits_int(body[97:112]) != crc16_ccitt(bytes)) return(NULL)
  n <- max(c(0L, which(bytes != 0)))
  if (n == 0L || any(bytes[seq_len(n)] == 0)) return(NULL)
  out <- rawToChar(as.raw(bytes[seq_len(n)]))
  Encoding(out) <- "UTF-8"
  if (!validUTF8(out)) return(NULL)
  out
}
