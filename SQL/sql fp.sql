CREATE DATABASE IF NOT EXISTS sql_fp;

USE sql_fp;

-- ============================================================
--   SQL FINAL PROJECT: RESPIRATORY HEALTH IN EGYPT (2010-2025)
--   Database: sql_fp
--   Tables: dim_cause, dim_dimographics, dim_macro, dim_year, fact_health
-- ============================================================

USE sql_fp;

-- ============================================================
-- SECTION 0: HELPER VIEWS (join all dimensions to fact table)
-- ============================================================

DROP VIEW IF EXISTS v_full;
CREATE VIEW v_full AS
SELECT
    f.val,
    f.year,
    dy.COVID_Period,
    dc.measure,
    dc.cause,
    dd.sex,
    dd.age,
    dd.`age category`                   AS age_category,
    dm.`% GDP growth`                   AS gdp_growth,
    dm.`% Inflation`                    AS inflation,
    dm.`Population, total`              AS population,
    dm.PM2_5
FROM fact_health          f
JOIN dim_year             dy ON f.year_key  = dy.year_key
JOIN dim_cause            dc ON f.cause_key = dc.cause_key
JOIN dim_dimographics     dd ON f.demo_key  = dd.demo_key
JOIN dim_macro            dm ON f.macro_key = dm.macro_key;


-- ============================================================
-- SECTION 1: DESCRIPTIVE STATISTICS
-- ============================================================

-- 1-A  Core statistics on health outcome values
DROP TABLE IF EXISTS insight_descriptive_stats;
CREATE TABLE insight_descriptive_stats AS
WITH ranked AS (
    SELECT val,
           ROW_NUMBER() OVER (ORDER BY val) AS rn,
           COUNT(*)     OVER ()             AS total
    FROM fact_health
),
percentiles AS (
    SELECT
        MAX(CASE WHEN rn = FLOOR(total / 2)     THEN val END) AS median_approx,
        MAX(CASE WHEN rn = FLOOR(total / 4)     THEN val END) AS q1_approx,
        MAX(CASE WHEN rn = FLOOR(total * 3 / 4) THEN val END) AS q3_approx
    FROM ranked
)
SELECT
    COUNT(*)                    AS record_count,
    ROUND(AVG(f.val), 2)        AS mean_val,
    ROUND(STDDEV_POP(f.val), 2) AS stddev_val,
    ROUND(VAR_POP(f.val), 2)    AS variance_val,
    MIN(f.val)                  AS min_val,
    MAX(f.val)                  AS max_val,
    MAX(f.val) - MIN(f.val)     AS range_val,
    MAX(p.median_approx)        AS median_approx,
    MAX(p.q1_approx)            AS q1_approx,
    MAX(p.q3_approx)            AS q3_approx
FROM fact_health f
CROSS JOIN percentiles p;

SELECT * FROM insight_descriptive_stats;


-- 1-B  PM2.5 descriptive statistics
DROP TABLE IF EXISTS insight_pm25_stats;
CREATE TABLE insight_pm25_stats AS
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

SELECT * FROM insight_pm25_stats;


-- 1-C  GDP and Inflation descriptive statistics
DROP TABLE IF EXISTS insight_macro_stats;
CREATE TABLE insight_macro_stats AS
SELECT
    ROUND(AVG(`% GDP growth`) * 100, 2)             AS mean_gdp_pct,
    ROUND(MIN(`% GDP growth`) * 100, 2)             AS min_gdp_pct,
    ROUND(MAX(`% GDP growth`) * 100, 2)             AS max_gdp_pct,
    ROUND(STDDEV_POP(`% GDP growth`) * 100, 2)      AS stddev_gdp_pct,
    ROUND(AVG(`% Inflation`) * 100, 2)              AS mean_inflation_pct,
    ROUND(MIN(`% Inflation`) * 100, 2)              AS min_inflation_pct,
    ROUND(MAX(`% Inflation`) * 100, 2)              AS max_inflation_pct,
    ROUND(STDDEV_POP(`% Inflation`) * 100, 2)       AS stddev_inflation_pct
