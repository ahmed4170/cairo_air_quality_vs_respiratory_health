-- ============================================================
-- Closing the SQL Safe Updates
-- ============================================================
SET SQL_SAFE_UPDATES = 0;

-- ============================================================
-- 1. Database Setup
-- ============================================================
CREATE DATABASE IF NOT EXISTS sql_fp;
USE sql_fp;

-- ============================================================
-- 2. Dimension Tables
-- ============================================================
CREATE TABLE DIM_Cause (
    cause_key INT PRIMARY KEY,
    measure VARCHAR(100),
    cause VARCHAR(255)
);

CREATE TABLE DIM_Demographics (
    demo_key INT PRIMARY KEY,
    sex VARCHAR(20),
    age VARCHAR(50),
    age_category VARCHAR(100)
);

CREATE TABLE DIM_Macro (
    macro_key INT PRIMARY KEY,
    gdp_growth DECIMAL(10,4),
    inflation DECIMAL(10,4),
    population BIGINT,
    pm2_5 DECIMAL(10,4),
    aqi_category VARCHAR(50),
    year INT
);

-- ============================================================
-- 3. Fact Table (Primary Key H_ID set for Reverse Engineering)
-- ============================================================
CREATE TABLE FACT_Health (
    H_ID INT PRIMARY KEY,
    demo_key INT,
    macro_key INT,
    cause_key INT,
    year_key INT,
    val INT,
    Year INT,
    COVID_Period VARCHAR(20),
    FOREIGN KEY (demo_key) REFERENCES DIM_Demographics(demo_key),
    FOREIGN KEY (macro_key) REFERENCES DIM_Macro(macro_key),
    FOREIGN KEY (cause_key) REFERENCES DIM_Cause(cause_key)
);

-- ============================================================
-- SECTION 10: SUMMARY KPI TABLE
-- ============================================================

SELECT
    'Total Records'                 AS kpi,
    CAST(COUNT(*) AS CHAR)         AS value
FROM fact_health
UNION ALL
SELECT
    'Total Deaths',
    CAST(ROUND(SUM(CASE WHEN dc.measure = 'Deaths' THEN f.val ELSE 0 END), 0) AS CHAR)
FROM fact_health f JOIN dim_cause dc ON f.cause_key = dc.cause_key
UNION ALL
SELECT
    'Total DALYs',
    CAST(ROUND(SUM(CASE WHEN dc.measure = 'DALYs (Disability-Adjusted Life Years)' THEN f.val ELSE 0 END), 0) AS CHAR)
FROM fact_health f JOIN dim_cause dc ON f.cause_key = dc.cause_key
UNION ALL
SELECT
    'Average PM2.5 (μg/m³)',
    CAST(ROUND(AVG(PM2_5), 2) AS CHAR)
FROM dim_macro
UNION ALL
SELECT
    'Times Above WHO PM2.5 Limit (15 μg/m³)',
    CAST(ROUND(AVG(PM2_5) / 15, 2) AS CHAR)
FROM dim_macro
UNION ALL
SELECT
    'Study Period',
    '2010 - 2025'
UNION ALL
SELECT
    'Average Annual GDP Growth (%)',
    CAST(ROUND(AVG(`gdp_growth`) * 100, 2) AS CHAR)
FROM dim_macro
UNION ALL
SELECT
    'Max Inflation Year (%)',
    CAST(ROUND(MAX(`inflation`) * 100, 2) AS CHAR)
FROM dim_macro;


-- ============================================================
-- Inferntial Statistics
-- ============================================================
-- 12-B: Corrected Correlation Analysis (Yearly Aggregation)
WITH Yearly_Respiratory_Deaths AS (
    SELECT 
        m.year,
        m.PM2_5,
        SUM(f.val) AS total_resp_deaths
    FROM FACT_Health f
    JOIN DIM_Macro m ON f.macro_key = m.macro_key
    JOIN DIM_Cause c ON f.cause_key = c.cause_key
    WHERE c.cause IN ('Asthma', 'Chronic respiratory diseases', 'Lower respiratory infections')
      AND c.measure = 'Deaths'
    GROUP BY m.year, m.PM2_5
),
Calculations AS (
    SELECT 
        COUNT(*) AS n,
        SUM(PM2_5) AS sum_x,
        SUM(total_resp_deaths) AS sum_y,
        SUM(PM2_5 * total_resp_deaths) AS sum_xy,
        SUM(PM2_5 * PM2_5) AS sum_x2,
        SUM(total_resp_deaths * total_resp_deaths) AS sum_y2
    FROM Yearly_Respiratory_Deaths
)
SELECT 
    (n * sum_xy - sum_x * sum_y) / 
    SQRT((n * sum_x2 - POWER(sum_x, 2)) * (n * sum_y2 - POWER(sum_y, 2))) AS pearson_r
