# --- 0. Load Libraries ---
# Ensure all necessary libraries are loaded at the beginning.
if (!requireNamespace("sf", quietly = TRUE)) install.packages("sf")
if (!requireNamespace("elevatr", quietly = TRUE)) install.packages("elevatr")
if (!requireNamespace("dplyr", quietly = TRUE)) install.packages("dplyr")
if (!requireNamespace("ggplot2", quietly = TRUE)) install.packages("ggplot2")
if (!requireNamespace("ggshadow", quietly = TRUE)) install.packages("ggshadow") # Note: ggshadow might require installation from GitHub if not on CRAN
if (!requireNamespace("geosphere", quietly = TRUE)) install.packages("geosphere")

library(sf)
library(elevatr)
library(dplyr)
library(ggplot2)
library(ggshadow)
library(geosphere)

# --- 1. Process Command-Line Arguments ---
# This section retrieves coordinates passed when running the script.
# Usage: Rscript elevationProfileR.R start_lon start_lat end_lon end_lat output_filename.png
args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 4) {
    stop("Usage: Rscript mountain_profile.R <start_lon> <start_lat> <end_lon> <end_lat> [output_filename.png]", call. = FALSE)
}

start_lon <- as.numeric(args[1])
start_lat <- as.numeric(args[2])
end_lon <- as.numeric(args[3])
end_lat <- as.numeric(args[4])

# Optional: Get output filename from command line, otherwise use a default
output_filename <- "elevation_profile.png"
if (length(args) >= 5) {
    output_filename <- args[5]
}

if (any(is.na(c(start_lon, start_lat, end_lon, end_lat)))) {
    stop("Error: Coordinates must be numeric values.", call. = FALSE)
}

cat("Starting script with the following parameters:\n")
cat("Start Longitude:", start_lon, "\n")
cat("Start Latitude:", start_lat, "\n")
cat("End Longitude:", end_lon, "\n")
cat("End Latitude:", end_lat, "\n")
cat("Output Filename:", output_filename, "\n\n")

# --- Step 1 ---
cat("--- Step 1: Defining Path and Sampling Points ---\n")

# Define the start and end points from command-line arguments
start_point <- c(start_lon, start_lat)
end_point <- c(end_lon, end_lat)

geodetic_distance <- distm(start_point, end_point, fun = distGeo)
geodetic_distance <- round(geodetic_distance, 2)
cat("Calculated Geodetic Distance:", geodetic_distance, "meters\n")

# Create the LINESTRING
path_line <- st_sfc(st_linestring(rbind(start_point, end_point)), crs = 4326)

# Generate 1000 points along the line
points_on_path <- st_sample(path_line, size = 1000, type = "regular")

# Convert to sf object
points_sf_initial <- st_as_sf(points_on_path)

# --- Add Check and Correction Step ---
initial_geom_type <- st_geometry_type(points_sf_initial, by_geometry = FALSE)[1] # Ensure single value
initial_rows <- nrow(points_sf_initial)
cat("Initial object has", initial_rows, "row(s) and geometry type:", initial_geom_type, "\n")

if (initial_rows == 1 && initial_geom_type == "MULTIPOINT") {
    cat("Detected single MULTIPOINT feature. Casting to individual POINTs...\n")
    points_sf <- st_cast(points_sf_initial, "POINT")
    cat("After casting, object has", nrow(points_sf), "rows and geometry type:", st_geometry_type(points_sf, by_geometry=FALSE)[1], "\n")
} else if (initial_rows > 1 && initial_geom_type == "POINT") { # Handles cases where st_sample directly returns multiple POINTs
    cat("Initial object structure appears correct (multiple POINTs).\n")
    points_sf <- points_sf_initial
} else if (initial_rows == 1000 && initial_geom_type == "GEOMETRYCOLLECTION" && st_geometry_type(st_collection_extract(points_sf_initial, "POINT"), by_geometry = FALSE)[1] == "POINT"){
    cat("Initial object is a GEOMETRYCOLLECTION, attempting to extract POINTs...\n")
    points_sf <- st_collection_extract(points_sf_initial, "POINT")
    if (nrow(points_sf) == 1 && st_geometry_type(points_sf, by_geometry = FALSE)[1] == "MULTIPOINT") {
        cat("Extracted MULTIPOINT, casting to individual POINTs...\n")
        points_sf <- st_cast(points_sf, "POINT")
    }
    cat("After processing GEOMETRYCOLLECTION, object has", nrow(points_sf), "rows and geometry type:", st_geometry_type(points_sf, by_geometry=FALSE)[1], "\n")
} else {
    warning(paste("The structure of the sampled points object is unexpected:", initial_rows, "rows, type", initial_geom_type, ". Proceeding, but errors may occur."))
    points_sf <- points_sf_initial
}


