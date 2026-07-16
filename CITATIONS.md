# Citations

This repository extends Brooke Anderson and collaborators' original
`hurricaneexposuredata` package with more recent hurricane exposure data and
new PRISM-based rainfall data.

## Citing This Updated Repository

If you use the updated data in this repository, please cite this fork:

Li E, Nguyen J, Sanghavi P, and Burrows K, based on work by Anderson B, Schumacher A, Crosson W, Al-Hamdan M,
Yan M, Ferreri J, Chen Z, Quiring S, and Guikema S. hurricaneexposuredata:
Data Characterizing Exposure to Hurricanes in United States Counties.
R package version 0.1.3. https://doi.org/10.5281/zenodo.21249129

Development repository: https://github.com/ethanqli/hurricaneexposuredata

In R, users can also run:

```r
citation("hurricaneexposuredata")
```

For reproducible analyses, cite the version-specific Zenodo DOI for the
release you used when available.

## Original Package

This repository is a fork of the original `hurricaneexposuredata` package
developed by Brooke Anderson and collaborators. Please cite the original
repository when using data, code, documentation, or methods inherited from
that work:

Anderson B, Schumacher A, Crosson W, Al-Hamdan M, Yan M, Ferreri J, Chen Z,
Quiring S, and Guikema S. hurricaneexposuredata: Data Characterizing Exposure
to Hurricanes in United States Counties. R package version 0.1.0.
https://github.com/geanders/hurricaneexposuredata

## PRISM-Based Rainfall Data

The new PRISM-based rainfall data in this repository were derived from daily
precipitation rasters from the PRISM Climate Group at Oregon State University.
These data were aggregated to county-day precipitation summaries and then
matched to storm-relative lag windows.

Please cite PRISM when using PRISM-derived rainfall datasets from this
repository, including `rain_prism` and related PRISM rain outputs:

PRISM Climate Group, Oregon State University. PRISM gridded climate data.
https://prism.oregonstate.edu

Daly C, Halbleib M, Smith JI, Gibson WP, Doggett MK, Taylor GH, Curtis J, and
Pasteris PP. 2008. Physiographically sensitive mapping of climatological
temperature and precipitation across the conterminous United States.
International Journal of Climatology 28(15):2031-2064.
https://doi.org/10.1002/joc.1688

## Other Data Sources

Dataset-specific source and reference information is documented in the package
help pages generated from `R/data.R`. These include sources for HURDAT2 storm
tracks, U.S. Census county population centers, NOAA Storm Events, modeled wind
exposure data, and the legacy NLDAS/CDC WONDER rainfall data.