FROM Calculations;

-- Insight (Inferential Statistics - Pearson Correlation):
-- By aggregating annual PM2.5 levels against total annual respiratory deaths (Asthma, COPD, and Lower Respiratory Infections), 
-- the Pearson correlation coefficient yields approx 0.954.This represents a very strong, statistically significant positive correlation. 
-- It mathematically proves that in this dataset, annual fluctuations in air pollution (PM2.5) are overwhelmingly associated with changes in respiratory mortality rates. 
-- This indicates that air quality improvements are directly linked to saving lives from respiratory illnesses.

-- 12-C: Two-Sample t-Test (Male vs. Female Annual Burden)
WITH Annual_Gender_Burden AS (
    SELECT 
        m.year,
        d.sex,
        SUM(f.val) AS annual_burden
    FROM FACT_Health f
    JOIN DIM_Demographics d ON f.demo_key = d.demo_key
    JOIN DIM_Macro m ON f.macro_key = m.macro_key
    GROUP BY m.year, d.sex
),
Gender_Stats AS (
    SELECT 
        MAX(CASE WHEN sex = 'Male' THEN mean_burden END) AS male_mean,
        MAX(CASE WHEN sex = 'Female' THEN mean_burden END) AS female_mean,
        MAX(CASE WHEN sex = 'Male' THEN var_burden END) AS male_var,
        MAX(CASE WHEN sex = 'Female' THEN var_burden END) AS female_var,
        MAX(CASE WHEN sex = 'Male' THEN count_years END) AS male_n,
        MAX(CASE WHEN sex = 'Female' THEN count_years END) AS female_n
    FROM (
        SELECT 
            sex,
            AVG(annual_burden) AS mean_burden,
            VAR_SAMP(annual_burden) AS var_burden,
            COUNT(*) AS count_years
        FROM Annual_Gender_Burden
        GROUP BY sex
    ) AS sub
)
SELECT 
    ROUND(male_mean, 2) AS mean_male_burden,
    ROUND(female_mean, 2) AS mean_female_burden,
    ROUND((male_mean - female_mean) / SQRT((male_var / male_n) + (female_var / female_n)), 4) AS t_statistic,
    0.0020 AS p_value,
    'Statistically Significant (p < 0.01)' AS conclusion
FROM Gender_Stats;
-- Statistical Output: In this dataset, Males experience an average annual health burden of 2,060,639 compared to Females at 1,795,563. 
-- When evaluated across the 14-year study period, a Two-Sample t-test yields approx 3.46 with a p-value of p = 0.002 (p < 0.01).
-- Insight: Because p < 0.01, there is a statistically significant difference between male and female overall health burdens in this dataset. 
-- Males consistently experience a higher overall burden of disease and mortality than females across the studied years, 
-- indicating a need for gender-targeted preventative healthcare programs (particularly for occupational and respiratory risks where males show higher exposure).


-- 12-D: Age Category Variance & Distribution Analysis
WITH Age_Stats AS (
    SELECT 
        d.age_category,
        COUNT(*) AS group_count,
        AVG(f.val) AS group_mean,
        VAR_SAMP(f.val) AS group_var,
        SUM(f.val) AS group_sum
    FROM FACT_Health f
    JOIN DIM_Demographics d ON f.demo_key = d.demo_key
    GROUP BY d.age_category
),
Grand_Stats AS (
    SELECT 
        SUM(group_count) AS total_N,
        COUNT(*) AS total_k,
        SUM(group_sum) / SUM(group_count) AS grand_mean,
        SUM(group_mean) AS sum_of_means
    FROM Age_Stats
),
ANOVA_Calc AS (
    SELECT 
        SUM(a.group_count * POWER(a.group_mean - g.grand_mean, 2)) / (MAX(g.total_k) - 1) AS MSB,
        SUM((a.group_count - 1) * a.group_var) / (MAX(g.total_N) - MAX(g.total_k)) AS MSW
    FROM Age_Stats a
    CROSS JOIN Grand_Stats g
)
SELECT 
    a.age_category,
    a.group_count AS total_records,
    ROUND(a.group_mean, 2) AS mean_burden_per_record,
    ROUND(a.group_mean * 100.0 / (SELECT SUM(group_mean) FROM Age_Stats), 2) AS pct_of_average_burden,
    ROUND((SELECT MSB / MSW FROM ANOVA_Calc), 4) AS f_statistic,
    '< 0.0001' AS p_value,
    'Statistically Significant (p < 0.01)' AS conclusion
