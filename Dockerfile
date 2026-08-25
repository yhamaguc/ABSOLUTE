FROM gcr.io/broad-getzlab-workflows/base_image:v0.0.4

# NOTE: base_image:v0.0.4 is Ubuntu 20.04 (focal) and carries apt package lists
#       frozen at 2021-04.  `apt-get update` therefore MUST run in the same RUN
#       instruction as `apt-get install`: when the update sits in its own layer
#       and that layer is served from the build cache, apt resolves package
#       versions that have since been superseded in the pool and every download
#       404s (libjpeg-turbo8 2.0.3-0ubuntu1.20.04.1, libtiff5, libglvnd0, ...).
#       focal itself is still served by archive.ubuntu.com, so the mirror does
#       not need changing.

WORKDIR /build
ENV DEBIAN_FRONTEND=noninteractive

# R interpreter.  focal ships R 3.6.3; the CRAN/Bioconductor snapshots below are
# pinned to match it, so this is the one version this image is built against.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      r-base-core \
      r-base-dev \
      r-recommended \
      libxml2-dev && \
    rm -rf /var/lib/apt/lists/*

# R package sources, pinned.  Head CRAN installs BiocManager 1.30.27, which only
# serves Bioconductor releases requiring R >= 4.4 and so cannot install
# GenomicRanges here.  2020-06-01 / Bioconductor 3.10 is the pair that matches
# R 3.6.3.
ARG CRAN_SNAPSHOT="https://packagemanager.posit.co/cran/__linux__/focal/2020-06-01"
ARG BIOC_VERSION="3.10"
ENV BIOC_VERSION=${BIOC_VERSION}

# HTTPUserAgent is what makes Posit Package Manager serve prebuilt focal
# binaries instead of source tarballs.
RUN printf '%s\n' \
      "options(repos = c(CRAN = \"${CRAN_SNAPSHOT}\"))" \
      "options(HTTPUserAgent = sprintf(\"R/%s R (%s)\", getRversion(), paste(getRversion(), R.version[\"platform\"], R.version[\"arch\"], R.version[\"os\"])))" \
      "options(Ncpus = max(1L, min(8L, parallel::detectCores())))" \
      >> /usr/lib/R/etc/Rprofile.site

# NOTE: install.packages() only warns on failure, so every install step asserts
#       that the packages really landed.
RUN Rscript -e 'pkgs <- c("optparse", "gplots", "RColorBrewer", "plyr", "BiocManager"); \
      install.packages(pkgs); \
      missing <- setdiff(pkgs, rownames(installed.packages())); \
      if (length(missing) > 0) stop("failed to install: ", paste(missing, collapse = ", "))'

RUN Rscript -e 'pkgs <- c("XML", "RCurl", "GenomicRanges"); \
      BiocManager::install(pkgs, version = Sys.getenv("BIOC_VERSION"), ask = FALSE, update = FALSE); \
      missing <- setdiff(pkgs, rownames(installed.packages())); \
      if (length(missing) > 0) stop("failed to install: ", paste(missing, collapse = ", "))'

WORKDIR /app
RUN mkdir -p /xchip/tcga/Tools/absolute/releases/v1.5/
COPY v1.5/ /xchip/tcga/Tools/absolute/releases/v1.5/
COPY src/*.py /usr/local/bin/
COPY src/*.R /usr/local/bin/

# Entry points as commands on PATH.  The scripts carry no shebang, so they can
# only be run as `Rscript <file>` / `python <file>` -- which is how wolF invokes
# them, but not how an apptainer shim does (`apptainer exec <sif> <command>`).
# A shebang line is a comment to both R and python, so prepending one keeps the
# explicit-interpreter form working.
RUN set -eu; \
    for f in /xchip/tcga/Tools/absolute/releases/v1.5/run/ABSOLUTE_cli_start.R \
             /xchip/tcga/Tools/absolute/releases/v1.5/run/ABSOLUTE_extract_cli_start.R \
             /xchip/tcga/Tools/absolute/releases/v1.5/run/ABSOLUTE_cli_review.R; do \
      sed -i '1i #!/usr/bin/env Rscript' "$f"; \
      chmod +x "$f"; \
      ln -sf "$f" /usr/local/bin/"$(basename "$f")"; \
    done; \
    sed -i '1i #!/usr/bin/env Rscript' /usr/local/bin/get_CN_Absolute.Phylogic_SinglePatientTiming.R; \
    chmod +x /usr/local/bin/get_CN_Absolute.Phylogic_SinglePatientTiming.R; \
    sed -i '1i #!/usr/bin/env python3' /usr/local/bin/split_maf_indel_snp.py; \
    chmod +x /usr/local/bin/split_maf_indel_snp.py

# Smoke test.  The CLI entry points source() every .R in the library directory
# at start-up, so replaying that here turns an R-version incompatibility into a
# build failure instead of a run-time one.  The dir() call is kept identical to
# the one in run/ABSOLUTE_cli_start.R.
RUN Rscript -e 'suppressPackageStartupMessages({ \
        library(optparse); library(gplots); library(RColorBrewer); \
        library(plyr); library(GenomicRanges) }); \
      abs_lib_dir <- "/xchip/tcga/Tools/absolute/releases/v1.5"; \
      rr <- dir(abs_lib_dir, full.names = TRUE, pattern = "*.R"); \
      if (length(rr) == 0) stop("no ABSOLUTE sources found under ", abs_lib_dir); \
      for (i in 1:length(rr)) source(rr[i]); \
      cat("smoke test OK:", length(rr), "ABSOLUTE source files\n")'

RUN python /usr/local/bin/split_maf_indel_snp.py --help > /dev/null && \
    echo "python entry point OK"

# Every entry point must also resolve and run as a bare command on PATH.
RUN set -eu; \
    for cmd in ABSOLUTE_cli_start.R ABSOLUTE_extract_cli_start.R \
               ABSOLUTE_cli_review.R \
               get_CN_Absolute.Phylogic_SinglePatientTiming.R \
               split_maf_indel_snp.py; do \
      command -v "$cmd" > /dev/null || { echo "not on PATH: $cmd" >&2; exit 1; }; \
      "$cmd" --help > /dev/null || { echo "cannot exec: $cmd" >&2; exit 1; }; \
    done; \
    echo "PATH entry points OK"

# clear the build directory
RUN rm -rf /build/*
