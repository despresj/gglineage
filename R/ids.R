#' Generate IDs for tracing plots
#'
#' `wm_id()` returns a short random ID in Crockford base32 (no `I`, `L`, `O`
#' or `U`, so it survives being read aloud or retyped). Eight characters give
#' 40 bits and fit in a single row of [watermark_dots()].
#'
#' `wm_uuid()` returns a UUID (RFC 9562) as its canonical lowercase string.
#' Version 4 (the default) is 122 random bits; version 7 starts with a
#' 48-bit millisecond timestamp, so IDs sort by creation time, followed by 74
#' random bits. Either takes two rows of dots; see [watermark_dots()] for the
#' width that needs.
#'
#' @section Randomness:
#' Random bytes come from the operating system (`/dev/urandom`) where it
#' exists. Otherwise the uuid package is used if it is installed, and failing
#' that a Mersenne-Twister stream private to this package, seeded once per
#' session from the clock and process ID. None of these touch R's own random
#' number generator: `set.seed()` in your analysis neither repeats the IDs nor
#' is disturbed by them. IDs are for provenance, not security.
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

# Random bytes from the best source available; see wm_id()'s docs.
random_bytes <- function(n) {
  os_random_bytes(n) %||% uuid_package_bytes(n) %||% private_stream_bytes(n)
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

# The uuid package makes version 4 UUIDs from the platform's own generator;
# their 16 bytes (6 of them fixed by the version and variant, which the
# callers overwrite anyway) serve as random bytes.
uuid_package_bytes <- function(n) {
  if (!requireNamespace("uuid", quietly = TRUE)) return(NULL)
  bytes <- raw()
  while (length(bytes) < n) {
    one <- parse_uuid(tryCatch(uuid::UUIDgenerate(), error = function(e) NULL))
    if (is.null(one)) return(NULL)
    bytes <- c(bytes, one)
  }
  bytes[seq_len(n)]
}

# A Mersenne-Twister stream of our own: its state is kept here, swapped in
# for the draw and swapped out again, so the session's .Random.seed is left
# exactly as it was (or absent, if it was absent).
private_rng <- new.env(parent = emptyenv())

private_stream_bytes <- function(n) {
  global <- globalenv()
  had_seed <- exists(".Random.seed", envir = global, inherits = FALSE)
  saved <- if (had_seed) get(".Random.seed", envir = global, inherits = FALSE)
  on.exit({
    private_rng$seed <- get(".Random.seed", envir = global, inherits = FALSE)
    if (had_seed) {
      assign(".Random.seed", saved, envir = global)
    } else {
      rm(".Random.seed", envir = global)
    }
  })
  if (is.null(private_rng$seed)) {
    set.seed(NULL)  # from the clock and process ID
  } else {
    assign(".Random.seed", private_rng$seed, envir = global)
  }
  as.raw(sample.int(256L, n, replace = TRUE) - 1L)
}
