#' Generate IDs for tracing plots
#'
#' `wm_id()` returns a short random ID in Crockford base32 (no `I`, `L`, `O`
#' or `U`, so it survives being read aloud or retyped). Eight characters give
#' 40 bits, which fits comfortably in a [watermark_dots()] code.
#' `wm_uuid()` returns a random (version 4) UUID, which is too long for the dot
#' code but useful as a metadata field in [ggsave_watermark()].
#'
#' Both use the package's own generator, seeded from the clock and process ID,
#' rather than R's random number generator: `set.seed()` in your analysis
#' neither repeats the IDs nor is disturbed by them. IDs are for provenance,
#' not security.
#'
#' @param n Number of characters, 1 to 16.
#' @return A character string.
#' @export
#' @examples
#' wm_id()
#' wm_id(12)
#' wm_uuid()
wm_id <- function(n = 8) {
  if (!is.numeric(n) || length(n) != 1L || n < 1 || n > max_id_bytes) {
    stop("`n` must be a number between 1 and ", max_id_bytes, ".", call. = FALSE)
  }
  alphabet <- strsplit("0123456789ABCDEFGHJKMNPQRSTVWXYZ", "")[[1]]
  paste(alphabet[random_ints(n, 32L) + 1L], collapse = "")
}

#' @rdname wm_id
#' @export
wm_uuid <- function() {
  hex <- c(0:9, letters[1:6])
  x <- hex[random_ints(30, 16L) + 1L]
  variant <- c("8", "9", "a", "b")[random_ints(1, 4L) + 1L]
  sprintf(
    "%s-%s-4%s-%s%s-%s",
    paste(x[1:8], collapse = ""),
    paste(x[9:12], collapse = ""),
    paste(x[13:15], collapse = ""),
    variant,
    paste(x[16:18], collapse = ""),
    paste(x[19:30], collapse = "")
  )
}

# Two Park-Miller streams (modulus 2^31 - 1, multipliers 48271 and 16807)
# whose state lives in the package, so ID generation never reads or advances
# the session's .Random.seed. Summing the streams gives about 62 bits of state,
# enough that 40-bit IDs are not limited by the generator. Products stay below
# 2^47, so double arithmetic is exact. Each call re-mixes the clock and process
# ID into the state, so separate processes and rapid successive calls diverge.
rng <- new.env(parent = emptyenv())
rng$a <- 0
rng$b <- 0

pm_modulus <- 2147483647

random_ints <- function(n, range) {
  micros <- floor(as.numeric(Sys.time()) * 1e6)
  a <- (micros + rng$a) %% pm_modulus
  b <- (floor(micros / pm_modulus) + Sys.getpid() * 7919 + rng$b + 1) %% pm_modulus
  if (a == 0) a <- 1
  if (b == 0) b <- 1
  out <- integer(n)
  for (i in seq_len(n)) {
    a <- (48271 * a) %% pm_modulus
    b <- (16807 * b) %% pm_modulus
    out[i] <- as.integer(floor(((a + b) / pm_modulus) %% 1 * range))
  }
  rng$a <- a
  rng$b <- b
  out
}