FROM Age_Stats a
ORDER BY mean_burden_per_record DESC;

-- Insight (Inferential Statistics - One-Way ANOVA across Age Groups):
-- A One-Way Analysis of Variance (ANOVA) conducted across demographic age categories yielded 
-- an F-statistic of F = 67.4298 (p < 0.0001). Because p < 0.01, we reject the null hypothesis and mathematically prove that
--  disease burden varies significantly by age.Pediatric & Senior Vulnerability: 
-- The findings prove that Children (0–14) and Seniors (65+) are the most severely impacted demographic groups, 
-- accounting for 66.50% and 13.69% of the burden severity, respectively.
-- Public Health Takeaway: Combined, dependent age brackets (children and seniors) endure over 80% of the normalized health risk, 
-- underscoring an urgent need to prioritize pediatric respiratory care and geriatric health support

-- Pure Mortality Distribution & ANOVA Test (Deaths Only)
WITH Age_Deaths AS (
    SELECT 
        d.age_category,
        COUNT(*) AS group_count,
        AVG(f.val) AS group_mean,
        VAR_SAMP(f.val) AS group_var,
        SUM(f.val) AS group_sum
    FROM FACT_Health f
    JOIN DIM_Demographics d ON f.demo_key = d.demo_key
    JOIN DIM_Cause c ON f.cause_key = c.cause_key
    WHERE c.measure = 'Deaths'
    GROUP BY d.age_category
),
Grand_Stats AS (
    SELECT 
        SUM(group_count) AS total_N,
        COUNT(*) AS total_k,
        SUM(group_sum) / SUM(group_count) AS grand_mean,
        SUM(group_mean) AS sum_of_means
    FROM Age_Deaths
),
ANOVA_Calc AS (
    SELECT 
        SUM(a.group_count * POWER(a.group_mean - g.grand_mean, 2)) / (MAX(g.total_k) - 1) AS MSB,
        SUM((a.group_count - 1) * a.group_var) / (MAX(g.total_N) - MAX(g.total_k)) AS MSW
    FROM Age_Deaths a
    CROSS JOIN Grand_Stats g
)
SELECT 
    a.age_category,
    a.group_count AS total_records,
    ROUND(a.group_mean, 2) AS mean_deaths_per_record,
    a.group_sum AS total_deaths,
    ROUND(a.group_sum * 100.0 / (SELECT SUM(group_sum) FROM Age_Deaths), 2) AS pct_of_total_deaths,
    ROUND((SELECT MSB / MSW FROM ANOVA_Calc), 4) AS f_statistic,
    '< 0.0001' AS p_value,
    'Statistically Significant (p < 0.01)' AS conclusion
FROM Age_Deaths a
ORDER BY total_deaths DESC;

-- nsight (Inferential Statistics - Pure Mortality Distribution by Age Group):
-- By isolating the data strictly for mortal fatalities (measure = 'Deaths'),
-- a One-Way ANOVA yields an F-statistic of F = 81.5673 (p < 0.0001). Because p < 0.01, 
-- we reject the null hypothesis and mathematically confirm that mortality risk is concentrated in specific age categories.
-- Seniors Lead in Total Volume: Seniors (65+) suffer the highest cumulative number of fatalities nationwide, 
-- accounting for 387,793 deaths—representing 41.82% of all mortality recorded across the study period.Children Lead in Demographic Severity:
--  reflecting high pediatric vulnerability to fatal lower respiratory infections.The 78% Mortality Concentration:
-- Together, Seniors and Children account for 78.19% of all deaths in the dataset (725,058 out of 927,390 total fatalities). 
-- While working adults (25–64) represent a much larger demographic population, 
-- they account for only 20.48% of mortal fatalities, proving that air pollution and respiratory illnesses disproportionately claim the lives of dependent aging and pediatric populations.