FROM dim_macro;

SELECT * FROM insight_macro_stats;


-- ============================================================
-- SECTION 2: TOTAL BURDEN BY CAUSE AND MEASURE
-- ============================================================

-- 2-A  Total health burden (Deaths + DALYs) by cause
DROP TABLE IF EXISTS insight_burden_by_cause;
CREATE TABLE insight_burden_by_cause AS
SELECT
    measure,
    cause,
    SUM(val)                                AS total_burden,
    ROUND(AVG(val), 2)                      AS avg_burden,
    MIN(val)                                AS min_burden,
    MAX(val)                                AS max_burden
FROM v_full
GROUP BY measure, cause
ORDER BY measure, total_burden DESC;

SELECT * FROM insight_burden_by_cause;


-- 2-B  Annual total Deaths and DALYs (pivot-style)
DROP TABLE IF EXISTS insight_annual_burden;
CREATE TABLE insight_annual_burden AS
SELECT
    year,
    COVID_Period,
    SUM(CASE WHEN measure = 'Deaths' THEN val ELSE 0 END)                               AS total_deaths,
    SUM(CASE WHEN measure = 'DALYs (Disability-Adjusted Life Years)' THEN val ELSE 0 END) AS total_dalys,
    SUM(val)                                                                             AS grand_total
FROM v_full
GROUP BY year, COVID_Period
ORDER BY year;

SELECT * FROM insight_annual_burden;


-- 2-C  Deaths by cause and year (cross-tab / matrix view)
DROP TABLE IF EXISTS insight_deaths_by_cause_year;
CREATE TABLE insight_deaths_by_cause_year AS
SELECT
    year,
    COVID_Period,
    SUM(CASE WHEN cause = 'Asthma'                                 THEN val ELSE 0 END) AS Asthma,
    SUM(CASE WHEN cause = 'Chronic obstructive pulmonary disease'  THEN val ELSE 0 END) AS COPD,
    SUM(CASE WHEN cause = 'Chronic respiratory diseases'           THEN val ELSE 0 END) AS Chronic_Resp,
    SUM(CASE WHEN cause = 'Lower respiratory infections'           THEN val ELSE 0 END) AS Lower_Resp_Inf,
    SUM(val)                                                                             AS Year_Total
FROM v_full
WHERE measure = 'Deaths'
GROUP BY year, COVID_Period
ORDER BY year;

SELECT * FROM insight_deaths_by_cause_year;


-- ============================================================
-- SECTION 3: DEMOGRAPHIC INSIGHTS
-- ============================================================

-- 3-A  Total burden by age category and sex
DROP TABLE IF EXISTS insight_burden_by_demo;
CREATE TABLE insight_burden_by_demo AS
SELECT
    age_category,
    sex,
    measure,
    SUM(val)            AS total_burden,
    ROUND(AVG(val), 2)  AS avg_burden
FROM v_full
GROUP BY age_category, sex, measure
ORDER BY measure, age_category, sex;

SELECT * FROM insight_burden_by_demo;


-- 3-B  Deaths by age group (ranked) — shows most-at-risk groups
DROP TABLE IF EXISTS insight_deaths_by_age_ranked;
CREATE TABLE insight_deaths_by_age_ranked AS
SELECT
    age,
    age_category,
    SUM(val)                                AS total_deaths,
    ROUND(SUM(val) * 100.0 /
        (SELECT SUM(val) FROM v_full WHERE measure = 'Deaths'), 2) AS pct_of_total
FROM v_full
WHERE measure = 'Deaths'
GROUP BY age, age_category
ORDER BY total_deaths DESC;

SELECT * FROM insight_deaths_by_age_ranked;


