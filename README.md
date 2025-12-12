# Swiss Solar Panel Analysis

This project analyzes solar panel installations in Switzerland using data from the BFE.

## 🚀 How to Run This Project

1.  **Clone the Repository:**
    ```bash
    git clone https://github.com/drjacques-coder/SwissSolarStats.git
    ```

2.  **Get the Data:**
    * Download the data from: [https://opendata.swiss/de/dataset/elektrizitatsproduktionsanlagen](https://opendata.swiss/de/dataset/elektrizitatsproduktionsanlagen)
    * Unzip the file.

3.  **Set Up Folders:**
    * Inside this project folder, create a new folder named exactly:
        `Import BFE  Elektrizitätsproduktionsanlagen 31.10.25`
        *(Note: There are two spaces after "BFE")*
    * Move the `.csv` files (like `ElectricityProductionPlant.csv`) into that new folder.

4.  **Run the Analysis:**
    * Open the `SwissSolarStats.Rproj` file to start RStudio.
    * Open and run the `01_load_and_clean.R` script.

The project is set up to use relative paths, so as long as the data folder is named correctly, the script will run without changes
## 📊 Preliminary Results (Top 20)

![Top 20 Capacity](plot_top20_capacity.png)

![Top 20 Intensity](plot_top20_intensity.png)
