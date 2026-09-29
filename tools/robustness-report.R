# Run the stress matrix from tests/testthat/helper-transforms.R against a few
# plot types and write a Markdown report. In GitHub Actions the report goes to
# the run summary; locally it prints. Exits non-zero if any promised transform
# fails or any transform decodes to a wrong ID.
#
# Usage (from the package root): Rscript tools/robustness-report.R

suppressPackageStartupMessages({
  library(ggplot2)
  library(watermark)
})
source("tests/testthat/helper-transforms.R")
set.seed(1)

id <- "K7Q2M9XD"
plots <- list(
  scatter = ggplot(mtcars, aes(wt, mpg)) + geom_point(),
  facets = ggplot(mpg, aes(class)) + geom_bar() + facet_wrap(~drv),
  legend = ggplot(mpg, aes(displ, hwy, colour = class)) + geom_point() +
    theme(legend.position = "bottom") + labs(caption = "Source: EPA")
)

images <- lapply(plots, function(p) render_plot(p + watermark_dots(id)))
transforms <- stress_transforms()

symbol <- function(got) {
  if (is.null(got)) "✖" else if (identical(got, id)) "✅" else "❌"
}

rows <- lapply(transforms, function(tf) {
  got <- lapply(images, function(img) {
    extract_watermark(suppressWarnings(tf$f(img)))
  })
  list(
    tf = tf,
    cells = vapply(got, symbol, character(1)),
    broken = tf$survives && !all(vapply(got, identical, logical(1), id)),
    wrong = any(vapply(got, function(g) !is.null(g) && !identical(g, id),
                       logical(1)))
  )
})

n_broken <- sum(vapply(rows, `[[`, logical(1), "broken"))
n_wrong <- sum(vapply(rows, `[[`, logical(1), "wrong"))
os <- paste(Sys.info()[["sysname"]], R.version$major, R.version$minor,
            sep = " / R ")

md <- c(
  sprintf("## Dot-code robustness: %s", os),
  "",
  sprintf("ggplot2 %s · graphics device: %s", packageVersion("ggplot2"),
          if (requireNamespace("ragg", quietly = TRUE)) "ragg" else "png"),
  "",
  sprintf("**%s** — %d promised transforms broken, %d wrong IDs.",
          if (n_broken + n_wrong == 0) "PASS" else "FAIL", n_broken, n_wrong),
  "",
  paste0("| Group | Transformation | Promised | ",
         paste(names(images), collapse = " | "), " |"),
  paste0("|---|---|:---:|", strrep(":---:|", length(images))),
  vapply(rows, function(r) {
    sprintf("| %s | %s | %s | %s |", r$tf$group, r$tf$name,
            if (r$tf$survives) "yes" else "—",
            paste(r$cells, collapse = " | "))
  }, character(1)),
  "",
  "✅ exact ID · ✖ not found · ❌ wrong ID"
)

summary_file <- Sys.getenv("GITHUB_STEP_SUMMARY")
if (nzchar(summary_file)) {
  cat(md, sep = "\n", file = summary_file, append = TRUE)
}
cat(md, sep = "\n")

if (n_broken + n_wrong > 0) quit(status = 1)