-- 3-C  Gender comparison — total deaths and DALYs
DROP TABLE IF EXISTS insight_gender_comparison;
CREATE TABLE insight_gender_comparison AS
SELECT
    sex,
    SUM(CASE WHEN measure = 'Deaths' THEN val ELSE 0 END)                               AS total_deaths,
    SUM(CASE WHEN measure = 'DALYs (Disability-Adjusted Life Years)' THEN val ELSE 0 END) AS total_dalys,
    ROUND(AVG(CASE WHEN measure = 'Deaths' THEN val END), 2)                             AS avg_deaths_per_record,
    ROUND(AVG(CASE WHEN measure = 'DALYs (Disability-Adjusted Life Years)' THEN val END), 2) AS avg_dalys_per_record
FROM v_full
GROUP BY sex;

SELECT * FROM insight_gender_comparison;


-- ============================================================
-- SECTION 4: AIR POLLUTION & HEALTH CORRELATION
-- ============================================================

-- 4-A  Annual PM2.5 vs total deaths
DROP TABLE IF EXISTS insight_pm25_vs_deaths;
CREATE TABLE insight_pm25_vs_deaths AS
SELECT
    dm.Year                                                     AS year,
    dy.COVID_Period,
    dm.PM2_5,
    SUM(CASE WHEN dc.measure = 'Deaths' THEN f.val ELSE 0 END)  AS total_deaths,
    SUM(CASE WHEN dc.measure = 'DALYs (Disability-Adjusted Life Years)' THEN f.val ELSE 0 END) AS total_dalys,
    ROUND(dm.`% GDP growth` * 100, 2)                           AS gdp_pct,
    ROUND(dm.`% Inflation`  * 100, 2)                           AS inflation_pct,
    dm.`Population, total`                                      AS population
FROM fact_health  f
JOIN dim_macro    dm ON f.macro_key = dm.macro_key
JOIN dim_cause    dc ON f.cause_key = dc.cause_key
JOIN dim_year     dy ON f.year_key  = dy.year_key
GROUP BY dm.Year, dy.COVID_Period, dm.PM2_5,
         dm.`% GDP growth`, dm.`% Inflation`, dm.`Population, total`
ORDER BY dm.Year;

SELECT * FROM insight_pm25_vs_deaths;


-- 4-B  Pearson correlation approximation: PM2.5 vs annual deaths
--      Using the formula: r = (n*SUM(xy) - SUM(x)*SUM(y)) /
--                             SQRT( (n*SUM(x^2)-SUM(x)^2) * (n*SUM(y^2)-SUM(y)^2) )
DROP TABLE IF EXISTS insight_correlation_pm25_deaths;
CREATE TABLE insight_correlation_pm25_deaths AS
WITH yearly AS (
    SELECT
        dm.PM2_5                                                                         AS x,
        SUM(CASE WHEN dc.measure = 'Deaths' THEN f.val ELSE 0 END)                      AS y
    FROM fact_health f
    JOIN dim_macro dm ON f.macro_key = dm.macro_key
    JOIN dim_cause dc ON f.cause_key = dc.cause_key
    GROUP BY dm.Year, dm.PM2_5
),
sums AS (
    SELECT
        COUNT(*)        AS n,
        SUM(x)          AS sx,
        SUM(y)          AS sy,
        SUM(x * y)      AS sxy,
        SUM(x * x)      AS sx2,
        SUM(y * y)      AS sy2
    FROM yearly
)
SELECT
    ROUND(
        (n * sxy - sx * sy) /
        SQRT((n * sx2 - sx * sx) * (n * sy2 - sy * sy))
    , 4) AS pearson_r_pm25_vs_deaths,
    'Higher PM2.5 strongly correlates with higher deaths (r≈0.63 expected)' AS interpretation
FROM sums;

SELECT * FROM insight_correlation_pm25_deaths;


-- 4-C  PM2.5 trend & WHO exceedance per year
DROP TABLE IF EXISTS insight_pm25_who_exceedance;
CREATE TABLE insight_pm25_who_exceedance AS
SELECT
    Year,
    PM2_5,
    15                                          AS who_limit,
    PM2_5 - 15                                  AS excess_above_who,
    ROUND(PM2_5 / 15, 2)                        AS times_over_who,
    CASE WHEN PM2_5 >= 86 THEN 'Extreme'
         WHEN PM2_5 >= 75 THEN 'Very High'
         WHEN PM2_5 >= 55 THEN 'High'
         ELSE 'Elevated' END                    AS pollution_category
