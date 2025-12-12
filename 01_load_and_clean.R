# ===================================================================
# SWISS ELECTRICITY PRODUCTION ANALYSIS
# 03: LOAD, CLEAN, JOIN & NORMALIZE (FINAL SCRIPT)
#
# 1. Load BFE Solar Data (Installations)
# 2. Load Swisstopo Data (Commune Names & BFS IDs)
# 3. Load BFS Population Data (JSON)
# 4. Join all datasets to calculate kW per Capita.
# ===================================================================

# -------------------------------------------------------------------
# STEP 1: LOAD LIBRARIES
# -------------------------------------------------------------------
if(!require("readr")) install.packages("readr") # For reading CSV/delim files
if(!require("dplyr")) install.packages("dplyr") # For data manipulation
if(!require("lubridate")) install.packages("lubridate") # For working with dates
if(!require("jsonlite")) install.packages("jsonlite") # For parsing JSON
if(!require("stringr")) install.packages("stringr")   # For text/regex

library(readr)
library(dplyr)
library(lubridate)
library(jsonlite)
library(stringr)

# -------------------------------------------------------------------
# STEP 2: IMPORT BFE SOLAR DATA
# -------------------------------------------------------------------
bfe_file_path <- "Import BFE  Elektrizitätsproduktionsanlagen 31.10.25/ElectricityProductionPlant.csv"

print(paste("Reading BFE file from:", bfe_file_path))
all_plants_raw <- read_csv(bfe_file_path, locale = locale(encoding = "UTF-8"))

# Clean & filter for Solar GROWTH (2018-2024)
  solar_growth_clean <- all_plants_raw %>%
  filter(SubCategory == "subcat_2") %>% # Filter for Photovoltaic only [cite: 234, 235]
  mutate(operation_date = ymd(BeginningOfOperation)) %>%
  # *** CRITICAL FILTER: Start of 2018 to End of 2024 ***
  filter(operation_date >= "2018-01-01" & operation_date <= "2024-12-31") %>%
  select(PostCode, TotalPower)

print(paste("Solar data loaded. Installations in period:", nrow(solar_growth_clean)))

# -------------------------------------------------------------------
# STEP 3: IMPORT SWISSTOPO (FIXED: PRIORITIZE OFFICIAL INDEX)
# -------------------------------------------------------------------
swisstopo_file_path <- "Import Swisstopo/AMTOVZ_CSV_LV95.csv"

print("Reading Swisstopo lookup file...")
ortschaften_raw <- read_delim(swisstopo_file_path, delim = ";", locale = locale(encoding = "UTF-8"))

# FIX: Refined Logic for Shared PLZs
ortschaften_lookup <- ortschaften_raw %>%
  select(PLZ, Ortschaftsname, Gemeindename, `BFS-Nr`, Zusatzziffer, contains("Kanton")) %>% 
  rename(BFS_Nr = `BFS-Nr`, Canton = contains("Kanton")) %>%
  
  # Create Priority Column (for tie-breaking)
  mutate(Is_Main_Commune = (Ortschaftsname == Gemeindename)) %>%
  
  # *** THE FIX IS HERE ***
  # 1. Zusatzziffer (Ascending): Trust the official "Main" status first.
  #    (Fixes Champoz: Valbirse [2] beats Champoz [3])
  # 2. Is_Main_Commune (Descending): If indices are tied, use name match.
  #    (Fixes Mont-Tramelan: Mont-Tramelan [0] beats Tramelan [0])
  arrange(PLZ, Zusatzziffer, desc(Is_Main_Commune)) %>%
  
  # Lock in the single best match
  distinct(PLZ, .keep_all = TRUE) %>% 
  
  select(PLZ, Gemeindename, BFS_Nr, Canton)

print("Swisstopo lookup created (Logic: Index > Name Match).")


# -------------------------------------------------------------------
# STEP 4: IMPORT POPULATION DATA (JSON)
# -------------------------------------------------------------------
json_file_path <- "Import BFS Commune/px-x-0102020000_201.json"

print("Reading Population JSON...")
json_data <- fromJSON(json_file_path)

