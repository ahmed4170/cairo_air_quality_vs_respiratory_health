# 🌫️ Cairo Air Quality vs. Respiratory Health

**Investigating the relationship between air pollution and respiratory health in Cairo, Egypt — one of the most polluted cities in the world.**

A multi-tool, end-to-end data analysis project combining global air quality data, Egypt-specific disease burden data, and macroeconomic indicators to statistically test — and quantify — the link between PM2.5 pollution and respiratory disease outcomes.

*DEPI — Digital Egypt Pioneers Initiative | Track: Data Analysis Specialist | 2025–2026*

---

## 📖 Table of Contents

- [Overview](#-overview)
- [Key Findings](#-key-findings)
- [Data Sources](#-data-sources)
- [Data Model](#-data-model)
- [Tech Stack](#-tech-stack)
- [Repository Structure](#-repository-structure)
- [Methodology](#-methodology)
- [Dashboards](#-dashboards)
- [Recommendations](#-recommendations)
- [Team Members](#-team-members)
- [Getting Started](#-getting-started)

---

## 📌 Overview

Air pollution — particularly fine particulate matter (PM2.5) — is the leading environmental health risk globally, and Cairo consistently ranks among the most polluted major cities in the world. This project builds a complete analytical pipeline to quantify how PM2.5 exposure relates to respiratory disease burden in Egypt, and whether macroeconomic conditions play a role.

The pipeline integrates **three real-world datasets**, cleans and joins them into a **Star Schema data model**, applies **descriptive and inferential statistics** (correlation, t-tests, ANOVA, OLS regression), and delivers **interactive dashboards across five platforms**: Excel, SQL, Python, Power BI, and Tableau.

| 133 | 4 | 77,724 | 2010–2025 |
|---|---|---|---|
| Countries in Dataset | Respiratory Causes Tracked | IHME Health Records | Observation Window |

---

## 🔑 Key Findings

- 🫁 **PM2.5 is the dominant driver of respiratory mortality.** Annual PM2.5 correlates very strongly with annual respiratory deaths (**r ≈ 0.93–0.95, p < 0.0001**), and remains the only statistically significant predictor of mortality in a multiple regression model (**R² = 0.880**).
- 👶👵 **Children and seniors carry a disproportionate burden.** Once normalized per record, children (0–14) alone account for **66.5%** of average burden severity; children + seniors together account for **78.2%** of all deaths.
- ⚧ **Men bear a significantly higher burden than women** (Welch's t ≈ 3.46, p = 0.002), consistent with greater occupational and outdoor exposure.
- 💸 **Inflation shocks compound the crisis independently of pollution.** GDP growth and inflation show no direct correlation with PM2.5 (p > 0.05), but inflation spikes (up to 33.9%) coincide with reduced healthcare affordability.
- 📉 **Improvement has been partial, not sufficient.** Despite some air quality gains, mortality and DALYs remain disproportionately high — current interventions haven't yet produced proportional health gains.

> Full statistical derivations, test tables, and detailed insights are documented in [`CAQVSRH_Documentation.pdf`](https://github.com/ahmed4170/cairo_air_quality_vs_respiratory_health/blob/a3137aad46a1f9549f7894ca18c41e569b7c8712/Project%20Documentation/CAQVSRH_Documentation.pdf).

---

## 🗂️ Data Sources

| Source | Description | Coverage |
|---|---|---|
| **WHO / IQAir** | Global ambient PM2.5 concentration records | 133 countries, 2010–2025 |
| **IHME Global Burden of Disease (GBD) 2023** | Egypt-specific respiratory disease burden (Deaths & DALYs), disaggregated by sex, age, and cause | 77,724 records, 2010–2023 |
| **World Bank** | National macroeconomic indicators — GDP growth, inflation, population | 2010–2025 |

Respiratory causes tracked: **Asthma**, **Chronic Obstructive Pulmonary Disease (COPD) / Chronic respiratory diseases**, and **Lower Respiratory Infections**.

---

## 🧩 Data Model

The cleaned data is structured as a **Star Schema** — one fact table and three dimension tables — enabling efficient multi-dimensional analysis by year, cause, and demographic group.

```
                ┌────────────────────┐
                │    DIM_Cause       │
                │  cause_key (PK)    │
                │  measure, cause    │
                └─────────┬──────────┘
                          │
┌──────────────────┐      │      ┌────────────────────┐
│ DIM_Demographics  │      │      │     DIM_Macro       │
│  demo_key (PK)    │──────┼──────│  macro_key (PK)     │
│  sex, age,        │      │      │  gdp_growth,        │
│  age_category      │      │      │  inflation,          │
└─────────┬─────────┘      │      │  population, pm2_5, │
          │                │      │  aqi_category, year │
          │       ┌────────┴─────┐└──────────┬──────────┘
          └───────│ FACT_Health   │───────────┘
                  │  H_ID (PK)     │
                  │  demo_key (FK) │
                  │  macro_key (FK)│
                  │  cause_key (FK)│
                  │  val, Year,    │
                  │  COVID_Period  │
                  └────────────────┘
```

**Grain:** one row per unique combination of *year × cause × measure × sex × age category*. Joined, the master analytical table contains **4,312 rows × 19 columns**.

---

## 🛠️ Tech Stack

| Layer | Tools |
|---|---|
| **Data Modeling & ETL** | Excel (Power Pivot), MySQL |
| **Statistical Analysis** | Python (`pandas`, `numpy`, `scipy.stats`, `statsmodels`, `scikit-learn`) |
| **Visualization / Dashboards** | Plotly, Streamlit, Power BI, Tableau, Excel |
| **Forecasting** | Linear & Ridge Regression (2024–2033 projection) |

---

## 📁 Repository Structure

```
├── CAQVSRH_Documentation.docx   # Full project documentation (methodology, stats, insights)
├── CAQVSRH.xlsx                 # Excel Power Pivot model, KPI cards, pivot dashboards
├── sql_fp.sql                   # MySQL schema, ETL, descriptive & inferential statistics
├── python.ipynb                 # Full Python analysis notebook + Streamlit app (app.py)
├── dim_cause.csv                # Dimension: respiratory cause / measure
├── dim_demographics.csv         # Dimension: sex, age, age category
├── dim_macro.csv                # Dimension: PM2.5, GDP growth, inflation, population
├── fact_health.csv              # Fact table: health burden records
├── app.py                       # Streamlit dashboard (generated from the notebook)
├── *.pbix                       # Power BI dashboard
├── *.twbx                       # Tableau dashboard
└── README.md
```

---

## 🔬 Methodology

1. **Data Cleaning & Transformation** — standardized column names, parsed percentage fields, verified zero nulls/duplicates/negative values, engineered `burden_per_100k` and PM2.5 risk tiers.
2. **Data Modeling** — built the Star Schema described above; resolved Power Pivot's 1-to-many cardinality constraint via a composite country-year key.
3. **Descriptive Statistics** — mean, median, std. deviation, skewness, kurtosis, and quartiles computed on health burden, PM2.5, GDP growth, and inflation.
4. **Inferential Statistics**:
   - **Pearson Correlation** — PM2.5 vs. respiratory deaths (r ≈ 0.93–0.95, p < 0.0001)
   - **Welch's Two-Sample t-Test** — male vs. female burden (t ≈ 3.46, p = 0.002)
   - **One-Way ANOVA** — burden and mortality across age categories (F ≈ 67.4 / 81.6, p < 0.0001)
   - **OLS Multiple Regression** — deaths ~ PM2.5 + GDP growth + inflation (R² = 0.880)
5. **Forecasting** — a two-stage Linear/Ridge Regression pipeline projecting PM2.5, deaths, DALYs, and population from 2024–2033.

📄 See [`CAQVSRH_Documentation.docx`](./CAQVSRH_Documentation.docx) for the complete write-up, including every test's null hypothesis, result table, and interpretation.

---

## 📊 Dashboards

| Platform | Highlights |
|---|---|
| **Excel** | Power Pivot data model with KPI cards and pivot charts |
| **Streamlit (Python)** | 4-tab interactive app: `📊 Executive KPI Overview` · `👥 Demographics & Causes` · `🧪 Statistical Lab & Economics` · `💡 Strategic Action Center` |
| **Power BI** | Interactive drill-down by cause, demographic, and year |
| **Tableau** | Visual storytelling — PM2.5 vs. mortality trends, demographic breakdowns |

**Run the Streamlit app locally:**
```bash
pip install streamlit pandas numpy plotly scipy scikit-learn
streamlit run app.py
```

---

## ✅ Recommendations

1. **Accelerate emissions reduction** — the strongest, most direct lever for reducing mortality.
2. **Prioritize pediatric & geriatric respiratory care**, given their outsized share of the burden.
3. **Target occupational exposure protections** for male outdoor/industrial workers.
4. **Buffer healthcare affordability** during inflation shocks (e.g. subsidized inhalers/medicines).
5. **Track forecasted vs. actual outcomes** annually to catch policy drift early.
6. **Institutionalize the Star Schema** as a shared source of truth across all reporting tools.

---

## 👥 Team Members

| Name | Role |
|---|---|
| Ahmed Haytham | Data Analyst |
| Amr Mohamed | Data Analyst |
| Kerillos Milad | Data Analyst |
| Mohanad Mohamed | Data Analyst |
| Youssef Mostafa | Data Analyst |

**Supervised by:** Amal Mahmoud

---

## 🚀 Getting Started

```bash
# Clone the repository
git clone https://github.com/<your-username>/cairo-air-quality-respiratory-health.git
cd cairo-air-quality-respiratory-health

# (Optional) create a virtual environment
python -m venv venv
source venv/bin/activate

# Install dependencies
pip install pandas numpy plotly scipy statsmodels scikit-learn streamlit

# Explore the analysis
jupyter notebook python.ipynb

# Or launch the dashboard
streamlit run app.py
```

---

<p align="center"><i>Digital Egypt Pioneers Initiative (DEPI) — Data Analysis Specialist Track, 2025–2026</i></p>