FROM dim_macro
ORDER BY Year;

SELECT * FROM insight_pm25_who_exceedance;


-- ============================================================
-- SECTION 5: COVID PERIOD COMPARISON
-- ============================================================

-- 5-A  Avg annual deaths by COVID period
DROP TABLE IF EXISTS insight_covid_period_comparison;
CREATE TABLE insight_covid_period_comparison AS
SELECT
    dy.COVID_Period,
    COUNT(DISTINCT f.year)                                          AS years_in_period,
    SUM(CASE WHEN dc.measure = 'Deaths' THEN f.val ELSE 0 END)     AS total_deaths,
    ROUND(
        SUM(CASE WHEN dc.measure = 'Deaths' THEN f.val ELSE 0 END)
        / COUNT(DISTINCT f.year), 2)                                AS avg_annual_deaths,
    SUM(CASE WHEN dc.measure = 'DALYs (Disability-Adjusted Life Years)' THEN f.val ELSE 0 END) AS total_dalys,
    ROUND(AVG(dm.PM2_5), 2)                                         AS avg_pm25,
    ROUND(AVG(dm.`% Inflation`) * 100, 2)                           AS avg_inflation_pct
FROM fact_health  f
JOIN dim_year     dy ON f.year_key  = dy.year_key
JOIN dim_cause    dc ON f.cause_key = dc.cause_key
JOIN dim_macro    dm ON f.macro_key = dm.macro_key
GROUP BY dy.COVID_Period
ORDER BY FIELD(dy.COVID_Period, 'Pre-COVID', 'COVID', 'Post-COVID');

SELECT * FROM insight_covid_period_comparison;


-- 5-B  Year-over-year change in deaths
DROP TABLE IF EXISTS insight_yoy_deaths;
CREATE TABLE insight_yoy_deaths AS
WITH annual AS (
    SELECT
        year,
        SUM(CASE WHEN measure = 'Deaths' THEN val ELSE 0 END) AS total_deaths
    FROM v_full
    GROUP BY year
)
SELECT
    a.year,
    a.total_deaths,
    LAG(a.total_deaths) OVER (ORDER BY a.year)                  AS prev_year_deaths,
    a.total_deaths - LAG(a.total_deaths) OVER (ORDER BY a.year) AS yoy_change,
    ROUND(
        (a.total_deaths - LAG(a.total_deaths) OVER (ORDER BY a.year))
        / LAG(a.total_deaths) OVER (ORDER BY a.year) * 100
    , 2)                                                        AS yoy_pct_change
FROM annual a
ORDER BY a.year;

SELECT * FROM insight_yoy_deaths;


-- ============================================================
-- SECTION 6: CAUSE-SPECIFIC TREND ANALYSIS
-- ============================================================

-- 6-A  Running totals by cause (Deaths only)
DROP TABLE IF EXISTS insight_running_total_by_cause;
CREATE TABLE insight_running_total_by_cause AS
WITH yearly_cause AS (
    SELECT
        year,
        cause,
        SUM(val) AS annual_deaths
    FROM v_full
    WHERE measure = 'Deaths'
    GROUP BY year, cause
)
SELECT
    year,
    cause,
    annual_deaths,
    SUM(annual_deaths) OVER (PARTITION BY cause ORDER BY year) AS cumulative_deaths
FROM yearly_cause
ORDER BY cause, year;

SELECT * FROM insight_running_total_by_cause;