geo_dim_key <- "Kanton (-) / Bezirk (>>) / Gemeinde (......)"
geo_labels <- json_data$dataset$dimension[[geo_dim_key]]$category$label
values_list <- json_data$dataset$value

pop_raw <- data.frame(
  Label = unlist(geo_labels),
  Population = values_list,
  stringsAsFactors = FALSE
)

population_clean <- pop_raw %>%
  filter(str_starts(Label, "\\.\\.\\.\\.\\.\\.")) %>% 
  mutate(
    BFS_Nr = as.numeric(str_extract(Label, "(?<=\\.\\.\\.\\.\\.\\.)\\d{4}")),
    Commune_Name_Pop = str_trim(str_remove(Label, "\\.\\.\\.\\.\\.\\.\\d{4} "))
  ) %>%
  select(BFS_Nr, Population)

print("Population data extracted.")

# -------------------------------------------------------------------
# STEP 5: JOIN EVERYTHING & CALCULATE DEPENDENT VARIABLES
# -------------------------------------------------------------------

print("Joining datasets...")

# 5a. Join Solar Data to Swisstopo
solar_mapped <- solar_growth_clean %>%
  mutate(PostCode = as.numeric(PostCode)) %>% 
  left_join(ortschaften_lookup, by = c("PostCode" = "PLZ")) %>%
  filter(!is.na(BFS_Nr))

# 5b. Aggregate Solar GROWTH per Commune
solar_agg_commune <- solar_mapped %>%
  # Group by Canton as well to keep it!
  group_by(BFS_Nr, Gemeindename, Canton) %>%
  summarise(
    New_Solar_kW = sum(TotalPower, na.rm = TRUE),
    New_Installations_Count = n(),
    .groups = "drop"
  )

# 5c. Join with Population & Calculate Metrics
final_dataset <- solar_agg_commune %>%
  left_join(population_clean, by = "BFS_Nr") %>%
  mutate(
    # DV 1: New Capacity Density (Watts per Capita)
    New_Watts_per_Capita = (New_Solar_kW * 1000) / Population,
    
    # DV 2: Adoption Intensity (Installations per 1,000 inhabitants)
    Adoption_Intensity = (New_Installations_Count / Population) * 1000
  ) %>%
  filter(!is.na(Population)) %>%
  # Optional: Filter out tiny communes to avoid outliers (e.g., Pop < 100)
  filter(Population > 100)

print("Final dataset created.")
glimpse(final_dataset)

# -------------------------------------------------------------------
# STEP 6: ANALYSIS - THE NEW RANKINGS
# -------------------------------------------------------------------

# RANKING 1: By New Capacity Density (The "Power" Leaders)
# sorting by: New_Watts_per_Capita
top_capacity <- final_dataset %>%
  arrange(desc(New_Watts_per_Capita)) %>%
  select(Gemeindename, Canton, Population, New_Watts_per_Capita, Adoption_Intensity)

print("--- TOP 20: NEW CAPACITY DENSITY (Watts/Capita) ---")
print(head(top_capacity, 20))


# RANKING 2: By Adoption Intensity (The "Frequency" Leaders)
# sorting by: Adoption_Intensity
top_intensity <- final_dataset %>%
  arrange(desc(Adoption_Intensity)) %>%
  select(Gemeindename, Canton, Population, Adoption_Intensity, New_Watts_per_Capita)

print("--- TOP 20: ADOPTION INTENSITY (Installations/1000 ppl) ---")
print(head(top_intensity, 20))

# -------------------------------------------------------------------
# STEP 7: SAVE RESULTS
# -------------------------------------------------------------------
saveRDS(final_dataset, "solar_growth_2018_2024_final.rds")
write_csv(top_capacity, "ranking_by_capacity.csv")
write_csv(top_intensity, "ranking_by_intensity.csv")

print("Analysis complete. Both rankings saved.")


# -------------------------------------------------------------------
# STEP 8: VISUALIZATION
# -------------------------------------------------------------------
if(!require("ggplot2")) install.packages("ggplot2")
library(ggplot2)

