library(ggplot2)

# Helper closures don't see attached packages, so qualify calls here.
skip_if_no_raster <- function() {
  skip_if_not(capabilities("png") || requireNamespace("ragg", quietly = TRUE),
              "No PNG graphics device available")
}

base_plot <- function() {
  ggplot2::ggplot(mtcars, ggplot2::aes(wt, mpg)) + ggplot2::geom_point()
}

# A spread of plot types that stress different parts of the layout.
plot_zoo <- function() {
  list(
    scatter = base_plot(),
    facets_discrete = ggplot2::ggplot(ggplot2::mpg, ggplot2::aes(class)) + ggplot2::geom_bar() + ggplot2::facet_wrap(~drv),
    legend_bottom = ggplot2::ggplot(ggplot2::mpg, ggplot2::aes(displ, hwy, colour = class)) +
      ggplot2::geom_point() +
      ggplot2::theme(legend.position = "bottom") +
      ggplot2::labs(title = "Fuel economy", caption = "Source: EPA"),
    flipped = ggplot2::ggplot(ggplot2::mpg, ggplot2::aes(class, hwy)) + ggplot2::geom_boxplot() + ggplot2::coord_flip(),
    polar = ggplot2::ggplot(ggplot2::mpg, ggplot2::aes(x = factor(1), fill = class)) +
      ggplot2::geom_bar(width = 1) + ggplot2::coord_polar(theta = "y"),
    minimal = base_plot() + ggplot2::theme_minimal(),
    void = base_plot() + ggplot2::theme_void() + ggplot2::theme(plot.background = ggplot2::element_rect(fill = "white", colour = NA)),
    dates = ggplot2::ggplot(ggplot2::economics, ggplot2::aes(date, unemploy)) + ggplot2::geom_line()
  )
}

is_cran <- function() !identical(Sys.getenv("NOT_CRAN"), "true")
