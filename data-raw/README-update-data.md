# Updating the Data

This guide explains how to update the package data when a newer HURDAT2 file
or newer rainfall/event data become available.

Most storm-track updates start by replacing the HURDAT2 URL. After that, the
derived `.rda` data files must be rebuilt by rerunning the scripts below in
order.

## 1. Update the HURDAT2 URL

Replace the HURDAT2 URL in both of these files:

- `data-raw/02-clean_hurr_tracks.R`
- `data-raw/07-process_wr_tracks.R`

Look for lines like:

```r
hurdat2 <- read_lines("https://www.nhc.noaa.gov/data/hurdat/hurdat2-1851-2025-02272026.txt")
```

Replace the URL with the newest Atlantic HURDAT2 file from the National
Hurricane Center.

Also update any nearby comments that say when the file was current.

## 2. Rebuild Hurricane Tracks

Run:

```bash
Rscript data-raw/02-clean_hurr_tracks.R
```

This rebuilds:

- `data/hurr_tracks.rda`

After this step, reinstall or reload the package so later scripts use the new
`hurr_tracks` object:

```bash
R CMD INSTALL .
```

## 3. Rebuild Closest Distances and Excluded Tracks

Run:

```bash
Rscript data-raw/03-calculate_closest_distance.R
```

This rebuilds:

- `data/closest_dist.rda`
- `data/hurr_tracks.rda`
- `data/excluded_tracks.rda`

This script filters `hurr_tracks` to storms that came within 250 km of at
least one county. Storms that do not meet this criterion are moved into
`excluded_tracks`.

After this step, reinstall or reload the package again:

```bash
R CMD INSTALL .
```

## 4. Rebuild PRISM-Based Rainfall Data

The PRISM rainfall workflow depends on `closest_dist`, so rerun it after
updating HURDAT2 and closest distances.

Run:

```bash
Rscript data-raw/04a-download_prism_data.R
Rscript data-raw/04b-aggregate_prism_to_counties.R
Rscript data-raw/04c-process_prism_precip_data.R
```

These scripts:

- compute the storm-relative dates needed from `closest_dist`
- download missing PRISM daily precipitation rasters
- aggregate PRISM rasters to county-day precipitation summaries
- rebuild the PRISM rain dataset

The current processing script writes:

- `data/rain_prism_wonder.rda`

For more detail, see:

- `data-raw/README-rain-refresh.md`
- `data-raw/README-rain-differences.md`

## 5. Rebuild Wind Data

Run:

```bash
Rscript data-raw/05-calc_windmodel_data.R
```

This rebuilds:

- `data/storm_winds.rda`

Then run:

```bash
Rscript data-raw/07-process_wr_tracks.R
```

This rebuilds:

- `data/ext_tracks_wind.rda`

`07-process_wr_tracks.R` reads HURDAT2 directly, so its HURDAT2 URL must match
the URL used in `02-clean_hurr_tracks.R`.

## 6. Rebuild Storm Events

Run:

```bash
Rscript data-raw/06-process_events_data.R
```

This rebuilds:

- `data/storm_events.rda`

This script downloads NOAA Storm Events files by storm year, based on the
updated storms in `hurr_tracks` and the updated county-storm distances in
`closest_dist`.

## 7. Usually Not Needed

You usually do not need to rerun:

```bash
Rscript data-raw/01-clean_county_centers.R
```

Only rerun it if you intentionally want to change the county center source or
geography vintage.

## 8. Refresh Package Documentation

After rebuilding data, update documentation:

```r
devtools::document()
```

If the README changed, rebuild it from `README.Rmd`:

```r
rmarkdown::render("README.Rmd")
```

Then run package checks:

```r
devtools::check()
```

## Summary Order

For a standard HURDAT2 update, run:

```bash
Rscript data-raw/02-clean_hurr_tracks.R
R CMD INSTALL .
Rscript data-raw/03-calculate_closest_distance.R
R CMD INSTALL .
Rscript data-raw/04a-download_prism_data.R
Rscript data-raw/04b-aggregate_prism_to_counties.R
Rscript data-raw/04c-process_prism_precip_data.R
Rscript data-raw/05-calc_windmodel_data.R
Rscript data-raw/06-process_events_data.R
Rscript data-raw/07-process_wr_tracks.R
```

Before committing, check that the regenerated files in `data/` are the files
you expected to change.
