# Large-scale run of the lineage fuzz in tests/testthat/test-lineage-fuzz.R:
# random IDs through the codec, corrupted and cross-joined rows, soft-decision
# repair against true and foreign partners, and composed, perturbed images.
# The invariant everywhere: a decode returns an ID that was drawn, or NULL.
# Writes a Markdown summary (to the GitHub run summary in Actions) and exits
# non-zero on any wrong ID.
#
# Usage (from the package root):
#   Rscript tools/lineage-fuzz-campaign.R [codec_n] [repair_n] [image_n] [seed]

args <- as.integer(commandArgs(TRUE))
codec_n <- if (length(args) >= 1L && !is.na(args[1])) args[1] else 20000L
repair_n <- if (length(args) >= 2L && !is.na(args[2])) args[2] else 2000L
image_n <- if (length(args) >= 3L && !is.na(args[3])) args[3] else 300L
seed <- if (length(args) >= 4L && !is.na(args[4])) args[4] else 2026L

suppressPackageStartupMessages(pkgload::load_all(".", quiet = TRUE, helpers = FALSE))
for (f in c("helper-plots.R", "helper-transforms.R", "helper-fuzz.R")) {
  source(file.path("tests", "testthat", f))
}
set.seed(seed)
started <- Sys.time()
wrong <- list()
note_wrong <- function(stage, ...) wrong[[length(wrong) + 1L]] <<- sprintf("%s: %s", stage, sprintf(...))

# 1. Codec: round trip, then corruption of 1-24 bits per damaged row.
codec <- c(roundtrip = 0L, corrupted = 0L, corrupted_decoded = 0L)
for (i in seq_len(codec_n)) {
  id <- check_id(random_id())
  rows <- encode_rows(id)
  if (identical(decode_rows(rows), id)) codec["roundtrip"] <- codec["roundtrip"] + 1L else
    note_wrong("codec round trip", "%s", id)
  hit <- if (length(rows) == 2L) sample(list(1L, 2L, 1:2), 1L)[[1]] else 1L
  for (r in hit) rows[[r]] <- flip_bits(rows[[r]], sample(1:24, 1L))
  got <- decode_rows(rows)
  codec["corrupted"] <- codec["corrupted"] + 1L
  if (!is.null(got)) {
    codec["corrupted_decoded"] <- codec["corrupted_decoded"] + 1L
    if (!identical(got, id)) note_wrong("codec corruption", "%s -> %s", id, got)
  }
}

# 2. Cross-joins of UUIDs sharing bytes.
joins <- 0L
for (i in seq_len(codec_n %/% 2L)) {
  a <- as.raw(sample(0:255, 16L, replace = TRUE))
  b <- a
  change <- switch(sample(c("first", "second", "some", "bit"), 1L),
                   first = 9:16, second = 1:8, some = sample(16L, sample(1:15, 1L)),
                   bit = sample(16L, 1L))
  b[change] <- if (length(change) == 1L) xor(b[change], as.raw(bitwShiftL(1L, sample(0:7, 1L)))) else
    as.raw(sample(0:255, length(change), replace = TRUE))
  if (identical(a, b)) next
  ra <- encode_rows(format_uuid(a))
  rb <- encode_rows(format_uuid(b))
  for (mix in list(list(ra[[1]], rb[[2]]), list(rb[[1]], ra[[2]]))) {
    joins <- joins + 1L
    got <- decode_rows(mix)
    if (!is.null(got)) note_wrong("cross join", "%s + %s -> %s", format_uuid(a), format_uuid(b), got)
  }
}

