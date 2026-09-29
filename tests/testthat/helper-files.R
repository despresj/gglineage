withr_tempfile <- function(ext, env = parent.frame()) {
  file <- tempfile(fileext = ext)
  do.call(on.exit, list(substitute(unlink(f), list(f = file)), add = TRUE),
          envir = env)
  file
}
