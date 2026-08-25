# ABSOLUTE

Estimate tumor purity, ploidy, and absolute copy number from a copy number segmentation.

Publication: [Absolute quantification of somatic DNA alterations in human cancer (Carter et al. 2012)](https://doi.org/10.1038/nbt.2203).

[This page on the GenePattern website contains some helpful information as well.](https://www.genepattern.org/analyzing-absolute-data#gsc.tab=0)

## High-level concepts

ABSOLUTE receives the following inputs:

* Segmented, smoothed (relative) copy number profiles
    - I.e., from HapASeg or AllelicCapSeg
* Somatic point mutations with their allelic fractions

ABSOLUTE uses these as evidence to infer the following quantities:

* Tumor purity
* Tumor ploidy
* Absolute copy numbers for genome segments

## Outputs from ABSOLUTE


The ABSOLUTE R script (`ABSOLUTE_cli_start.R`) outputs the following files:

* `*.ABSOLUTE_plot.pdf`. Plots of ABSOLUTE candidate solutions
* `*.PP-modes.data.RData`. RData file containing candidate solutions

Once a candidate solution is chosen, the "extractor" script (`ABSOLUTE_extract_cli_start.R`) can produce the following outputs:
* `{sample_name}_ABS_MAF.txt`
* `{sample_name}.segtab.txt`
* `{sample_name}.ABSOLUTE.{analyst_id}.called.RData`
    - RData file containing a list of candidate ABSOLUTE solutions
* `{sample_name}.{analyst_id}.ABSOLUTE.table.txt`
    - Contains purities and ploidies. Analyst can edit this file with manual annotations in order to


---

# Addendum: container build

> Everything above this line is unmodified upstream text from
> [`getzlab/ABSOLUTE`](https://github.com/getzlab/ABSOLUTE). Everything below
> was added in this fork.

## Building the container

```
docker build \
  --build-arg HTTP_PROXY="$HTTP_PROXY" \
  --build-arg HTTPS_PROXY="$HTTPS_PROXY" \
  --build-arg http_proxy="$http_proxy" \
  --build-arg https_proxy="$https_proxy" \
  -t absolute:v1.5 .
```

The proxy `--build-arg` flags are only needed behind an HTTP proxy; drop them
otherwise.

`deploy.sh` builds the same image and pushes it to GCR, deriving the tag from
the branch name and the commit count. Run it from `master`: on a branch whose
name contains a `/`, the tag it generates is not a valid docker reference and
the build fails immediately.

### Pinned versions

Three things are pinned together and cannot be changed independently:

| | |
|---|---|
| Base image | `gcr.io/broad-getzlab-workflows/base_image:v0.0.4` (Ubuntu 20.04) |
| R | 3.6.3, from focal |
| CRAN / Bioconductor | Posit Package Manager snapshot `2020-06-01` / Bioconductor `3.10` |

Current CRAN installs a `BiocManager` that only serves Bioconductor releases
requiring R >= 4.4, which cannot install `GenomicRanges` under R 3.6.3 — hence
the snapshot. Moving to a newer R means moving all three.

The base image carries apt package lists frozen at 2021-04, so `apt-get update`
must stay in the **same `RUN` instruction** as `apt-get install`. Split across
two layers, a cached update layer resolves package versions that have since
been superseded in the pool, and every download fails with a 404.

### Build-time checks

The build fails rather than producing a broken image when:

* an R package silently fails to install (`install.packages()` only warns);
* any ABSOLUTE source file cannot be `source()`d the way the CLI entry points do
  at start-up;
* an entry point does not resolve on `PATH`, or resolves but cannot be executed.

### Entry points

Each of these works both as a bare command and with an explicit interpreter:

| Command | File |
|---|---|
| `ABSOLUTE_cli_start.R` | `v1.5/run/ABSOLUTE_cli_start.R` |
| `ABSOLUTE_extract_cli_start.R` | `v1.5/run/ABSOLUTE_extract_cli_start.R` |
| `ABSOLUTE_cli_review.R` | `v1.5/run/ABSOLUTE_cli_review.R` |
| `get_CN_Absolute.Phylogic_SinglePatientTiming.R` | `src/` |
| `split_maf_indel_snp.py` | `src/` |

The ABSOLUTE library itself is not an R package; the entry points `source()`
every `.R` file under `--abs_lib_dir`, which the image places at
`/xchip/tcga/Tools/absolute/releases/v1.5`.

### Apptainer / Singularity

```
apptainer build absolute_v1.5.sif docker-daemon://absolute:v1.5
```

The conversion unpacks the whole image, so point `APPTAINER_TMPDIR` at a
filesystem with several GB free if `/tmp` is small.

To check a built image or SIF:

```
for cmd in ABSOLUTE_cli_start.R ABSOLUTE_extract_cli_start.R \
           ABSOLUTE_cli_review.R \
           get_CN_Absolute.Phylogic_SinglePatientTiming.R \
           split_maf_indel_snp.py; do
  apptainer exec absolute_v1.5.sif "$cmd" --help > /dev/null \
    && echo "OK   $cmd" || echo "FAIL $cmd"
done
```
