# Regenerate the legacy-format fixtures: images rendered by the dot code as
# it was at commit 922c32a (the pre-UUID frame: sync | header | text payload |
# 32-bit check | sync), so later decoders are held to reading them.
#
# Run from the package root, standalone (never from the tests):
#   Rscript tests/testthat/fixtures/legacy/make-fixtures.R
#
# The old package tree is checked out from git into a temporary directory and
# loaded with pkgload, so the fixtures come from the old code itself, not
# from a re-implementation of it.

commit <- "922c32a"
out_dir <- "tests/testthat/fixtures/legacy"
stopifnot(dir.exists(out_dir), dir.exists(".git") || nzchar(Sys.which("git")))

old <- file.path(tempfile("legacy-"), "pkg")
dir.create(old, recursive = TRUE)
status <- system2("git", c("archive", commit, "R", "DESCRIPTION", "NAMESPACE"),
                  stdout = file.path(dirname(old), "old.tar"))
stopifnot(status == 0)
untar(file.path(dirname(old), "old.tar"), exdir = old)
pkgload::load_all(old, quiet = TRUE)
message("Loaded ", pkgload::pkg_name(old), " from ", commit)

library(ggplot2)
p <- ggplot(mtcars, aes(wt, mpg)) + geom_point()

save_png <- function(id, name, ...) {
  ggsave(file.path(out_dir, name), p + watermark_dots(id), bg = "white", ...)
}
# 8-char base32 ID (112-bit packed frame), small PNG.
save_png("K7Q2M9XD", "K7Q2M9XD-400px.png", width = 4, height = 3, dpi = 100)
# Free text with a hyphen (UTF-8 byte frame, 120 bits).
save_png("RUN-42", "RUN-42-400px.png", width = 4, height = 3, dpi = 100)
# Non-ASCII text (5 UTF-8 bytes, 112-bit byte frame).
save_png("café", "cafe-400px.png", width = 4, height = 3, dpi = 100)
# 16-character base32 ID, the longest packed frame (152 bits).
save_png("ZZ0123456789ABCD", "ZZ0123456789ABCD-600px.png", width = 6, height = 3,
         dpi = 100)
# The same 8-char ID saved straight to JPEG by ggsave.
ggsave(file.path(out_dir, "K7Q2M9XD-500px-q60.jpg"), p + watermark_dots("K7Q2M9XD"),
       width = 5, height = 3.5, dpi = 100, quality = 60)

for (f in list.files(out_dir, pattern = "\\.(png|jpg)$", full.names = TRUE)) {
  message(sprintf("%-40s %6.1f KB  -> %s", basename(f), file.size(f) / 1024,
                  format(extract_watermark(f))))
}