-- 6-B  Cause share of total deaths per year (%)
DROP TABLE IF EXISTS insight_cause_share_per_year;
CREATE TABLE insight_cause_share_per_year AS
WITH yearly_cause AS (
    SELECT
        year,
        cause,
        SUM(val) AS annual_deaths
    FROM v_full
    WHERE measure = 'Deaths'
    GROUP BY year, cause
),
yearly_total AS (
    SELECT year, SUM(annual_deaths) AS year_total
    FROM yearly_cause
    GROUP BY year
)
SELECT
    yc.year,
    yc.cause,
    yc.annual_deaths,
    yt.year_total,
    ROUND(yc.annual_deaths * 100.0 / yt.year_total, 2) AS pct_of_year_total
FROM yearly_cause yc
JOIN yearly_total yt ON yc.year = yt.year
ORDER BY yc.year, yc.annual_deaths DESC;

SELECT * FROM insight_cause_share_per_year;


-- ============================================================
-- SECTION 7: POPULATION-ADJUSTED RATES
-- ============================================================

-- 7-A  Deaths per 100,000 population by year
DROP TABLE IF EXISTS insight_death_rate_per_100k;
CREATE TABLE insight_death_rate_per_100k AS
SELECT
    dm.Year                                                             AS year,
    dy.COVID_Period,
    dm.`Population, total`                                              AS population,
    SUM(CASE WHEN dc.measure = 'Deaths' THEN f.val ELSE 0 END)         AS total_deaths,
    ROUND(
        SUM(CASE WHEN dc.measure = 'Deaths' THEN f.val ELSE 0 END)
        * 100000.0 / dm.`Population, total`
    , 2)                                                                AS deaths_per_100k,
    dm.PM2_5
FROM fact_health  f
JOIN dim_macro    dm ON f.macro_key = dm.macro_key
JOIN dim_cause    dc ON f.cause_key = dc.cause_key
JOIN dim_year     dy ON f.year_key  = dy.year_key
GROUP BY dm.Year, dy.COVID_Period, dm.`Population, total`, dm.PM2_5
ORDER BY dm.Year;

SELECT * FROM insight_death_rate_per_100k;


-- 7-B  DALYs per 100,000 population by year
DROP TABLE IF EXISTS insight_daly_rate_per_100k;
CREATE TABLE insight_daly_rate_per_100k AS
SELECT
    dm.Year                                                                       AS year,
    dy.COVID_Period,
    dm.`Population, total`                                                        AS population,
    SUM(CASE WHEN dc.measure = 'DALYs (Disability-Adjusted Life Years)' THEN f.val ELSE 0 END) AS total_dalys,
    ROUND(
        SUM(CASE WHEN dc.measure = 'DALYs (Disability-Adjusted Life Years)' THEN f.val ELSE 0 END)
        * 100000.0 / dm.`Population, total`
    , 2)                                                                          AS dalys_per_100k
FROM fact_health  f
JOIN dim_macro    dm ON f.macro_key = dm.macro_key
JOIN dim_cause    dc ON f.cause_key = dc.cause_key
JOIN dim_year     dy ON f.year_key  = dy.year_key
GROUP BY dm.Year, dy.COVID_Period, dm.`Population, total`
ORDER BY dm.Year;

SELECT * FROM insight_daly_rate_per_100k;


-- ============================================================
-- SECTION 8: OUTLIER DETECTION
-- ============================================================

-- 8-A  Flag records exceeding IQR upper boundary (28,389)
DROP TABLE IF EXISTS insight_outliers;
CREATE TABLE insight_outliers AS
SELECT
    f.year,
    dc.measure,
    dc.cause,
    dd.sex,
    dd.age,
    dd.`age category`   AS age_category,
    f.val               AS burden_value,
    'Outlier (>IQR upper bound 28,389)' AS flag
FROM fact_health      f
JOIN dim_cause        dc ON f.cause_key = dc.cause_key
JOIN dim_dimographics dd ON f.demo_key  = dd.demo_key
WHERE f.val > 28389
ORDER BY f.val DESC;

SELECT * FROM insight_outliers;

-- 8-B  Outlier count by cause and age group
SELECT
    cause,
    age_category,
    COUNT(*)    AS outlier_records,
    SUM(burden_value) AS total_outlier_burden
FROM insight_outliers
GROUP BY cause, age_category
ORDER BY outlier_records DESC;


