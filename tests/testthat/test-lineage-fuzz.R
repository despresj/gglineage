# Property-based tests of the lineage invariant: whatever is done to a code,
# decoding gives back the ID that was drawn, or NULL. Trial counts scale with
# GGLINEAGE_FUZZ_N; the seed is fixed (override with GGLINEAGE_FUZZ_SEED) so
# a failure reproduces, and every failure label carries the trial number.

test_that("fuzz: random IDs of every kind round-trip through the codec exactly", {
  set.seed(fuzz_seed(101))
  n <- fuzz_n(3000)
  for (i in seq_len(n)) {
    id <- random_id()
    got <- decode_rows(encode_rows(id))
    if (!identical(got, check_id(id))) {
      fail(sprintf("trial %d: %s decoded as %s", i, id, format(got)))
    }
  }
  succeed()
})

test_that("fuzz: corrupted rows decode to the original ID or NULL, never another", {
  set.seed(fuzz_seed(102))
  n <- fuzz_n(3000)
  wrong <- 0L
  for (i in seq_len(n)) {
    id <- check_id(random_id())
    rows <- encode_rows(id)
    # Damage one row or both, by 1 to 24 bits each.
    hit <- if (length(rows) == 2L) sample(list(1L, 2L, 1:2), 1L)[[1]] else 1L
    for (r in hit) rows[[r]] <- flip_bits(rows[[r]], sample(1:24, 1L))
    got <- decode_rows(rows)
    if (!is.null(got) && !identical(got, id)) {
      wrong <- wrong + 1L
      fail(sprintf("trial %d: %s corrupted into %s", i, id, got))
    }
  }
  expect_identical(wrong, 0L)
})

test_that("UUIDs one bit apart never exchange rows (all 128 bits, both orders)", {
  set.seed(fuzz_seed(103))
  for (trial in 1:3) {
    a <- as.raw(sample(0:255, 16L, replace = TRUE))
    ra <- encode_rows(format_uuid(a))
    for (bit in 0:127) {
      b <- a
      byte <- bit %/% 8L + 1L
      b[byte] <- xor(b[byte], as.raw(bitwShiftL(1L, bit %% 8L)))
      rb <- encode_rows(format_uuid(b))
      expect_null(decode_rows(list(ra[[1]], rb[[2]])), label = sprintf("A1+B2, bit %d", bit))
      expect_null(decode_rows(list(rb[[1]], ra[[2]])), label = sprintf("B1+A2, bit %d", bit))
    }
  }
})

test_that("fuzz: halves of UUIDs that share bytes never join into a third UUID", {
  set.seed(fuzz_seed(104))
  n <- fuzz_n(2000)
  for (i in seq_len(n)) {
    a <- as.raw(sample(0:255, 16L, replace = TRUE))
    b <- a
    # Keep a random subset of bytes in common, often a whole half.
    change <- switch(sample(c("first", "second", "some"), 1L),
                     first = 9:16, second = 1:8, some = sample(16L, sample(1:15, 1L)))
    b[change] <- as.raw(sample(0:255, length(change), replace = TRUE))
    if (identical(a, b)) next
    ra <- encode_rows(format_uuid(a))
    rb <- encode_rows(format_uuid(b))
    for (mix in list(list(ra[[1]], rb[[2]]), list(rb[[1]], ra[[2]]))) {
      got <- decode_rows(mix)
      if (!is.null(got)) {
        fail(sprintf("trial %d: rows of %s and %s joined into %s",
                     i, format_uuid(a), format_uuid(b), got))
      }
    }
  }
  succeed()
})

