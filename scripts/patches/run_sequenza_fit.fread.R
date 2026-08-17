#!/usr/bin/env Rscript
# Drop-in / merge reference for Sequenza fit (fread hardening).
# See references/runtime-hardening.md
#
# Usage (via apply script preferred):
#   Rscript run_sequenza_fit.fread.R <binned.seqz[.gz]> <outdir> <sample_id>

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3) {
  stop("Usage: run_sequenza_fit.fread.R <binned.seqz[.gz]> <outdir> <sample_id>")
}
seqz_file <- args[[1]]
outdir <- args[[2]]
sample_id <- args[[3]]
dir.create(outdir, recursive = TRUE, showWarnings = FALSE)

suppressPackageStartupMessages({
  library(sequenza)
  library(data.table)
})

resolve_seqz_path <- function(path) {
  if (!file.exists(path)) stop("seqz file not found: ", path)
  con <- file(path, "rb")
  magic <- readBin(con, what = "raw", n = 2L)
  close(con)
  is_gzip <- length(magic) == 2L && identical(magic, as.raw(c(0x1f, 0x8b)))
  if (grepl("\\.gz$", path, ignore.case = TRUE) && !is_gzip) {
    plain <- sub("\\.gz$", "", path, ignore.case = TRUE)
    if (!file.exists(plain)) {
      ok <- FALSE
      tryCatch({ file.link(path, plain); ok <- TRUE }, error = function(e) NULL)
      if (!ok) file.symlink(normalizePath(path), plain)
    }
    cat(sprintf("[%s] seqz named .gz but is plain text; using %s\n", Sys.time(), plain))
    return(plain)
  }
  path
}

seqz_file <- resolve_seqz_path(seqz_file)

readr_types_to_classes <- function(col_types) {
  chars <- strsplit(col_types, "", fixed = TRUE)[[1]]
  map <- c(c = "character", i = "integer", d = "numeric", l = "logical",
           `-` = "NULL", `_` = "NULL")
  vapply(chars, function(ch) {
    val <- map[[ch]]
    if (is.null(val)) "character" else val
  }, character(1), USE.NAMES = FALSE)
}

patch_sequenza_readers_fread <- function() {
  seq_ns <- asNamespace("sequenza")
  # Closures — do NOT environment(fn) <- seq_ns then get(..., envir = ns)
  unfold_gc_fn <- get("unfold_gc", envir = seq_ns)
  read_seqz_tbi_fn <- get("read.seqz.tbi", envir = seq_ns)
  split_chr_coord_fn <- get("split_chr_coord", envir = seq_ns)

  gc_fixed <- function(file, col_types = "c--dd----d----", buffer = 33554432,
                       parallel = 2L, verbose = TRUE) {
    if (verbose) {
      message("Collecting GC information via data.table::fread ", appendLF = FALSE)
    }
    keep <- which(strsplit(col_types, "", fixed = TRUE)[[1]] != "-")
    chunk_n <- 5000000L
    skip <- 1L
    res <- list()
    idx <- 1L
    nthreads <- max(1L, as.integer(parallel))
    repeat {
      dt <- data.table::fread(
        file = file, sep = "\t", header = FALSE, skip = skip, nrows = chunk_n,
        select = keep, col.names = paste0("V", seq_along(keep)),
        showProgress = FALSE, nThread = nthreads
      )
      if (nrow(dt) == 0L) break
      res[[idx]] <- list(
        unique = unique(dt[[1]]),
        lines = table(dt[[1]]),
        gc_nor = lapply(split(dt[[2]], dt[[4]]), table),
        gc_tum = lapply(split(dt[[3]], dt[[4]]), table)
      )
      if (verbose) message(".", appendLF = FALSE)
      skip <- skip + nrow(dt)
      idx <- idx + 1L
      if (nrow(dt) < chunk_n) break
    }
    if (verbose) message(" done\n")
    n <- length(res)
    if (n == 0L) stop("gc.sample.stats: no data rows read from ", file)
    xmat <- matrix(list(), nrow = n, ncol = 4L,
                   dimnames = list(NULL, c("unique", "lines", "gc_nor", "gc_tum")))
    for (i in seq_len(n)) {
      xmat[[i, "unique"]] <- res[[i]]$unique
      xmat[[i, "lines"]] <- res[[i]]$lines
      xmat[[i, "gc_nor"]] <- res[[i]]$gc_nor
      xmat[[i, "gc_tum"]] <- res[[i]]$gc_tum
    }
    unfold_gc_fn(xmat, stats = TRUE)
  }

  read_seqz_fixed <- function(file, n_lines = NULL, col_types = "ciciidddcddccc",
                              chr_name = NULL, buffer = 33554432, parallel = 1,
                              col_names = c("chromosome", "position", "base.ref",
                                            "depth.normal", "depth.tumor", "depth.ratio",
                                            "Af", "Bf", "zygosity.normal", "GC.percent",
                                            "good.reads", "AB.normal", "AB.tumor",
                                            "tumor.strand"),
                              ...) {
    if (is.null(n_lines)) {
      skip <- 1
      n_max <- Inf
    } else {
      n_lines <- round(sort(n_lines), 0)
      skip <- n_lines[1]
      n_max <- n_lines[2] - skip + 1
    }
    if (!is.null(chr_name)) {
      chr_name <- as.character(chr_name)
      tbi <- file.exists(paste(file, "tbi", sep = "."))
      if (tbi) {
        read_seqz_tbi_fn(file, split_chr_coord_fn(chr_name), col_names, col_types)
      } else {
        classes <- readr_types_to_classes(col_types)
        dt <- data.table::fread(
          file = file, sep = "\t", header = TRUE,
          col.names = col_names, colClasses = classes,
          showProgress = FALSE, nThread = max(1L, as.integer(parallel))
        )
        as.data.frame(dt[dt$chromosome == chr_name, , drop = FALSE])
      }
    } else {
      classes <- readr_types_to_classes(col_types)
      nrows <- if (is.finite(n_max)) as.integer(n_max) else -1L
      dt <- data.table::fread(
        file = file, sep = "\t", header = FALSE,
        skip = skip, nrows = nrows,
        col.names = col_names, colClasses = classes,
        showProgress = FALSE, nThread = max(1L, as.integer(parallel))
      )
      as.data.frame(dt)
    }
  }

  assignInNamespace("gc.sample.stats", gc_fixed, ns = "sequenza")
  assignInNamespace("read.seqz", read_seqz_fixed, ns = "sequenza")
  invisible(TRUE)
}

