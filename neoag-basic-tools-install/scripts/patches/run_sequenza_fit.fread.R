#!/usr/bin/env Rscript
# Sequenza fit with chrom-split fread (sunbinbin 2026-08-17 success).
# Avoids vroom/gzfile on fake-.gz seqz and mmap/skip segfaults on huge files.
# Usage: Rscript run_sequenza_fit.fread.R <binned.seqz[.gz]> <outdir> <sample_id>

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3) {
  stop("Usage: run_sequenza_fit.fread.R <binned.seqz[.gz]> <outdir> <sample_id>")
}
seqz_file <- args[[1]]
outdir <- args[[2]]
sample_id <- args[[3]]
dir.create(outdir, recursive = TRUE, showWarnings = FALSE)

data.table::setDTthreads(1L)
Sys.setenv(OMP_NUM_THREADS = "1")

suppressPackageStartupMessages({
  library(sequenza)
  library(data.table)
})

seqz_is_gzip <- function(path) {
  con <- file(path, "rb")
  on.exit(close(con), add = TRUE)
  magic <- readBin(con, what = "raw", n = 2L)
  length(magic) == 2L && identical(magic, as.raw(c(0x1f, 0x8b)))
}

resolve_seqz_path <- function(path) {
  if (!file.exists(path)) stop("seqz file not found: ", path)
  is_gzip <- seqz_is_gzip(path)
  # sunbinbin β / seqz_binning: plain TSV named *.gz → hardlink twin without .gz
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
  # Real gzip (e.g. mistaken | gzip -c merge): materialize plain for awk split
  if (is_gzip) {
    plain <- if (grepl("\\.gz$", path, ignore.case = TRUE)) {
      sub("\\.gz$", "", path, ignore.case = TRUE)
    } else {
      paste0(path, ".ungz")
    }
    need <- !file.exists(plain) || file.info(plain)$mtime < file.info(path)$mtime
    if (need) {
      cat(sprintf("[%s] real gzip seqz; decompressing -> %s\n", Sys.time(), plain))
      status <- system2("gzip", c("-dc", path), stdout = plain, stderr = TRUE)
      if (!is.null(attr(status, "status")) && attr(status, "status") != 0) {
        stop("gzip -dc failed for ", path, ": ", paste(status, collapse = "\n"))
      }
      if (!file.exists(plain) || file.info(plain)$size == 0) {
        stop("decompress produced empty file: ", plain)
      }
    } else {
      cat(sprintf("[%s] reuse decompressed seqz %s\n", Sys.time(), plain))
    }
    return(plain)
  }
  path
}

`%||%` <- function(a, b) if (is.null(a)) b else a

fread_safe <- function(..., file = NULL, cmd = NULL) {
  extra <- list(...)
  extra$showProgress <- FALSE
  extra$nThread <- 1L
  extra$sep <- extra$sep %||% "\t"
  if (!is.null(file)) extra$file <- file
  if (!is.null(cmd)) extra$cmd <- cmd
  extra$mmap <- FALSE
  tryCatch(
    do.call(data.table::fread, extra),
    error = function(e) {
      extra$mmap <- NULL
      if (!is.null(file) && is.null(extra$cmd)) {
        extra$file <- NULL
        extra$cmd <- sprintf("cat %s", shQuote(file))
      }
      do.call(data.table::fread, extra)
    }
  )
}

split_seqz_by_chrom <- function(seqz_path) {
  chrom_dir <- paste0(seqz_path, ".by_chrom")
  index_file <- file.path(chrom_dir, "line_index.tsv")
  dir.create(chrom_dir, recursive = TRUE, showWarnings = FALSE)
  if (file.exists(index_file)) {
    idx <- utils::read.delim(index_file, stringsAsFactors = FALSE)
    if (nrow(idx) > 0 && all(file.exists(idx$path)) && all(file.info(idx$path)$size > 0)) {
      cat(sprintf("[%s] reuse chrom splits n=%d dir=%s\n", Sys.time(), nrow(idx), chrom_dir))
      return(idx)
    }
  }
  cat(sprintf("[%s] splitting seqz by chromosome -> %s\n", Sys.time(), chrom_dir))
  awk <- paste0(
    "BEGIN{OFS=\"\\t\"; total=0; nchr=0; chr=\"\"}\n",
    "NR==1{hdr=$0; next}\n",
    "$1!=chr{\n",
    "  if(chr!=\"\"){\n",
    "    start=total-nchr+1; end=total;\n",
    "    print chr, start, end, out >> idxf;\n",
    "    close(out)\n",
    "  }\n",
    "  chr=$1; nchr=0; safe=$1;\n",
    "  gsub(/[^A-Za-z0-9._-]/, \"_\", safe);\n",
    "  out=dir \"/\" safe \".seqz\";\n",
    "  print hdr > out\n",
    "}\n",
    "{print >> out; total++; nchr++}\n",
    "END{\n",
    "  if(chr!=\"\"){\n",
    "    start=total-nchr+1; end=total;\n",
    "    print chr, start, end, out >> idxf;\n",
    "    close(out)\n",
    "  }\n",
    "}\n"
  )
  awk_file <- file.path(chrom_dir, "split.awk")
  writeLines(awk, awk_file)
  unlink(index_file)
  old <- list.files(chrom_dir, pattern = "\\.seqz$", full.names = TRUE)
  if (length(old)) unlink(old)
  status <- system2(
    "awk",
    c("-v", paste0("dir=", chrom_dir), "-v", paste0("idxf=", index_file),
      "-f", awk_file, seqz_path),
    stdout = TRUE, stderr = TRUE
  )
  if (!is.null(attr(status, "status")) && attr(status, "status") != 0) {
    stop("awk chrom split failed: ", paste(status, collapse = "\n"))
  }
  if (!file.exists(index_file) || file.info(index_file)$size == 0) {
    stop("chrom split produced empty index: ", index_file)
  }
  idx <- utils::read.delim(
    index_file, header = FALSE, stringsAsFactors = FALSE,
    col.names = c("chrom", "start", "end", "path")
  )
  utils::write.table(idx, index_file, sep = "\t", quote = FALSE, row.names = FALSE)
  cat(sprintf("[%s] split done chromosomes=%d\n", Sys.time(), nrow(idx)))
  print(idx)
  idx
}

