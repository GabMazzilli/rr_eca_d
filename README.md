# Rzine Pipeline: ECA&D Precipitation Processing

This repository contains a reproducible data pipeline for the extraction, quality control, and temporal analysis of European daily climate datasets from the **ECA&D database**. 

## Quick Start (Plug & Play)

### 1. Configure Your Study Area
The pipeline automatically adapts to your specific region of interest.
1. Navigate to the `data/` directory.
2. Place your spatial geometry file there (a `.gpkg` file).
3. **Production**: Rename your file to `study_area.gpkg`.
4. **Testing**: You can use `study_area_test.gpkg` for rapid pipeline verification. The script will automatically prioritize the production file if both are present.

### 2. Initialize the Environment
Always open this project by double-clicking the **`rr_eca_d.Rproj`** file. 

### 3. Run the Pipeline
Open the master script **`run_all.R`** and execute it. It orchestrates the three processing modules in sequence:

1. **`01_climate_data_acquisition.R`**: Automated download and conversion of ECA&D files to `.parquet` format.
2. **`02_spatial_quality_temporal_step.R`**: Spatial intersection and chronological grid harmonization.
3. **`03_ref_trend_temporal_mask.R`**: Cascading quality masking and spatial coverage audits.

## Data Architecture
Generated results are stored in `data/outputs/`:
* `step_data/`: Clean climate series in `.parquet` format.
* `gis/`: Final validated station layers in `.geojson`.
* `tables/reports/`: Reference and trend auditing reports in `.csv`.

## Dependencies
This project requires: `arrow`, `sf`, `dplyr`, `tidyr`, `here`, `readr`, `stringr`, `purrr`

---
*Developed by Gabriel Mazzilli (2026), University of Lille (TVES Laboratory) for Rzine.*