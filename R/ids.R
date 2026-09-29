#' Generate IDs for tracing plots
#'
#' `wm_id()` returns a short random ID in Crockford base32 (no `I`, `L`, `O`
#' or `U`, so it survives being read aloud or retyped). Eight characters give
#' 40 bits, which fits comfortably in a [watermark_dots()] code.
#' `wm_uuid()` returns a random (version 4) UUID, which is too long for the dot
#' code but useful as a metadata field in [ggsave_watermark()].
#'
#' Both draw from a private random stream: they do not advance or depend on
#' the session's RNG, so `set.seed()` in your analysis neither changes the IDs
#' nor is changed by them. IDs are for provenance, not security.
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
  paste(with_private_rng(sample(alphabet, n, replace = TRUE)), collapse = "")
}

#' @rdname wm_id
#' @export
wm_uuid <- function() {
  hex <- c(0:9, letters[1:6])
  x <- with_private_rng(c(
    sample(hex, 30, replace = TRUE),
    sample(c("8", "9", "a", "b"), 1)
  ))
  sprintf(
    "%s-%s-4%s-%s%s-%s",
    paste(x[1:8], collapse = ""),
    paste(x[9:12], collapse = ""),
    paste(x[13:15], collapse = ""),
    x[31],
    paste(x[16:18], collapse = ""),
    paste(x[19:30], collapse = "")
  )
}

rng_state <- new.env(parent = emptyenv())
rng_state$counter <- 0

with_private_rng <- function(expr) {
  env <- globalenv()
  had_seed <- exists(".Random.seed", envir = env, inherits = FALSE)
  if (had_seed) old <- get(".Random.seed", envir = env, inherits = FALSE)
  on.exit(
    if (had_seed) {
      assign(".Random.seed", old, envir = env)
    } else if (exists(".Random.seed", envir = env, inherits = FALSE)) {
      rm(".Random.seed", envir = env)
    }
  )
  rng_state$counter <- rng_state$counter + 1
  micros <- as.numeric(Sys.time()) * 1e6
  seed <- (micros + Sys.getpid() * 7919 + rng_state$counter * 104729) %%
    .Machine$integer.max
  set.seed(seed, kind = "Mersenne-Twister", normal.kind = "Inversion",
           sample.kind = "Rejection")
  expr
}