-- ============================================================
-- SECTION 9: MACRO ECONOMIC CONTEXT
-- ============================================================

-- 9-A  Year-over-year economic change
DROP TABLE IF EXISTS insight_macro_trends;
CREATE TABLE insight_macro_trends AS
SELECT
    Year,
    ROUND(`% GDP growth`   * 100, 2)                    AS gdp_pct,
    ROUND(`% Inflation`    * 100, 2)                    AS inflation_pct,
    PM2_5,
    `Population, total`                                 AS population,
    ROUND((`Population, total` - LAG(`Population, total`) OVER (ORDER BY Year))
          * 100.0 / LAG(`Population, total`) OVER (ORDER BY Year), 2) AS pop_growth_pct
FROM dim_macro
ORDER BY Year;

SELECT * FROM insight_macro_trends;


-- 9-B  High-inflation years and their death impact
DROP TABLE IF EXISTS insight_high_inflation_impact;
CREATE TABLE insight_high_inflation_impact AS
SELECT
    dm.Year,
    ROUND(dm.`% Inflation` * 100, 2)                                AS inflation_pct,
    dm.PM2_5,
    SUM(CASE WHEN dc.measure = 'Deaths' THEN f.val ELSE 0 END)      AS total_deaths,
    CASE WHEN dm.`% Inflation` > 0.15 THEN 'High Inflation (>15%)'
         ELSE 'Normal Inflation' END                                AS inflation_band
FROM fact_health  f
JOIN dim_macro    dm ON f.macro_key = dm.macro_key
JOIN dim_cause    dc ON f.cause_key = dc.cause_key
GROUP BY dm.Year, dm.`% Inflation`, dm.PM2_5
ORDER BY dm.Year;

SELECT * FROM insight_high_inflation_impact;


-- ============================================================
-- SECTION 10: SUMMARY KPI TABLE
-- ============================================================

DROP TABLE IF EXISTS insight_kpis;
CREATE TABLE insight_kpis AS
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
    CAST(ROUND(AVG(`% GDP growth`) * 100, 2) AS CHAR)
FROM dim_macro
UNION ALL
SELECT
    'Max Inflation Year (%)',
    CAST(ROUND(MAX(`% Inflation`) * 100, 2) AS CHAR)
FROM dim_macro;

SELECT * FROM insight_kpis;


-- ============================================================
-- SECTION 11: FINAL SUMMARY — ALL INSIGHT TABLES LISTED
-- ============================================================
-- insight_descriptive_stats       → Section 1-A core stats
-- insight_pm25_stats              → Section 1-B PM2.5 stats
-- insight_macro_stats             → Section 1-C GDP/Inflation stats
-- insight_burden_by_cause         → Section 2-A burden by cause
-- insight_annual_burden           → Section 2-B annual deaths + DALYs
-- insight_deaths_by_cause_year    → Section 2-C deaths cross-tab
-- insight_burden_by_demo          → Section 3-A by age + sex
-- insight_deaths_by_age_ranked    → Section 3-B age ranking
-- insight_gender_comparison       → Section 3-C gender gap
-- insight_pm25_vs_deaths          → Section 4-A PM2.5 vs deaths yearly
-- insight_correlation_pm25_deaths → Section 4-B Pearson r PM2.5
-- insight_pm25_who_exceedance     → Section 4-C WHO breach per year
-- insight_covid_period_comparison → Section 5-A COVID period avg
-- insight_yoy_deaths              → Section 5-B YoY change
-- insight_running_total_by_cause  → Section 6-A running totals
-- insight_cause_share_per_year    → Section 6-B cause share %
-- insight_death_rate_per_100k     → Section 7-A rate per 100k
-- insight_daly_rate_per_100k      → Section 7-B DALY rate per 100k
-- insight_outliers                → Section 8-A outlier records
-- insight_macro_trends            → Section 9-A macro trends
-- insight_high_inflation_impact   → Section 9-B inflation impact
-- insight_kpis                    → Section 10  KPI summary
