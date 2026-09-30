# UUID text handling (RFC 9562).
#
# Canonical form: 32 hexadecimal digits in groups of 8-4-4-4-12, separated by
# hyphens. Input is accepted in either case, optionally wrapped in braces or
# prefixed with "urn:uuid:"; output is always the lowercase canonical string.
# All 128 bits are carried as they are: the version and variant fields are
# neither checked nor changed, so the nil and max UUIDs are accepted too.

uuid_pattern <- "^[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}$"

# Strip the optional "{...}" wrapper or "urn:uuid:" prefix.
uuid_body <- function(x) {
  if (grepl("^\\{.*\\}$", x)) {
    x <- substr(x, 2L, nchar(x) - 1L)
  } else if (grepl("^urn:uuid:", x, ignore.case = TRUE)) {
    x <- substring(x, 10L)
  }
  x
}

# The 16 bytes of a UUID string, or NULL if `x` is not one.
parse_uuid <- function(x) {
  if (!is.character(x) || length(x) != 1L || is.na(x)) return(NULL)
  body <- uuid_body(x)
  if (!grepl(uuid_pattern, body)) return(NULL)
  hex <- gsub("-", "", body, fixed = TRUE)
  as.raw(strtoi(substring(hex, seq(1L, 31L, 2L), seq(2L, 32L, 2L)), 16L))
}

# Canonical lowercase string for 16 bytes.
format_uuid <- function(bytes) {
  hex <- paste(sprintf("%02x", as.integer(bytes)), collapse = "")
  paste(substring(hex, c(1L, 9L, 13L, 17L, 21L), c(8L, 12L, 16L, 20L, 32L)),
        collapse = "-")
}

# Why a string that resembles a UUID was not accepted as one, for error
# messages; NULL when it does not resemble one.
uuid_problem <- function(x) {
  body <- uuid_body(x)
  trimmed <- trimws(body)
  if (!identical(trimmed, body)) {
    return(if (grepl(uuid_pattern, trimmed)) "has surrounding whitespace" else NULL)
  }
  if (grepl("^[0-9A-Fa-f]{32}$", body)) {
    return("has no hyphens; write it as 8-4-4-4-12")
  }
  if (!grepl("-", body, fixed = TRUE)) return(NULL)
  hex <- gsub("-", "", body, fixed = TRUE)
  if (nchar(hex) < 28L || nchar(hex) > 36L) return(NULL)
  if (grepl("[^0-9A-Fa-f]", hex)) {
    return("contains characters other than hexadecimal digits")
  }
  if (nchar(hex) != 32L) {
    return(sprintf("has %d hexadecimal digits instead of 32", nchar(hex)))
  }
  "has its hyphens in the wrong places (expected 8-4-4-4-12)"
}