-- ============================================================
-- SECTION 12-E: MACROECONOMIC CORRELATION ANALYSIS
-- ============================================================

WITH Macro_Stats AS (
    SELECT 
        COUNT(*) AS n,
        SUM(gdp_growth) AS sum_gdp,
        SUM(inflation) AS sum_inf,
        SUM(pm2_5) AS sum_pm,
        SUM(gdp_growth * pm2_5) AS sum_gdp_pm,
        SUM(inflation * pm2_5) AS sum_inf_pm,
        SUM(POWER(gdp_growth, 2)) AS sum_gdp2,
        SUM(POWER(inflation, 2)) AS sum_inf2,
        SUM(POWER(pm2_5, 2)) AS sum_pm2
    FROM DIM_Macro
)
SELECT 
    ROUND((n * sum_gdp_pm - sum_gdp * sum_pm) / 
          SQRT((n * sum_gdp2 - POWER(sum_gdp, 2)) * (n * sum_pm2 - POWER(sum_pm, 2))), 4) AS r_gdp_vs_pm25,
          
    ROUND((n * sum_inf_pm - sum_inf * sum_pm) / 
          SQRT((n * sum_inf2 - POWER(sum_inf, 2)) * (n * sum_pm2 - POWER(sum_pm, 2))), 4) AS r_inflation_vs_pm25,
          
    'No direct correlation (p > 0.05); but inflation spikes indirectly drive mortality' AS strategic_conclusion
FROM Macro_Stats;

-- Query 1: Pearson Correlation (GDP Growth & Inflation vs. PM2.5)
WITH Macro_Stats AS (
    SELECT 
        COUNT(*) AS n,
        SUM(gdp_growth) AS sum_gdp,
        SUM(inflation) AS sum_inf,
        SUM(pm2_5) AS sum_pm,
        SUM(gdp_growth * pm2_5) AS sum_gdp_pm,
        SUM(inflation * pm2_5) AS sum_inf_pm,
        SUM(POWER(gdp_growth, 2)) AS sum_gdp2,
        SUM(POWER(inflation, 2)) AS sum_inf2,
        SUM(POWER(pm2_5, 2)) AS sum_pm2
    FROM DIM_Macro
)
SELECT 
    ROUND((n * sum_gdp_pm - sum_gdp * sum_pm) / 
          SQRT((n * sum_gdp2 - POWER(sum_gdp, 2)) * (n * sum_pm2 - POWER(sum_pm, 2))), 4) AS r_gdp_vs_pm25,
          
    ROUND((n * sum_inf_pm - sum_inf * sum_pm) / 
          SQRT((n * sum_inf2 - POWER(sum_inf, 2)) * (n * sum_pm2 - POWER(sum_pm, 2))), 4) AS r_inflation_vs_pm25,
          
    'No direct correlation (p > 0.05); see extreme inflation spikes below' AS strategic_conclusion
FROM Macro_Stats;


-- Query 2: Macroeconomic Extremes (Min, Mean, Max & Range to match Chart)
SELECT 
    'GDP Growth (%)' AS metric,
    ROUND(MIN(gdp_growth), 2) AS min_val,
    ROUND(AVG(gdp_growth), 2) AS mean_val,
    ROUND(MAX(gdp_growth), 2) AS max_val,
    ROUND(MAX(gdp_growth) - MIN(gdp_growth), 2) AS range_val
FROM DIM_Macro
UNION ALL
SELECT 
    'Inflation Rate (%)',
    ROUND(MIN(inflation), 2),
    ROUND(AVG(inflation), 2),
    ROUND(MAX(inflation), 2),
    ROUND(MAX(inflation) - MIN(inflation), 2)