patched <- patch_sequenza_readers_fread()
cat(sprintf("[%s] sequenza fread patch applied: %s\n", Sys.time(), patched))
cat(sprintf("[%s] sequenza.extract %s\n", Sys.time(), seqz_file))
seqz_data <- sequenza.extract(seqz_file, verbose = TRUE)
cat(sprintf("[%s] sequenza.fit %s\n", Sys.time(), sample_id))
CP <- sequenza.fit(seqz_data)
saveRDS(seqz_data, file.path(outdir, paste0(sample_id, ".sequenza_extract.rds")))
saveRDS(CP, file.path(outdir, paste0(sample_id, ".sequenza_fit.rds")))

cat(sprintf("[%s] sequenza.results %s\n", Sys.time(), sample_id))
results_status <- tryCatch({
  sequenza.results(sequenza.extract = seqz_data, cp.table = CP,
                   sample.id = sample_id, out.dir = outdir)
  "ok"
}, error = function(e) {
  msg <- conditionMessage(e)
  cat(sprintf("[%s] WARNING sequenza.results failed after partial output: %s\n",
              Sys.time(), msg))
  writeLines(msg, file.path(outdir, paste0(sample_id, ".sequenza_results.warning.txt")))
  "warning"
})

make_cp_table <- function(CP) {
  if (is.data.frame(CP)) return(CP)
  if (is.list(CP) && all(c("ploidy", "cellularity", "lpp") %in% names(CP))) {
    grid <- expand.grid(ploidy = CP$ploidy, cellularity = CP$cellularity)
    grid$lpp <- as.vector(CP$lpp)
    grid$posterior <- grid$lpp
    grid$sequenza_results_status <- results_status
    return(grid)
  }
  data.frame(raw_class = paste(class(CP), collapse = ","),
             sequenza_results_status = results_status)
}

cp_table <- make_cp_table(CP)
write.table(cp_table, file.path(outdir, paste0(sample_id, ".cp.table.tsv")),
            sep = "\t", quote = FALSE, row.names = FALSE)
if ("posterior" %in% names(cp_table)) {
  best <- cp_table[which.max(cp_table$posterior), , drop = FALSE]
} else if ("score" %in% names(cp_table)) {
  best <- cp_table[order(cp_table$score), , drop = FALSE][1, , drop = FALSE]
} else {
  best <- cp_table[1, , drop = FALSE]
}
write.table(best, file.path(outdir, paste0(sample_id, ".sequenza_summary.tsv")),
            sep = "\t", quote = FALSE, row.names = FALSE)
cat(sprintf("[%s] done %s\n", Sys.time(), sample_id))
