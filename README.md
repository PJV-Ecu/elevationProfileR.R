# R Script for Generating Stylized Elevation Profiles

This script was created with the assistance of Gemini Advanced Pro.

This repository contains an R script that generates stylized elevation profile plots between any two geographical coordinates (in decimal degrees). The script leverages several R packages to fetch real-world elevation data and create a visually appealing plot with a dark theme and a neon glow effect. The script will print the provided name for the mountain profile or, if not given such a name, will proceed to find the highest point on the profile and attempt to use the tidygeocoder package to get its geographical name from OpenStreetMap.

It is designed to be run from the command line, making it easy to integrate into automated workflows or use for generating multiple profiles quickly.

## Syntax
Rscript elevationProfileR.R <start_lon> <start_lat> <end_lon> <end_lat> [output_filename.png] [\"Terrain Name\"]"

## Output example (the central text is post-edited)

`Rscript elevationProfileR.R -78.187286 -0.484717 -78.083248 -0.484717 antizana.png`

![antisana_profile_fluorescent](https://github.com/user-attachments/assets/84001a66-5104-4f6b-b9ce-97b6926a4ee6)

## Features
Dynamic Profile Generation: Creates an elevation profile between any start and end coordinates (longitude/latitude).
Real-World Data: Fetches maximum-resolution elevation data from Amazon Web Services (AWS) Terrain Tiles using the elevatr package.
High-Quality Visuals: Uses ggplot2 and ggshadow to produce a modern, high-resolution plot with a "glowline" effect.
Customizable Aesthetics: The script features a dark theme with neon-colored axes and a randomly selected vibrant color for the glowline in each run.
Informative Output: The final plot includes the total geodetic distance of the path.
Command-Line Driven: Easily scriptable with coordinates and an output filename passed as arguments.

## How It Works
The script operates in three main steps:

Path Definition: It takes the start and end coordinates and creates an sf LINESTRING object. It then samples a large number of points (1000) along this path to ensure a detailed profile.
Elevation Fetching: For each point sampled along the path, it calls the get_elev_point() function from the elevatr package to retrieve its elevation.
Plot Generation: It uses ggplot2 to plot the elevation against the distance along the path. A custom theme creates the dark background and neon text, while ggshadow::geom_glowline adds the signature glowing line effect. The completed plot is then saved to a file.
Requirements
You will need R installed on your system. The script depends on the following R packages:\

-sf\
-elevatr\
-dplyr\
-ggplot2\
-ggshadow\
-geosphere

The script includes a check to automatically install these packages if they are not already present.

## Usage
Clone this repository or download the elevationProfileR.R script.
Open your terminal or command prompt.
Navigate to the directory where you saved the script.
Run the script using the Rscript command, providing the coordinates and an optional output filename.