test_that("fuzz: repairing a damaged UUID row restores it exactly or gives up", {
  set.seed(fuzz_seed(105))
  n <- fuzz_n(300)
  repaired <- 0L
  for (i in seq_len(n)) {
    id <- format_uuid(as.raw(sample(0:255, 16L, replace = TRUE)))
    rows <- encode_rows(id)
    half <- sample(1:2, 1L)
    partner <- parse_frame(rows[[3L - half]])
    free <- 25:120
    weak <- sample(free, sample(0:4, 1L))
    erased <- sample(setdiff(free[rows[[half]][free] == 1L], weak), sample(0:2, 1L))
    if (length(weak) + length(erased) == 0L) next
    v <- soft_row(rows[[half]], weak = weak, erased = erased)
    frame <- repair_uuid_row(v, 0.5, half, partner_accept(partner), partner)
    if (is.null(frame)) next
    got <- join_halves(partner, frame)
    if (!identical(got, id)) {
      fail(sprintf("trial %d: %s repaired into %s", i, id, format(got)))
    }
    repaired <- repaired + 1L
  }
  # Most damage of this size is repairable; a repair that never fires would
  # pass the test above trivially.
  expect_gt(repaired, n / 2)
})

# A row of another UUID may be repaired to fit only when its payload is the
# partner's own half byte for byte (two UUIDs sharing 8 bytes, whose rows
# then differ only in the pair bits): the result is then the partner's UUID,
# every byte of it read from the image. Anything else would be a third ID.
test_that("fuzz: a damaged row of another UUID never yields a UUID that was not drawn", {
  set.seed(fuzz_seed(106))
  n <- fuzz_n(300)
  for (i in seq_len(n)) {
    a <- as.raw(sample(0:255, 16L, replace = TRUE))
    b <- a
    change <- switch(sample(c("first", "second", "byte", "all"), 1L),
                     first = 1:8, second = 9:16, byte = sample(16L, 1L), all = 1:16)
    b[change] <- as.raw(sample(0:255, length(change), replace = TRUE))
    if (identical(a, b)) next
    half <- sample(1:2, 1L)
    partner <- parse_frame(encode_rows(format_uuid(a))[[3L - half]])
    foreign <- encode_rows(format_uuid(b))[[half]]
    v <- soft_row(foreign, weak = sample(25:120, sample(0:4, 1L)))
    frame <- repair_uuid_row(v, 0.5, half, partner_accept(partner), partner)
    if (!is.null(frame)) {
      same_payload <- identical(foreign[25:88], encode_rows(format_uuid(a))[[half]][25:88])
      joined <- join_halves(partner, frame)
      if (!same_payload || !identical(joined, format_uuid(a))) {
        fail(sprintf("trial %d: a row of %s was repaired to fit %s (joined: %s)",
                     i, format_uuid(b), format_uuid(a), format(joined)))
      }
    }
  }
  succeed()
})

test_that("a row sharing the partner's bytes completes the partner's UUID, nothing else", {
  # Found by the fuzz campaign (seed 2026): these two UUIDs share bytes 1-8,
  # so their first rows differ only in two pair-check bits.
  a <- "4f77baf8-9f08-2124-e851-88c49df21030"
  b <- "4f77baf8-9f08-2124-23d1-bc9c2aaedb7c"
  ra <- encode_rows(a)
  rb <- encode_rows(b)
  expect_identical(ra[[1]][25:88], rb[[1]][25:88])
  partner <- parse_frame(ra[[2]])
  set.seed(1)
  frame <- repair_uuid_row(soft_row(rb[[1]]), 0.5, 1L, partner_accept(partner), partner)
  expect_identical(join_halves(partner, frame), a)
  # Read cleanly, without repair, the same pair of rows is rejected.
  expect_null(decode_rows(list(rb[[1]], ra[[2]])))
})

test_that("fuzz: composed, perturbed images decode to a drawn ID or NULL", {
  skip_if_no_raster()
  skip_if_not_installed("jpeg")
  skip_on_cran()
  set.seed(fuzz_seed(107))
  pool <- fuzz_pool()
  n <- fuzz_n(40)
  exact <- 0L
  for (i in seq_len(n)) {
    r <- fuzz_trial(pool)
    expect_true(r$ok, label = sprintf("trial %d (%s | %s) decoded %s, not one of %s",
                                      i, r$charts, r$steps, format(r$got),
                                      paste(r$drawn, collapse = ", ")))
    exact <- exact + r$exact
  }
  # The trials are not all hopeless: plenty still decode.
  expect_gt(exact, n / 5)
})
