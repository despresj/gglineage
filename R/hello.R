# Hello, world!
#
# This is an example function named 'hello'
# which prints 'Hello, world!'.
#
# You can learn more about package authoring with RStudio at:
#
#   https://r-pkgs.org
#
# Some useful keyboard shortcuts for package authoring:
#
#   Install Package:           'Cmd + Shift + B'
#   Check Package:             'Cmd + Shift + E'
#   Test Package:              'Cmd + Shift + T'

library(ggplot2)
hello <- function() {
  ggplot(mtcars, aes(wt, mpg)) +
    geom_point() +
    annotation_custom(
      grid::textGrob(
        "QuickSpec",
        x = 0.95, y = 0.05,
        hjust = 1, vjust = 0,
        gp = grid::gpar(col = "grey80", fontsize = 20, alpha = 0.3)
      )
    )
}
