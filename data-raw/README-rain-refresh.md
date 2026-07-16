# Rain Refresh Workflow

This repo now includes a PRISM-based workflow for rebuilding the `rain`
dataset without changing the original `04-process_precip_data.R`.

## Overview

The new workflow has three steps:

1. Download only the PRISM daily precipitation files needed for storm windows
2. Aggregate each daily raster to county mean and county max precipitation,
   using county-boundary vintages matched to storm decade
3. Convert the county-day table into the storm-relative `rain` dataset

## Scripts

### 1. Download PRISM files

Script:

[`04a-download_prism_data.R`](/Users/ethanli/hurricaneexposuredata/data-raw/04a-download_prism_data.R)

What it does:

- Loads `closest_dist`
- Computes all unique dates needed from `closest_date - 5` through
  `closest_date + 3`
- Downloads missing PRISM daily precipitation zip files
- Saves them to `data-raw/cache/prism/ppt/`

Run:

```bash
R_LIBS="/Users/ethanli/hurricaneexposuredata/.r-lib:${R_LIBS}" Rscript data-raw/04a-download_prism_data.R
```

### 2. Aggregate PRISM rasters to counties

Script:

[`04b-aggregate_prism_to_counties.R`](/Users/ethanli/hurricaneexposuredata/data-raw/04b-aggregate_prism_to_counties.R)

What it does:

- Reads downloaded PRISM zip files one day at a time
- Extracts the `.tif`
- Selects the county-boundary vintage needed for each storm window:
  2000 boundaries for storms through 2009, 2010 boundaries for storms from
  2010 through 2019, and 2020 boundaries for storms from 2020 onward
- Computes county mean precipitation (`precip`)
- Computes county max precipitation (`precip_max`)
- Appends rows to `data-raw/prism_precip_export.txt`
- Deletes extracted files after each day to save disk space

Required R packages:

- `terra`
- `exactextractr`
- `sf`
- `tigris`
- `dplyr`
- `readr`

Install missing packages:

```r
install.packages(c("terra", "exactextractr"))
```

Run:

```bash
R_LIBS="/Users/ethanli/hurricaneexposuredata/.r-lib:${R_LIBS}" Rscript data-raw/04b-aggregate_prism_to_counties.R
```

### 3. Build the `rain` dataset

Script:

[`04c-process_prism_precip_data.R`](/Users/ethanli/hurricaneexposuredata/data-raw/04c-process_prism_precip_data.R)

What it does:

- Reads `data-raw/prism_precip_export.txt`
- Matches county-day precipitation to storm-relative lag windows
- Joins on `fips`, `year_month_day`, and `boundary_year` so each storm window
  uses the county-boundary vintage assigned in step 2
- Creates the final `rain` dataset with columns:
  - `fips`
  - `storm_id`
  - `usa_atcf_id`
  - `lag`
  - `precip`
  - `precip_max`
- Saves `data/rain_prism.rda`

Run:

```bash
R_LIBS="/Users/ethanli/hurricaneexposuredata/.r-lib:${R_LIBS}" Rscript data-raw/04c-process_prism_precip_data.R
```

## Intermediate File Format

The county-day table written by step 2 is:

```text
county,boundary_year,year_month_day,precip,precip_max
```

Example:

```text
01001,2020,20210827,0.0,0.0
01003,2020,20210827,1.2,4.5
```

## Notes

- This workflow uses PRISM daily precipitation rather than the original
  historical NLDAS/CDC WONDER export.
- The output format of `rain` is kept the same, but the precipitation source
  is different from the original package history.
- The PRISM workflow uses decennial Census cartographic boundary vintages
  matched to storm decade, mirroring the decennial population-center approach
  used in `closest_dist`.
- Census cartographic boundary files are generalized for mapping. Coastal
  county polygons can differ across vintages because of shoreline and water
  representation, which can affect county-average precipitation values.
- The new PRISM workflow assumes modern county FIPS codes and does not use the
  old Miami-Dade / Dade County `12025` workaround.
- Downloaded PRISM files are cached under `data-raw/cache/prism/`.
- Extracted raster files are deleted after aggregation to reduce disk usage.
