# Rzine Pipeline: ECA&D Precipitation Processing 🌧️

This repository contains a reproducible data pipeline for the extraction, quality control, and temporal analysis of European daily climate datasets from the **ECA&D database**. This protocol is designed to ensure full transparency and reproducibility for geographers and climatologists.

## Quick Start (Plug & Play)

### 1. Configure Your Study Area
The pipeline automatically adapts to your specific region of interest.
1. Navigate to the `data/study_area_folder/` directory.
2. Place your spatial geometry file there (a `.gpkg` file is highly recommended).
3. **IMPORTANT**: Rename your file exactly to `study_area.gpkg` so the pipeline can detect it automatically.

### 2. Initialize the Environment
Always open this project by double-clicking the **`rr_eca_d.Rproj`** file. RStudio will automatically set your working directory to the project root, ensuring all file paths function correctly without manual intervention.

### 3. Run the Pipeline
Open the master script **`run_all.R`** and execute it. This script orchestrates the three processing modules in sequence:

1. **`01_climate_data_acquisition.R`**: Automated download of the ECA&D source files and conversion from flat `.txt` to optimized `.parquet` format using `arrow`.
2. **`02_spatial_quality_temporal_step.R`**: Spatial intersection with your `study_area.gpkg` and chronological grid harmonization.
3. **`03_ref_trend_temporal_mask.R`**: Cascading quality masking (Monthly → Seasonal → Annual) and spatial coverage audits for trend analysis.

## Data Architecture
Generated results are stored in `data/outputs/`:
* `step_data/`: Clean climate series in `.parquet` format (Snappy compression).
* `gis/`: Final validated station layers in `.geojson`.
* `tables/reports/`: Reference and trend auditing reports in `.csv`.

## Dependencies
This project requires the following R packages:
`arrow`, `sf`, `dplyr`, `tidyr`, `here`, `readr`, `stringr`, `purrr`

---
*Developed by Gabriel Mazzilli (2026), University of Lille (TVES Laboratory) for Rzine.*