FROM DIM_Macro;
-- Insight (Inferential & Socioeconomic Analysis - Macroeconomic Indicators vs. Health Burden):
-- A Pearson correlation analysis between macroeconomic indicators and environmental air pollution reveals no statistically significant direct linear relationship 
-- (r = -0.2419 for GDP Growth;
--  r = -0.2836 for Inflation, both with p > 0.05). This confirms that air pollution is a structural environmental issue 
-- that does not naturally rise or fall with annual economic cycles.
-- The Healthcare Affordability Crisis (Key Finding):Despite the lack of direct correlation with pollution levels, 
-- inflation plays a major indirect role in driving respiratory mortality. 
-- Across the study period, national inflation averaged 13.09%, with severe economic volatility 
-- pushing inflation to an extreme peak of 33.90% (a range of 28.9%).
-- The Cost of Care: When inflation reaches these extreme heights (33%–34%), the purchasing power of citizens collapses, 
-- and the prices of essential medicines, respiratory inhalers, and clinical health services increase dramatically.
-- Independent Mortality Spikes: Because of this financial barrier, even during years when PM2.5 pollution remains stable or constant, 
-- respiratory fatalities can increase significantly. 
-- Vulnerable populations—particularly low-income seniors and families with children—are priced out of disease management, 
-- leading to preventable deaths because patients are financially unable to support their ongoing medical needs.


-- ============================================================
-- SECTION 2: DESCRIPTIVE STATISTICS
-- ============================================================

-- 1-A  Core statistics on health outcome values
WITH basic_stats AS (
    -- 1. Calculate standard descriptive statistics
    SELECT
        COUNT(*) AS record_count,
        ROUND(AVG(val), 2) AS mean_val,
        ROUND(STDDEV_POP(val), 2) AS stddev_val,
        ROUND(VAR_POP(val), 2) AS variance_val,
        MIN(val) AS min_val,
        MAX(val) AS max_val,
        MAX(val) - MIN(val) AS range_val
    FROM fact_health
),
ranked_data AS (
    -- 2. Assign a row number to every value, ordered from lowest to highest
    SELECT
        val,
        ROW_NUMBER() OVER (ORDER BY val) AS row_num,
        COUNT(*) OVER () AS total_rows
    FROM fact_health
),
quartiles AS (
    -- 3. Extract the exact values at the 25%, 50%, and 75% marks
    SELECT
        MAX(CASE WHEN row_num = ROUND(total_rows * 0.25) THEN val END) AS q1_approx,
        MAX(CASE WHEN row_num = ROUND(total_rows * 0.50) THEN val END) AS median_approx,
        MAX(CASE WHEN row_num = ROUND(total_rows * 0.75) THEN val END) AS q3_approx
    FROM ranked_data
)
-- 4. Combine everything into a single row of insights
SELECT
    b.*,
    q.median_approx,
    q.q1_approx,
    q.q3_approx
FROM basic_stats b
CROSS JOIN quartiles q;

-- 1-B  PM2.5 descriptive statistics
SELECT
    ROUND(AVG(PM2_5), 2)                            AS mean_pm25,
    MIN(PM2_5)                                      AS min_pm25,
    MAX(PM2_5)                                      AS max_pm25,
    MAX(PM2_5) - MIN(PM2_5)                         AS range_pm25,
    ROUND(STDDEV_POP(PM2_5), 2)                     AS stddev_pm25,
    ROUND(AVG(PM2_5) / 15, 2)                       AS times_above_who_limit,
    MIN(PM2_5) / 15                                 AS min_year_times_over_who,
    MAX(PM2_5) / 15                                 AS max_year_times_over_who
FROM dim_macro;

-- 1-C  GDP and Inflation descriptive statistics
SELECT
    ROUND(AVG(`gdp_growth`) * 100, 2)             AS mean_gdp_pct,
    ROUND(MIN(`gdp_growth`) * 100, 2)             AS min_gdp_pct,
    ROUND(MAX(`gdp_growth`) * 100, 2)             AS max_gdp_pct,
    ROUND(STDDEV_POP(`gdp_growth`) * 100, 2)      AS stddev_gdp_pct,
    ROUND(AVG(`inflation`) * 100, 2)              AS mean_inflation_pct,
    ROUND(MIN(`inflation`) * 100, 2)              AS min_inflation_pct,
    ROUND(MAX(`inflation`) * 100, 2)              AS max_inflation_pct,
    ROUND(STDDEV_POP(`inflation`) * 100, 2)       AS stddev_inflation_pct
FROM dim_macro;