# 3. Repair: own damaged row (should come back exact or NULL) and a foreign
# row against a partner (should never be accepted).
repair <- c(own = 0L, own_repaired = 0L, foreign = 0L, foreign_accepted = 0L)
for (i in seq_len(repair_n)) {
  a <- as.raw(sample(0:255, 16L, replace = TRUE))
  id <- format_uuid(a)
  rows <- encode_rows(id)
  half <- sample(1:2, 1L)
  partner <- parse_frame(rows[[3L - half]])
  free <- 25:120
  weak <- sample(free, sample(0:4, 1L))
  erased <- sample(setdiff(free[rows[[half]][free] == 1L], weak), sample(0:2, 1L))
  if (length(weak) + length(erased) > 0L) {
    repair["own"] <- repair["own"] + 1L
    frame <- repair_uuid_row(soft_row(rows[[half]], weak, erased), 0.5, half,
                             partner_accept(partner), partner)
    if (!is.null(frame)) {
      got <- join_halves(partner, frame)
      if (identical(got, id)) repair["own_repaired"] <- repair["own_repaired"] + 1L else
        note_wrong("repair own", "%s -> %s", id, format(got))
    }
  }
  b <- a
  change <- switch(sample(c("first", "second", "byte", "all"), 1L),
                   first = 1:8, second = 9:16, byte = sample(16L, 1L), all = 1:16)
  b[change] <- as.raw(sample(0:255, length(change), replace = TRUE))
  if (!identical(a, b)) {
    repair["foreign"] <- repair["foreign"] + 1L
    foreign <- encode_rows(format_uuid(b))[[half]]
    frame <- repair_uuid_row(soft_row(foreign, weak = sample(free, sample(0:4, 1L))), 0.5, half,
                             partner_accept(partner), partner)
    if (!is.null(frame)) {
      # Allowed only when the row carries the partner's own half byte for
      # byte (the UUIDs share those 8 bytes), so every byte of the result
      # was read from the image; see test-lineage-fuzz.R.
      repair["foreign_accepted"] <- repair["foreign_accepted"] + 1L
      same_payload <- identical(foreign[25:88], rows[[half]][25:88])
      if (!same_payload || !identical(join_halves(partner, frame), id)) {
        note_wrong("repair foreign", "row of %s fitted to %s", format_uuid(b), id)
      }
    }
  }
}

# 4. Images.
pool <- fuzz_pool()
trials <- vector("list", image_n)
for (i in seq_len(image_n)) {
  t0 <- Sys.time()
  r <- fuzz_trial(pool)
  r$seconds <- as.numeric(Sys.time() - t0, units = "secs")
  trials[[i]] <- r
  if (!r$ok) note_wrong("image", "trial %d (%s | %s) -> %s", i, r$charts, r$steps, format(r$got))
}
images <- data.frame(
  ok = vapply(trials, `[[`, TRUE, "ok"),
  exact = vapply(trials, `[[`, TRUE, "exact"),
  seconds = vapply(trials, `[[`, 0, "seconds")
)

minutes <- as.numeric(Sys.time() - started, units = "mins")
md <- c(
  "## Lineage fuzz campaign",
  "",
  sprintf("Seed %d; %.1f minutes; %s.", seed, minutes, R.version.string),
  "",
  "| Stage | Trials | Result |",
  "|---|---:|---|",
  sprintf("| Codec round trip (random text, base32 and UUID IDs) | %d | %d exact |",
          codec_n, codec[["roundtrip"]]),
  sprintf("| Codec corruption (1-24 flipped bits per damaged row) | %d | %d decoded (all to the original), rest NULL |",
          codec[["corrupted"]], codec[["corrupted_decoded"]]),
  sprintf("| Rows of two UUIDs sharing bytes, cross-joined | %d | all NULL unless listed below |", joins),
  sprintf("| Repair of own damaged row against true partner | %d | %d repaired exactly, rest NULL |",
          repair[["own"]], repair[["own_repaired"]]),
  sprintf("| Repair of another UUID's row against a partner | %d | %d accepted, each only where the row carried the partner's own 8 bytes |",
          repair[["foreign"]], repair[["foreign_accepted"]]),
  sprintf("| Composed, perturbed images | %d | %d decoded to a drawn ID, %d NULL; median %.2f s, max %.1f s |",
          image_n, sum(images$exact & images$ok), sum(!images$exact),
          stats::median(images$seconds), max(images$seconds)),
  "",
  if (length(wrong) == 0L) "**Wrong IDs: 0.**" else
    c(sprintf("**Wrong IDs: %d.**", length(wrong)), "", paste("-", unlist(wrong)))
)
summary_file <- Sys.getenv("GITHUB_STEP_SUMMARY")
if (nzchar(summary_file)) write(md, summary_file, append = TRUE)
writeLines(md)
if (length(wrong) > 0L) quit(status = 1L)
