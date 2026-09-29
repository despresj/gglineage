# The stress matrix: render once, then push the image through compression,
# resampling, cropping, colour changes and degradation. Everything marked
# `survives` must decode exactly; everything else must fail cleanly. No
# transform may ever produce a wrong ID.

for (tf in stress_transforms()) {
  local({
    tf <- tf
    test_that(sprintf("%s: %s", tf$group, tf$name), {
      skip_if_no_raster()
      skip_if_not_installed("jpeg")
      set.seed(1)
      for (id in c("K7Q2M9XD", "RUN-42")) {
        img <- render_plot(base_plot() + watermark_dots(id))
        got <- extract_watermark(tf$f(img))
        if (tf$survives) {
          expect_equal(got, id)
        } else {
          expect_true(is.null(got) || identical(got, id),
                      label = sprintf("decoded %s as %s", id, format(got)))
        }
      }
    })
  })
}

test_that("stress matrix also holds on a faceted plot with a bottom legend", {
  skip_if_no_raster()
  skip_if_not_installed("jpeg")
  skip_on_cran()
  set.seed(1)
  p <- ggplot(mpg, aes(displ, hwy, colour = drv)) +
    geom_point() +
    facet_wrap(~year) +
    theme(legend.position = "bottom") +
    watermark_dots("K7Q2M9XD")
  img <- render_plot(p)
  for (tf in Filter(function(t) t$survives, stress_transforms())) {
    expect_equal(extract_watermark(tf$f(img)), "K7Q2M9XD", label = tf$name)
  }
})

test_that("real JPEG files on disk decode", {
  skip_if_no_raster()
  skip_if_not_installed("jpeg")
  file <- tempfile(fileext = ".jpg")
  on.exit(unlink(file))
  ggsave(file, base_plot() + watermark_dots("K7Q2M9XD"),
         width = 7, height = 5, dpi = 150, quality = 70)
  expect_equal(extract_watermark(file), "K7Q2M9XD")
})