# --- Calculate Distances ---
cat("Calculating distances from start point to sampled points...\n")
start_sfc <- st_sfc(st_point(start_point), crs = 4326)

distances <- st_distance(points_sf, start_sfc)

cat("Dimensions of the 'distances' matrix:", dim(distances), "\n")

expected_rows <- nrow(points_sf)
if (is.null(dim(distances)) || nrow(distances) != expected_rows || ncol(distances) != 1) {
    stop(paste0("FATAL ERROR: Distance matrix has unexpected dimensions: ",
                paste(dim(distances), collapse=" x "),
                ". Expected: ", expected_rows, " x 1. Check the structure after potential casting."))
} else {
    cat("Distance matrix dimensions are correct. Proceeding...\n")
}

points_sf$distance_m <- as.numeric(distances[, 1])

cat("First few rows of points_sf including calculated distance_m:\n")
print(head(points_sf))
cat("\n--- End of Step 1 ---\n\n")

# --- Step 2 (from step2.R) ---
cat("--- Step 2: Fetching Elevation Data ---\n")

# Fetch elevation data for the points
coords_df <- as.data.frame(st_coordinates(points_sf))
names(coords_df) <- c("x", "y")

cat("Fetching elevation data for", nrow(coords_df), "points. This may take a moment...\n")
# Using tryCatch to handle potential errors during elevation data fetching
elevation_data <- NULL
tryCatch({
    elevation_data <- get_elev_point(coords_df, prj = 4326, src = "aws", z = 14) # Using AWS Terrain Tiles
    cat("Elevation data fetched successfully.\n")
}, error = function(e) {
    stop(paste("Error fetching elevation data with get_elev_point:", e$message), call. = FALSE)
})

# Check if elevation_data is NULL (in case get_elev_point failed silently, though it usually errors out)
if (is.null(elevation_data) || nrow(elevation_data) == 0) {
    stop("Failed to retrieve elevation data or no data was returned.", call. = FALSE)
}

# Merge elevation data with points_sf. get_elev_point returns an sf object.
# We need to make sure we are merging correctly.
# It should already have the coordinates, so we can add distance_m from points_sf.
# A safer way is to bind columns if row order is guaranteed, or merge by coordinates.
# Given points_sf was the input to get_elev_point (via coords_df),
# the row order should be preserved.

# Add the distance column from points_sf to elevation_data
# Ensure elevation_data is an sf object and has the same number of rows as points_sf
if (!inherits(elevation_data, "sf")) {
    stop("elevation_data is not an sf object as expected.", call. = FALSE)
}
if (nrow(elevation_data) != nrow(points_sf)) {
    stop(paste("Row mismatch between points_sf (", nrow(points_sf), ") and elevation_data (", nrow(elevation_data), "). Cannot reliably merge distance.", sep=""), call. = FALSE)
}
elevation_data$distance_m <- points_sf$distance_m


cat("First few rows of elevation_data (with distance_m added):\n")
print(head(elevation_data))

# Convert sf object to a regular data frame for ggplot
profile_df <- as.data.frame(st_drop_geometry(elevation_data))

# Add position_index (based on original sampling order)
profile_df <- profile_df %>%
    mutate(position_index = row_number())

# The column from get_elev_point is typically named 'elevation'
# Ensure 'elevation' column exists
if (!"elevation" %in% names(profile_df)) {
    # Sometimes, depending on the source or version, it might be named differently e.g. 'elev_M'.
    # Add a check or try to find a likely candidate.
    # For 'aws' source, it's typically 'elevation'.
    potential_elev_cols <- names(profile_df)[grepl("elev", names(profile_df), ignore.case = TRUE)]
    if (length(potential_elev_cols) == 1) {
        cat(paste("Note: 'elevation' column not found, using '", potential_elev_cols[1], "' as elevation data.\n", sep=""))
        names(profile_df)[names(profile_df) == potential_elev_cols[1]] <- "elevation"
    } else {
        stop("Error: 'elevation' column not found in the data frame from get_elev_point. Available columns: ", paste(names(profile_df), collapse=", "), call. = FALSE)
    }
}

