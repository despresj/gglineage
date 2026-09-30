#' Generate IDs for tracing plots
#'
#' `wm_id()` returns a short random ID in Crockford base32 (no `I`, `L`, `O`
#' or `U`, so it survives being read aloud or retyped). Eight characters give
#' 40 bits and fit in a single row of [watermark_dots()].
#'
#' `wm_uuid()` returns a UUID (RFC 9562) as a lowercase hyphenated string.
#' Version 4 (the default) has 122 random bits. Version 7 starts with a
#' 48-bit Unix timestamp in milliseconds, so IDs from different milliseconds
#' sort by creation time, followed by 74 random bits; IDs made within the
#' same millisecond are in random order (RFC 9562 makes stricter ordering
#' optional). Either takes two rows of dots; see [watermark_dots()] for the
#' width that needs.
#'
#' @section Randomness:
#' Random bits come from the operating system's cryptographically secure
#' generator: `/dev/urandom` on Linux, macOS and other Unix-alikes, and
#' otherwise (on Windows) `openssl::rand_bytes()`, which needs the openssl
#' package. If neither is available the functions stop with an error rather
#' than fall back to a weaker source. R's own random number generator is
#' never used, so `set.seed()` in your analysis neither repeats the IDs nor
#' is disturbed by them, and forked workers (`parallel::mclapply()`) get
#' different IDs.
#'
#' Uniqueness is probabilistic: two version 4 UUIDs collide with probability
#' about \eqn{2^{-122}}, and an 8-character `wm_id()` has only 40 bits, so
#' among a million of them a repeat is likely (about 36\%). Use UUIDs where
#' IDs from many people or machines share one record. The IDs identify plots;
#' they are not secrets, and the dot code is not authentication: anyone can
#' read it, and anyone can draw it.
#'
#' @param n Number of characters, 1 to 16.
#' @param version UUID version: `4` (random) or `7` (time-ordered).
#' @return A character string.
#' @export
#' @examples
#' wm_id()
#' wm_id(12)
#' wm_uuid()
#' wm_uuid(version = 7)
wm_id <- function(n = 8) {
  if (!is.numeric(n) || length(n) != 1L || is.na(n) || n < 1 || n > max_id_bytes) {
    stop("`n` must be a number between 1 and ", max_id_bytes, ".", call. = FALSE)
  }
  # 256 is a multiple of 32, so a byte modulo 32 is uniform.
  paste(base32_alphabet[as.integer(random_bytes(as.integer(n))) %% 32L + 1L],
        collapse = "")
}

#' @rdname wm_id
#' @export
wm_uuid <- function(version = 4) {
  if (!is.numeric(version) || length(version) != 1L || !version %in% c(4, 7)) {
    stop("`version` must be 4 or 7.", call. = FALSE)
  }
  bytes <- random_bytes(16L)
  if (version == 7) {
    # 48-bit Unix time in milliseconds, big-endian, in bytes 1-6.
    ms <- floor(as.numeric(Sys.time()) * 1000)
    stamp <- integer(6)
    for (i in 6:1) {
      stamp[i] <- ms %% 256
      ms <- ms %/% 256
    }
    bytes[1:6] <- as.raw(stamp)
  }
  # Version in the high nibble of byte 7, variant 10xx in byte 9.
  bytes[7] <- (bytes[7] & as.raw(0x0f)) | as.raw(if (version == 7) 0x70 else 0x40)
  bytes[9] <- (bytes[9] & as.raw(0x3f)) | as.raw(0x80)
  format_uuid(bytes)
}

# Random bytes from the operating system's CSPRNG; see wm_id()'s docs.
random_bytes <- function(n) {
  bytes <- os_random_bytes(n) %||% openssl_random_bytes(n)
  if (is.null(bytes)) {
    stop("No secure source of random numbers: /dev/urandom is not available. ",
         "Install the openssl package (install.packages(\"openssl\")) to ",
         "generate IDs, or supply your own.", call. = FALSE)
  }
  bytes
}

os_random_bytes <- function(n) {
  if (!file.exists("/dev/urandom")) return(NULL)
  bytes <- tryCatch({
    # raw = TRUE: it is a character device, not a regular file.
    con <- file("/dev/urandom", open = "rb", raw = TRUE)
    on.exit(close(con))
    readBin(con, "raw", n)
  }, error = function(e) NULL, warning = function(w) NULL)
  if (length(bytes) == n) bytes else NULL
}

openssl_random_bytes <- function(n) {
  if (!requireNamespace("openssl", quietly = TRUE)) return(NULL)
  bytes <- tryCatch(as.raw(openssl::rand_bytes(n)), error = function(e) NULL)
  if (length(bytes) == n) bytes else NULL
}
