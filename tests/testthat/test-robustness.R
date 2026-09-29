# The stress matrix: render once, then push the image through compression,
# resampling, cropping, colour changes and degradation. Everything marked
# `survives` must decode exactly; everything else must fail cleanly. No
# transform may ever produce a wrong ID.

# Render each base image once and reuse it for every transform.
base_images <- local({
  cache <- list()
  function(id) {
    if (is.null(cache[[id]])) {
      cache[[id]] <<- render_plot(base_plot() + watermark_dots(id))
    }
    cache[[id]]
  }
})

for (tf in stress_transforms()) {
  local({
    tf <- tf
    test_that(sprintf("%s: %s", tf$group, tf$name), {
      skip_if_no_raster()
      skip_if_not_installed("jpeg")
      if (isTRUE(tf$slow)) skip_on_cran()
      set.seed(1)
      ids <- if (is_cran()) "K7Q2M9XD" else c("K7Q2M9XD", "RUN-42")
      for (id in ids) {
        got <- extract_watermark(tf$f(base_images(id)))
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

test_that("random IDs near and past the limits decode exactly or not at all", {
  skip_if_no_raster()
  skip_if_not_installed("jpeg")
  skip_on_cran()
  set.seed(11)
  ids <- c(vapply(c(1, 4, 8, 12, 16), wm_id, character(1)),
           "RUN-42", "fig 2 (v3)", "café", "a1b2c3d4e5f6a7b8")
  chains <- list(
    function(x) tf_jpeg(tf_resize_to_width(x, 360), 50),
    function(x) tf_jpeg(tf_resize_to_width(x, 300), 50),
    function(x) tf_jpeg(tf_resize_to_width(x, 260), 35),
    function(x) tf_jpeg(tf_resize(x, 0.5), 15)
  )
  for (id in ids) {
    img <- render_plot(base_plot() + watermark_dots(id))
    for (chain in chains) {
      got <- extract_watermark(suppressWarnings(chain(img)))
      expect_true(is.null(got) || identical(got, id),
                  label = sprintf("decoded %s as %s", id, format(got)))
    }
  }
})