cat("First few rows of profile_df for plotting:\n")
print(head(profile_df))
cat("\n--- End of Step 2 ---\n\n")

# --- Step 3 (from step3.R) ---
cat("--- Step 3: Creating and Saving Plot ---\n")

# Rename the 'elevation' column for the plot label if desired
# For clarity, let's ensure the column is what ggplot expects or rename it.
if ("elevation" %in% names(profile_df)) {
    names(profile_df)[names(profile_df) == "elevation"] <- "elevation_meters" # Renaming to avoid space for safety
} else {
    stop("Column 'elevation' (or its renamed version) not found in profile_df for plotting.", call. = FALSE)
}


# Define some bright, fluorescent-like colors
color1 <- "black"
color2 <- "#FF0000" # Bright Red (was Cyan, but #FF0000 is Red)
# color3 <- "#7FFF00" # Bright Chartreuse/Lime (commented out in original)
neon_axis_color <- "#39ff14" # Neon Green for the Y-axis text/title

# List of potential glowline colors provided by the user
glow_colors <- c(
    "#FF00FF", "#FF00CC", "#7FFF00", "#FFFF33", "#00F6FF", "#0052FF",
    "#FF8C00", "#FF5F00", "#FF0000", "#BF00FF", "#8A2BE2", "#9400D3"
)

# --- Randomly select one color for the glowline ---
# Each run of Rscript is a new session, so sample() will produce a different result
# without needing to explicitly set a seed with set.seed(NULL) in most cases.
selected_glow_color <- sample(glow_colors, 1)
cat("Randomly selected glowline color for this run:", selected_glow_color, "\n")

# The 'color2' variable will now be this randomly selected glow_color for the glowline
color2 <- selected_glow_color

# Create the plot
profile_plot <- ggplot(profile_df, aes(x = position_index, y = elevation_meters)) +
    geom_area(fill = color1, alpha = 0.2) +
    geom_glowline(color = color2, linewidth = 0.6, alpha = 0.4) +
    scale_y_continuous(expand = expansion(mult = c(0, 0.05))) +
    scale_x_continuous(expand = expansion(mult = c(0, 0))) +
    theme(
        plot.background = element_rect(fill = "#1a1a1a", color = NA),
        panel.background = element_rect(fill = "#1a1a1a", color = NA),
        panel.grid.major = element_blank(),
        panel.grid.minor = element_blank(),
        plot.title = element_text(color = "white", hjust = 0.5, size=16, face="bold"),
        axis.title.y = element_text(color = neon_axis_color, size = 7, face = "bold", angle = 90, vjust = 0.5),
        axis.text.y = element_text(
            color = neon_axis_color, size = 7, face = "bold",
            margin = margin(t = 0, r = 2, b = 0, l = 0, unit = "pt")
        ),
        axis.ticks.y = element_line(color = neon_axis_color, linewidth=0.5),
        axis.title.x = element_text(color = neon_axis_color, size = 7, face = "bold", angle = 0, vjust = -0.5), # Adjusted vjust for spacing
        axis.text.x = element_blank(),
        axis.ticks.x = element_blank(),
        axis.line.x = element_blank(),
        plot.margin = margin(t = 5, r = 5, b = 20, l = 5, unit = "pt") # Increased bottom margin for x-axis title
    ) +
    labs(
        # title = "Pichincha Elevation Profile (West-East)", # Title can be dynamic if needed
        x = paste0("Geodesic distance = ", geodetic_distance, " m (Path sampled at ", nrow(profile_df) ," points)"),
        y = "Elevation (m)"
    )

# Display the plot (optional when running from command line, as it's saved)
# print(profile_plot)

# Save the plot
ggsave(output_filename, plot = profile_plot,
       width = 16.18, height = 10, dpi = 300, bg = "#1a1a1a")

cat(paste("\nPlot successfully saved as", output_filename, "\n"))
cat("--- End of Step 3 ---\n")
cat("Script finished.\n")