seqz_file <- resolve_seqz_path(seqz_file)
chrom_index <- split_seqz_by_chrom(seqz_file)

readr_types_to_classes <- function(col_types) {
  chars <- strsplit(col_types, "", fixed = TRUE)[[1]]
  map <- c(c = "character", i = "integer", d = "numeric", l = "logical",
           `-` = "NULL", `_` = "NULL")
  vapply(chars, function(ch) {
    val <- map[[ch]]
    if (is.null(val)) "character" else val
  }, character(1), USE.NAMES = FALSE)
}

lookup_chrom_file <- function(n_lines) {
  n_lines <- as.integer(round(sort(n_lines), 0))
  hit <- chrom_index$start == n_lines[1] & chrom_index$end == n_lines[2]
  if (!any(hit)) {
    return(NULL)
  }
  chrom_index$path[which(hit)[1]]
}

patch_sequenza_readers_fread <- function() {
  seq_ns <- asNamespace("sequenza")
  unfold_gc_fn <- get("unfold_gc", envir = seq_ns)
  read_seqz_tbi_fn <- get("read.seqz.tbi", envir = seq_ns)
  split_chr_coord_fn <- get("split_chr_coord", envir = seq_ns)

  gc_fixed <- function(file, col_types = "c--dd----d----", buffer = 33554432,
                       parallel = 2L, verbose = TRUE) {
    if (verbose) {
      message("Collecting GC information from chrom splits via fread ", appendLF = FALSE)
    }
    keep <- which(strsplit(col_types, "", fixed = TRUE)[[1]] != "-")
    res <- list()
    idx <- 1L
    for (i in seq_len(nrow(chrom_index))) {
      dt <- fread_safe(
        file = chrom_index$path[i], header = TRUE, select = keep
      )
      if (nrow(dt) == 0L) next
      res[[idx]] <- list(
        unique = unique(dt[[1]]),
        lines = table(dt[[1]]),
        gc_nor = lapply(split(dt[[2]], dt[[4]]), table),
        gc_tum = lapply(split(dt[[3]], dt[[4]]), table)
      )
      if (verbose) message(".", appendLF = FALSE)
      idx <- idx + 1L
    }
    if (verbose) message(" done\n")
    n <- length(res)
    if (n == 0L) stop("gc.sample.stats: no data rows from chrom splits")
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
    classes <- readr_types_to_classes(col_types)
    if (!is.null(chr_name)) {
      chr_name <- as.character(chr_name)
      chrom_only <- sub(":.*$", "", chr_name)
      hit <- chrom_index$chrom == chrom_only | chrom_index$chrom == paste0("chr", chrom_only)
      if (any(hit) && !grepl(":", chr_name, fixed = TRUE)) {
        dt <- fread_safe(
          file = chrom_index$path[which(hit)[1]], header = TRUE,
          col.names = col_names, colClasses = classes
        )
        return(as.data.frame(dt))
      }
      tbi <- file.exists(paste(file, "tbi", sep = "."))
      if (tbi) {
        return(read_seqz_tbi_fn(file, split_chr_coord_fn(chr_name), col_names, col_types))
      }
      dt <- fread_safe(
        file = file, header = TRUE, col.names = col_names, colClasses = classes
      )
      return(as.data.frame(dt[dt$chromosome == chr_name, , drop = FALSE]))
    }
    if (!is.null(n_lines)) {
      n_lines <- round(sort(n_lines), 0)
      chrom_path <- lookup_chrom_file(n_lines)
      if (!is.null(chrom_path)) {
        cat(sprintf("[%s] read.seqz n_lines=%s,%s -> %s\n",
                    Sys.time(), n_lines[1], n_lines[2], chrom_path))
        dt <- fread_safe(
          file = chrom_path, header = TRUE,
          col.names = col_names, colClasses = classes
        )
        return(as.data.frame(dt))
      }
      stop("read.seqz: no chrom split for n_lines=", paste(n_lines, collapse = ","))
    }
    dt <- fread_safe(
      file = file, header = TRUE, col.names = col_names, colClasses = classes
    )
    as.data.frame(dt)
  }

  assignInNamespace("gc.sample.stats", gc_fixed, ns = "sequenza")
  assignInNamespace("read.seqz", read_seqz_fixed, ns = "sequenza")
  invisible(TRUE)
}

patched <- patch_sequenza_readers_fread()
cat(sprintf("[%s] sequenza chrom-split fread patch applied: %s\n", Sys.time(), patched))
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
