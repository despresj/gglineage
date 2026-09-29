#' Save a ggplot with an embedded steganographic watermark
#'
#' Renders a ggplot to an image file and embeds a hidden watermark in the
#' least significant bits (LSB) of the pixel data. The resulting image is
#' visually identical to the original - pixel differences are at most 1 RGB value.
#'
#' @param plot A ggplot object
#' @param filename Output filename (PNG recommended for lossless compression)
#' @param watermark The watermark string to embed (e.g., UUID)
#' @param width,height Image dimensions in inches
#' @param dpi Resolution in dots per inch
#' @param ... Additional arguments passed to ggsave
#'
#' @return Invisibly returns the watermark that was embedded
#' @export
#'
#' @examples
#' library(ggplot2)
#'
#' p <- ggplot(mtcars, aes(wt, mpg)) +
#'   geom_point()
#'
#' # Save with hidden watermark
#' ggsave_watermark(p, "plot.png", watermark = "ID-12345")
#'
#' # Extract it later
#' extract_watermark("plot.png")
#'
ggsave_watermark <- function(plot,
                             filename,
                             watermark,
                             width = 7,
                             height = 5,
                             dpi = 300,
                             ...) {

  if (!requireNamespace("png", quietly = TRUE)) {
    stop("Package 'png' is required. Install with: install.packages('png')")
  }

  if (missing(watermark) || is.null(watermark)) {
    stop("You must provide a watermark")
  }

  # Create temp file for initial render
  temp_file <- tempfile(fileext = ".png")
  on.exit(unlink(temp_file), add = TRUE)

  # Render the plot
  ggplot2::ggsave(temp_file, plot = plot, width = width, height = height,
                  dpi = dpi, ...)

  # Read the image
  img <- png::readPNG(temp_file)

  # Embed the watermark using LSB steganography
  img_watermarked <- embed_lsb(img, watermark)

  # Write the watermarked image
  png::writePNG(img_watermarked, filename)

  message("Watermark embedded: ", watermark)
  invisible(watermark)
}

#' Embed data in the least significant bits of an image
#'
#' @param img A 3D array (RGB image from png::readPNG)
#' @param message The string to embed
#'
#' @return The modified image array
#' @keywords internal
embed_lsb <- function(img, message) {
  # Convert message to binary
  msg_bytes <- charToRaw(message)
  # Add length prefix (4 bytes)
  len_bytes <- packBits(intToBits(length(msg_bytes)), "raw")[1:4]
  all_bytes <- c(len_bytes, msg_bytes)

  # Convert to bits
  bits <- as.integer(rawToBits(all_bytes))

  # Check capacity (using only red channel)
  n_pixels <- prod(dim(img)[1:2])
  if (length(bits) > n_pixels) {
    stop("Watermark too long for image size. Max ~",
         floor(n_pixels / 8) - 4, " characters.")
  }

  # Flatten red channel, embed bits in LSB
  red <- as.vector(img[, , 1])

  # Convert to 0-255 integer space
  red_int <- round(red * 255)

  # Clear LSB and set to our bit
  for (i in seq_along(bits)) {
    red_int[i] <- bitwAnd(red_int[i], 0xFE) + bits[i]
  }

  # Convert back to 0-1 float
  img[, , 1] <- matrix(red_int / 255, nrow = dim(img)[1], ncol = dim(img)[2])

  img
}

#' Extract a watermark from an image file
#'
#' Reads the hidden watermark from the LSB of pixel data.
#'
#' @param filename Path to a PNG image with embedded watermark
#'
#' @return The extracted watermark string, or NULL if none found
#' @export
#'
#' @examples
#' # After saving with ggsave_watermark()
#' extract_watermark("plot.png")
#'
extract_watermark <- function(filename) {
  if (!requireNamespace("png", quietly = TRUE)) {
    stop("Package 'png' is required. Install with: install.packages('png')")
  }

  if (!file.exists(filename)) {
    stop("File not found: ", filename)
  }

  # Read image
  img <- png::readPNG(filename)

  # Extract from red channel
  red <- as.vector(img[, , 1])
  red_int <- round(red * 255)

  # Extract LSBs
  lsb <- bitwAnd(red_int, 1L)

  # First 32 bits (4 bytes) are the length
  len_bits <- lsb[1:32]
  len_raw <- packBits(as.integer(len_bits), "raw")
  msg_len <- sum(as.integer(len_raw) * (256^(0:3)))

  # Sanity check
  if (msg_len <= 0 || msg_len > 10000) {
    return(NULL)
  }

  # Extract message bits
  msg_bits <- lsb[33:(32 + msg_len * 8)]
  msg_raw <- packBits(as.integer(msg_bits), "raw")

  rawToChar(msg_raw)
}

#' Generate a UUID v4
#'
#' @return A character string containing a UUID
#' @export
generate_uuid <- function() {
  hex_chars <- c(0:9, letters[1:6])
  rand_hex <- function(n) paste0(sample(hex_chars, n, replace = TRUE), collapse = "")

  sprintf(
    "%s-%s-4%s-%s%s-%s",
    rand_hex(8),
    rand_hex(4),
    rand_hex(3),
    sample(c("8", "9", "a", "b"), 1),
    rand_hex(3),
    rand_hex(12)
  )
}
