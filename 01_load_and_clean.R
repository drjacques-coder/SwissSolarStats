# ===================================================================
# SWISS ELECTRICITY PRODUCTION ANALYSIS
# 01: LOAD AND CLEAN DATA
#
# This script imports the official dataset of all Swiss electricity
# production plants, then filters it to focus on solar panel
# installations up to the end of 2024.
# ===================================================================


# -------------------------------------------------------------------
# STEP 1: LOAD LIBRARIES
# -------------------------------------------------------------------

# We will use a few key packages for this analysis.
# If you don't have them, R will install them.
if(!require("readr")) install.packages("readr")     # For reading CSV files quickly
if(!require("dplyr")) install.packages("dplyr")     # For data manipulation (filter, group, etc.)
if(!require("lubridate")) install.packages("lubridate") # For working with dates

# Load the libraries into our R session
library(readr)
library(dplyr)
library(lubridate)
# -------------------------------------------------------------------
# STEP 2: IMPORT DATA (MANUAL)
# -------------------------------------------------------------------
# Load the main data file from its folder

# This is the path *relative* to your RStudio Project file.
data_folder_path <- "Import BFE  Elektrizitätsproduktionsanlagen 31.10.25/"

# This is the main data file you found
main_file_name <- "ElectricityProductionPlant.csv"

# **NOTE**: This is the corrected path.
# It includes TWO spaces between "BFE" and "Elektrizitätsproduktionsanlagen"
local_file_path <- "Import BFE  Elektrizitätsproduktionsanlagen 31.10.25/ElectricityProductionPlant.csv"


# Read the *local* CSV file.
print(paste("Reading local file from:", local_file_path))
all_plants_raw <- read_csv(local_file_path, 
                           locale = locale(encoding = "UTF-8"))

# Check the data structure to ensure it loaded correctly
print("Data loaded. Showing table structure (glimpse):")
glimpse(all_plants_raw)

# -------------------------------------------------------------------
# STEP 3: CLEAN & FILTER DATA (USING ID 'subcat_2')
# -------------------------------------------------------------------
# Isolate only the solar panel data and clean it up.

print("Filtering for solar (SubCategory ID: subcat_2) plants up to 2024-12-31...")

solar_plants_2024 <- all_plants_raw %>%
  
  # 1. Filter for only solar panel installations
  # We use the ID "subcat_2" in the "SubCategory" column as requested
  filter(SubCategory == "subcat_2") %>%
  
  # 2. Convert the date column to a proper R-readable date object
  # ymd() assumes "YYYY-MM-DD" format
  mutate(operation_date = ymd(BeginningOfOperation)) %>%
  
  # 3. Filter by date, as requested
  # Keep all installations on or before Dec 31, 2024
  filter(operation_date <= "2024-12-31") %>%
  
  # 4. Select only the columns we need for this analysis
  select(
    Canton,
    Municipality,
    PostCode,
    operation_date,
    InitialPower,
    TotalPower
  )

# Check our final, clean dataset
print("Cleaning complete. Showing structure of final solar dataset:")
glimpse(solar_plants_2024)

print("Summary of solar dataset:")
summary(solar_plants_2024)

# -------------------------------------------------------------------
# STEP 4: PRELIMINARY ANALYSIS (YOUR GOAL)
# -------------------------------------------------------------------
# Find the "best" and "worst" cantons and communes

# --- 4.a) Analysis by Canton ---
print("--- Analysis by Canton (Count of Installations) ---")

installs_by_canton <- solar_plants_2024 %>%
  group_by(Canton) %>%
  summarise(
    total_installations = n(),
    total_power_kW = sum(TotalPower, na.rm = TRUE)
  ) %>%
  arrange(desc(total_installations))

# Show the Top 10 "Best" Cantons
print("Top 10 Cantons by Number of Installations:")
print(head(installs_by_canton, 10))

# Show the Bottom 10 "Worst" Cantons
print("Bottom 10 Cantons by Number of Installations:")
print(tail(installs_by_canton, 10))


# --- 4.b) Analysis by Commune ---
print("--- Analysis by Commune (Count of Installations) ---")

installs_by_commune <- solar_plants_2024 %>%
  group_by(Canton, Municipality) %>%
  summarise(
    total_installations = n(),
    total_power_kW = sum(TotalPower, na.rm = TRUE)
  ) %>%
  ungroup() %>%
  arrange(desc(total_installations))

# Show the Top 20 "Best" Communes
print("Top 20 Communes by Number of Installations:")
print(head(installs_by_commune, 20))

# Show the Bottom 20 "Worst" Communes
print("Bottom 20 Communes by Number of Installations:")
print(tail(installs_by_commune, 20))

# -------------------------------------------------------------------
# STEP 5: SAVE YOUR CLEAN DATA
# -------------------------------------------------------------------
# Save our work so we don't have to re-do the import and clean steps

saveRDS(solar_plants_2024, file = "solar_plants_2024_clean.rds")
write_csv(installs_by_canton, "summary_installs_by_canton.csv")
write_csv(installs_by_commune, "summary_installs_by_commune.csv")

print("Script finished. Clean data and summaries saved to your project directory.")

# ===================================================================
# END OF SCRIPT
# ===================================================================