# 1. Calculate National Statistics (Mean & Median)
stats_capacity <- final_dataset %>%
  summarise(
    Mean_Val = mean(New_Watts_per_Capita, na.rm = TRUE),
    Median_Val = median(New_Watts_per_Capita, na.rm = TRUE)
  )

stats_intensity <- final_dataset %>%
  summarise(
    Mean_Val = mean(Adoption_Intensity, na.rm = TRUE),
    Median_Val = median(Adoption_Intensity, na.rm = TRUE)
  )

print("National Statistics calculated.")
print(stats_capacity)
print(stats_intensity)


# 2. Plot 1: Top 20 New Capacity Density (Watts per Capita)
plot_capacity <- ggplot(head(top_capacity, 20), aes(x = reorder(Gemeindename, New_Watts_per_Capita), y = New_Watts_per_Capita)) +
  geom_bar(stat = "identity", fill = "#2E8B57") + # Green color
  coord_flip() + # Make bars horizontal for readability
  
  # Add Reference Lines for Average and Median
  geom_hline(aes(yintercept = stats_capacity$Mean_Val, linetype = "Average"), color = "blue", size = 1) +
  geom_hline(aes(yintercept = stats_capacity$Median_Val, linetype = "Median"), color = "red", size = 1) +
  
  # Labels and Titles
  labs(
    title = "Top 20 Communes: New Solar Capacity Growth (2018-2024)",
    subtitle = "Metric: Newly installed Watts per Capita",
    x = "Commune",
    y = "Watts per Capita",
    caption = "Red line: Median | Blue line: Average"
  ) +
  theme_minimal()

# Save Plot 1
ggsave("plot_top20_capacity.png", plot = plot_capacity, width = 10, height = 8)
print(plot_capacity)


# 3. Plot 2: Top 20 Adoption Intensity (Installations per 1000 people)
plot_intensity <- ggplot(head(top_intensity, 20), aes(x = reorder(Gemeindename, Adoption_Intensity), y = Adoption_Intensity)) +
  geom_bar(stat = "identity", fill = "#4682B4") + # Blue color
  coord_flip() +
  
  # Add Reference Lines for Average and Median
  geom_hline(aes(yintercept = stats_intensity$Mean_Val, linetype = "Average"), color = "darkblue", size = 1) +
  geom_hline(aes(yintercept = stats_intensity$Median_Val, linetype = "Median"), color = "red", size = 1) +
  
  # Labels and Titles
  labs(
    title = "Top 20 Communes: Solar Adoption Intensity (2018-2024)",
    subtitle = "Metric: Number of new installations per 1,000 inhabitants",
    x = "Commune",
    y = "Installations per 1,000 inhabitants",
    caption = "Red line: Median | Blue line: Average"
  ) +
  theme_minimal()

# Save Plot 2
ggsave("plot_top20_intensity.png", plot = plot_intensity, width = 10, height = 8)
print(plot_intensity)

print("Graphics saved to project folder.")

# -------------------------------------------------------------------
# STEP 9: UPDATE README.md AUTOMATICALLY
# -------------------------------------------------------------------
# This step adds the plot images to your README.md file so they show up on GitHub.

readme_path <- "README.md"
plot1_file <- "plot_top20_capacity.png"
plot2_file <- "plot_top20_intensity.png"

# Check if README exists
if (file.exists(readme_path)) {
  
  # Read the current content of the README
  readme_content <- readLines(readme_path)
  
  # Define the markdown text for the images
  img_markdown <- c(
    "",
    "## 📊 Preliminary Results (Top 20)",
    "",
    paste0("![Top 20 Capacity](", plot1_file, ")"),
    "",
    paste0("![Top 20 Intensity](", plot2_file, ")")
  )
  
  # Check if the images are already in the file to avoid duplicates
  if (!any(grepl(plot1_file, readme_content))) {
    
    # Append the new lines to the file
    cat(img_markdown, file = readme_path, sep = "\n", append = TRUE)
    print("Success: Plots added to README.md")
    
  } else {
    print("Info: Plots are already present in README.md. Skipping.")
  }
  
} else {
  print("Warning: README.md not found. Could not add plots.")
}