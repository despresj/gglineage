# Hex logo, drawn with ggplot2 and carrying a real dot code for "wm".
# Run from the package root: Rscript data-raw/logo.R
library(ggplot2)
pkgload::load_all(quiet = TRUE)

angles <- seq(pi / 2, 2 * pi + pi / 2, length.out = 7)
hex <- data.frame(x = 0.92 * cos(angles), y = 0.92 * sin(angles))

set.seed(11)
pts <- data.frame(x = runif(30, -0.5, 0.5))
pts$y <- 0.12 + 0.5 * pts$x + rnorm(30, 0, 0.08)

bits <- watermark:::encode_bits("wm")
dots <- data.frame(
  x = seq(-0.6, 0.6, length.out = length(bits)),
  y = -0.3,
  on = bits == 1L
)

logo <- ggplot() +
  geom_polygon(aes(x, y), hex, fill = "#0f1b2d", colour = "#5eead4",
               linewidth = 2) +
  annotate("segment", x = -0.55, xend = 0.55, y = 0.12 - 0.275, yend = 0.12 + 0.275,
           colour = "#5eead4", linewidth = 0.8, alpha = 0.6) +
  geom_point(aes(x, y), pts, colour = "#e2e8f0", size = 1.5, alpha = 0.9) +
  geom_point(aes(x, y), dots[dots$on, ], colour = "#5eead4", size = 0.38) +
  annotate("text", x = 0, y = -0.52, label = "watermark",
           colour = "#f8fafc", size = 6, fontface = "bold", family = "sans") +
  coord_fixed(xlim = c(-0.84, 0.84), ylim = c(-0.97, 0.97), expand = FALSE) +
  theme_void()

ggsave("man/figures/logo.png", logo, width = 1.68, height = 1.94,
       dpi = 310, bg = "transparent")
