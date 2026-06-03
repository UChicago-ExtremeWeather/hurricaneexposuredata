# Legacy NLDAS Rain vs. New PRISM Rain

This note explains the difference between the package's legacy rain workflow
and the new PRISM-based rain workflow added in this repo.

## Short Version

- The legacy approach builds `rain` from a precomputed county-day export in
  `data-raw/nasa_precip_export_2.txt`.
- The new approach builds PRISM-based rain data directly from daily PRISM
  precipitation rasters using the scripts `04a` through `04c`.
- Both approaches produce the same storm-relative output shape:
  `fips`, `storm_id`, `usa_atcf_id`, `lag`, `precip`, `precip_max`.
- The important change is the precipitation source and the way county-day
  precipitation is constructed before it is matched to storm windows.

## Legacy Approach

Script:

- `data-raw/04-process_precip_data.R`

Data source:

- A previously prepared county-day precipitation file,
  `data-raw/nasa_precip_export_2.txt`
- As documented in `R/data.R`, the package's original `rain` dataset is based
  on North America Land Data Assimilation System Phase 2 (NLDAS-2) daily
  precipitation data distributed through CDC WONDER
- Per the CDC WONDER website, daily precipitation measurements are recorded on
  `1/8`-degree geographic-area grids, then assigned to counties based on the
  county containing the grid centroid; if a county is so small that it has no
  grid centroids, the value from the grid covering the greatest county area is
  assigned to that county

How it works:

1. Load `closest_dist`
2. Expand each county-storm pair to lag days from 5 days before through
   3 days after closest approach
3. Read the pre-aggregated county-day precipitation export
4. Filter that export to the needed counties and dates
5. Join county-day precipitation onto the storm-relative lag table
6. Save the final `rain` dataset

Characteristics:

- Fast once the export file already exists
- Depends on an external intermediate file that is not rebuilt in this script
- Uses historical county-day values that were already aggregated before they
  enter the repo workflow
- Uses CDC WONDER's county assignment logic rather than recomputing county
  summaries directly from raw gridded precipitation inside this repo
- Includes a legacy Miami-Dade handling step by mapping modern FIPS `12086`
  to historic `12025` during the join and then mapping it back afterward

## New PRISM Approach

Scripts:

- `data-raw/04a-download_prism_data.R`
- `data-raw/04b-aggregate_prism_to_counties.R`
- `data-raw/04c-process_prism_precip_data.R`

Data source:

- Daily PRISM precipitation rasters downloaded for the exact dates needed by
  the storm windows

How it works:

1. Load `closest_dist`
2. Compute the unique calendar dates needed for all lag windows
3. Download missing PRISM daily precipitation files into
   `data-raw/cache/prism/ppt/`
4. Aggregate each daily raster to county mean precipitation (`precip`) and
   county max precipitation (`precip_max`)
5. Write that county-day table to `data-raw/prism_precip_export.txt`
6. Join the county-day PRISM values back to the storm-relative lag table
7. Save the final PRISM-based dataset

Characteristics:

- Rebuilds county-day precipitation from gridded rasters inside the repo
  workflow
- Uses `terra` and `exactextractr` to aggregate raster cells to counties
- Caches raw downloads and removes extracted temporary raster files after use
- Uses modern county FIPS directly and does not apply the old `12025`
  Miami-Dade workaround

## Main Differences

### 1. Precipitation source

- Legacy: NLDAS-2 county-day precipitation from the prebuilt export used by
  the package's historical workflow
- New: PRISM daily precipitation rasters aggregated to counties in this repo

### 2. Reproducibility path

- Legacy: the script assumes the export file already exists on the machine
- New: the workflow documents how to download, aggregate, and rebuild the
  county-day input from source rasters

### 3. County aggregation step

- Legacy: county aggregation happened upstream before the repo script runs.
  Per the CDC WONDER website, NLDAS daily precipitation is first associated to
  counties by grid centroid, with a fallback for very small counties that do
  not contain any grid centroids.
- New: county aggregation is part of the repo workflow and is visible in
  `04b-aggregate_prism_to_counties.R`, where PRISM raster cells intersecting a
  county are summarized directly to county mean precipitation (`precip`) and
  county max precipitation (`precip_max`).

### 4. How county assignment differs

- Legacy NLDAS / CDC WONDER: each grid's precipitation value is assigned to a
  county using the grid centroid location, and WONDER then aggregates those
  grid-level measurements into county summaries.
- New PRISM workflow: county summaries are built from raster cells that
  intersect the county geometry during the repo's aggregation step, rather than
  relying on a prebuilt centroid-based county assignment from WONDER.

### 5. County identifier handling

- Legacy: special handling for Miami-Dade / historic Dade County codes
- New: modern county FIPS are used as-is

### 6. Why this branch uses PRISM

- The historical CDC WONDER county-day NLDAS product used by the package is no
  longer freely available in the same way for rebuilding the dataset from
  source.
- We therefore chose PRISM so the rainfall workflow can be reproduced from
  downloadable daily raster files within the repo's documented pipeline.
- The goal is to preserve a rain dataset with the same storm-relative output
  structure while replacing the unavailable legacy upstream source with a
  reproducible alternative.

### 7. Output naming

- Legacy package dataset: `rain`
- New dataset in this branch: `rain_prism`

The PRISM datasets were kept separate so the repo can compare them with the
legacy `rain` dataset before replacing historical package behavior.

## What Stays the Same

- Storm windows are still anchored to `closest_dist`
- Lag days still run from `-5` through `+3`
- Output columns remain compatible with the legacy `rain` structure
- The final tables can still be joined to storm and county analyses using the
  same identifying fields

## Comparing the Outputs

Script:

- `data-raw/04d-compare_rain_datasets.R`

Outputs:

- `data-raw/rain_comparison/overview.csv`
- `data-raw/rain_comparison/metric_table.csv`
- `data-raw/rain_comparison/difference_quantiles.csv`
- `data-raw/rain_comparison/storm_summary.csv`
- `data-raw/rain_comparison/year_summary.csv`
- `data-raw/rain_comparison/county_summary.csv`
- `data-raw/rain_comparison/largest_examples.csv`

Use these files when you want to quantify how much the PRISM-based rain values
depart from the legacy NLDAS-based values for the overlapping storms, counties,
and lag days.
