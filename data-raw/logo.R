# Hex logo: a lineage (data -> code -> run) whose thread runs into the dot
# code under a chart. Run from the package root: Rscript data-raw/logo.R
# Uses the Avenir Next font (macOS); other systems fall back to their default
# sans, so regenerate on a Mac to reproduce the published logo exactly.
library(ggplot2)

navy <- "#0f1b2d"
teal <- "#5eead4"
ink <- "#f1f5f9"
slate <- "#8193ad"
bar_fill <- "#d6dee8"

shift <- -0.02
angles <- seq(pi / 2, 2 * pi + pi / 2, length.out = 7)
hex <- data.frame(x = 0.955 * cos(angles), y = 0.955 * sin(angles))

# The lineage: three nodes on a vertical thread, which bends into the chart's
# baseline of dots.
node_x <- -0.40
nodes <- data.frame(x = node_x, y = c(0.52, 0.30, 0.08) + shift)
base_y <- -0.10 + shift
dot_y <- -0.19 + shift
bend_r <- 0.12
arc <- seq(pi, 1.5 * pi, length.out = 30)
thread <- rbind(
  data.frame(x = node_x, y = nodes$y[1]),
  data.frame(x = node_x + bend_r + bend_r * cos(arc),
             y = dot_y + bend_r + bend_r * sin(arc)),
  data.frame(x = -0.19, y = dot_y)
)

bars <- data.frame(x = c(-0.06, 0.15, 0.36), h = c(0.26, 0.42, 0.62),
                   fill = c(bar_fill, bar_fill, teal))
code <- c(1, 0, 1, 1, 0, 1, 0, 1, 1, 0, 1)
dots <- data.frame(x = seq(-0.16, 0.46, length.out = length(code)), y = dot_y)
dots <- dots[code == 1, ]

logo <- ggplot() +
  geom_polygon(aes(x, y), hex, fill = navy, colour = teal, linewidth = 1.5) +
  geom_path(aes(x, y), thread, colour = slate, linewidth = 0.8) +
  geom_point(aes(x, y), nodes, shape = 21, size = 2.7, stroke = 1,
             colour = slate, fill = navy) +
  geom_rect(aes(xmin = x - 0.075, xmax = x + 0.075, ymin = base_y,
                ymax = base_y + h, fill = fill), bars, colour = NA) +
  scale_fill_identity() +
  geom_point(aes(x, y), dots, colour = teal, size = 1.25) +
  annotate("text", x = 0, y = -0.50, label = "gglineage", colour = ink,
           size = 5.4, family = "Avenir Next", fontface = "bold") +
  coord_fixed(xlim = c(-0.87, 0.87), ylim = c(-1.005, 1.005), expand = FALSE) +
  theme_void()

ggsave("man/figures/logo.png", logo, width = 1.74, height = 2.01, dpi = 300,
       bg = "transparent", device = ragg::agg_png)
