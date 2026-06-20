import pandas as pd
import numpy as np
import plotly.graph_objects as go
from plotly.subplots import make_subplots
import pygwalker as pyg
import warnings
warnings.filterwarnings("ignore")

# 1) LOAD + BUILD ONE CLEAN TABLE (star schema -> flat table)
cause = pd.read_csv("DIM_Cause.csv")
demo = pd.read_csv("DIM_Dimographics.csv")
macro = pd.read_csv("DIM_Macro.csv")
year = pd.read_csv("DIM_Year.csv")
fact = pd.read_csv("FACT_Health.csv")

df = (fact
      .merge(cause, on="cause_key", how="left")
      .merge(demo, on="demo_key", how="left")
      .merge(macro, on="macro_key", how="left")
      .merge(year, on="year_key", how="left"))

df = df.rename(columns={
    "val": "value", "age category": "age_group",
    "% GDP growth": "gdp_growth", "% Inflation": "inflation",
    "Population, total": "population", "PM2_5": "pm25"
})
df = df.drop(columns=["Year_x", "Year_y"])  # duplicate of 'year', already correct
df.to_csv("cairo_air_health_clean.csv", index=False)

print(f"Loaded {len(df):,} records | Years {df['year'].min()}-{df['year'].max()} | "
      f"{df['cause'].nunique()} causes | {df['measure'].nunique()} measures")


# 2) INSIGHTS
deaths = df[df["measure"] == "Deaths"]
dalys = df[df["measure"].str.contains("DALY")]

yearly = deaths.groupby("year").agg(total_deaths=("value", "sum"), pm25=("pm25", "mean"),
                                     pop=("population", "mean"), gdp=("gdp_growth", "mean"),
                                     inflation=("inflation", "mean")).reset_index()
yearly["rate_per_100k"] = yearly["total_deaths"] / yearly["pop"] * 100000
daly_yearly = dalys.groupby("year")["value"].sum().reset_index(name="total_dalys")

corr_deaths_pm25 = yearly["total_deaths"].corr(yearly["pm25"])
corr_rate_pm25 = yearly["rate_per_100k"].corr(yearly["pm25"])
corr_gdp_deaths = yearly["gdp"].corr(yearly["total_deaths"])

pre = yearly[yearly["year"] < 2020]["total_deaths"].mean()
post = yearly[yearly["year"] >= 2020]["total_deaths"].mean()
covid_change = (post - pre) / pre * 100

cause_totals = deaths.groupby("cause")["value"].sum().sort_values(ascending=False)
top_cause = cause_totals.index[0]
top_cause_share = cause_totals.iloc[0] / cause_totals.sum() * 100

age_totals = deaths.groupby("age_group")["value"].sum().sort_values(ascending=False)
top_age = age_totals.index[0]

sex_totals = deaths.groupby("sex")["value"].sum()
sex_gap_pct = abs(sex_totals.get("Male", 0) - sex_totals.get("Female", 0)) / sex_totals.sum() * 100
higher_sex = sex_totals.idxmax()

first_5y = yearly[yearly["year"] <= yearly["year"].min() + 4]["total_deaths"].mean()
last_5y = yearly[yearly["year"] >= yearly["year"].max() - 4]["total_deaths"].mean()
trend_pct = (last_5y - first_5y) / first_5y * 100

rate_first = yearly[yearly["year"] <= yearly["year"].min() + 4]["rate_per_100k"].mean()
rate_last = yearly[yearly["year"] >= yearly["year"].max() - 4]["rate_per_100k"].mean()
rate_trend_pct = (rate_last - rate_first) / rate_first * 100

pm25_first = yearly[yearly["year"] <= yearly["year"].min() + 4]["pm25"].mean()
pm25_last = yearly[yearly["year"] >= yearly["year"].max() - 4]["pm25"].mean()
pm25_trend_pct = (pm25_last - pm25_first) / pm25_first * 100

worst_year = int(yearly.loc[yearly["total_deaths"].idxmax(), "year"])
best_year = int(yearly.loc[yearly["total_deaths"].idxmin(), "year"])
cleanest_year = int(yearly.loc[yearly["pm25"].idxmin(), "year"])
dirtiest_year = int(yearly.loc[yearly["pm25"].idxmax(), "year"])

cause_by_age = deaths.groupby(["age_group", "cause"])["value"].sum().reset_index()
worst_combo = cause_by_age.loc[cause_by_age["value"].idxmax()]

daly_vs_death_ratio = dalys["value"].sum() / deaths["value"].sum()

covid_period_avg = deaths.groupby("COVID_Period")["value"].sum()
period_order = ["Pre-COVID", "COVID", "Post-COVID"]
covid_period_avg = covid_period_avg.reindex([p for p in period_order if p in covid_period_avg.index])

print("\n" + "=" * 70)
print("KEY INSIGHTS")
print("=" * 70)
print(f"1. PM2.5 vs Deaths correlation: {corr_deaths_pm25:.2f}")
print(f"2. PM2.5 vs Death-RATE correlation (population-adjusted): {corr_rate_pm25:.2f}")
print(f"3. GDP growth vs Deaths correlation: {corr_gdp_deaths:.2f}")
print(f"4. COVID period (2020+) raw deaths changed {covid_change:+.1f}% vs pre-COVID")
print(f"5. Deadliest disease overall: {top_cause} ({top_cause_share:.1f}% of all deaths)")
print(f"6. Most affected age group: {top_age} ({age_totals.iloc[0]:,.0f} total)")
print(f"7. Highest-risk single combo: {worst_combo['age_group']} + {worst_combo['cause']}")
print(f"8. {higher_sex}s carry {sex_gap_pct:.1f}% more of the death burden than the other sex")
print(f"9. Raw death trend: {trend_pct:+.1f}% (first 5yrs vs last 5yrs)")
print(f"10. Population-adjusted death RATE trend: {rate_trend_pct:+.1f}% (the real story)")
print(f"11. PM2.5 trend: {pm25_trend_pct:+.1f}% (first 5yrs vs last 5yrs)")
print(f"12. Worst year (deaths): {worst_year} | Best year: {best_year}")
print(f"13. Dirtiest air year: {dirtiest_year} | Cleanest air year: {cleanest_year}")
print(f"14. Every death carries ~{daly_vs_death_ratio:.1f} DALYs (years of healthy life lost)")


# 3) RECOMMENDATIONS
recs = []
recs.append(f"PM2.5 and the population-adjusted death rate correlate at {corr_rate_pm25:.2f} — "
            f"this is the cleanest signal in the dataset. Frame every clean-air policy pitch "
            f"around this number, it's harder to argue against than raw counts.")
if covid_change < 0:
    recs.append("Lockdown years show a real drop in deaths — use this as living proof that "
                "cutting traffic/industrial activity for even a year measurably saves lives. "
                "Push for permanent low-emission zones in high-traffic Cairo districts.")
else:
    recs.append("Deaths kept climbing even through COVID lockdowns — pollution exposure looks "
                "chronic and structural, not just traffic-driven. Investigate indoor air and "
                "industrial point sources, not only vehicles.")
recs.append(f"Raw death counts moved {trend_pct:+.1f}% but the population-adjusted RATE moved "
            f"{rate_trend_pct:+.1f}% — always report the rate, not the count, or population "
            f"growth alone will make every report look worse than reality.")
recs.append(f"{top_cause} alone accounts for {top_cause_share:.1f}% of deaths — this is where "
            f"a single intervention (screening, subsidized inhalers, vaccination drives) "
            f"buys the most lives per dollar spent.")
recs.append(f"{worst_combo['age_group']} dying from {worst_combo['cause']} is the single "
            f"riskiest combination in the data — design one targeted program for exactly "
            f"this group instead of spreading budget evenly across all ages.")
if sex_gap_pct > 5:
    recs.append(f"{higher_sex}s carry {sex_gap_pct:.1f}% more of the burden — check "
                f"occupational exposure (outdoor labor, smoking rates, commute patterns) "
                f"as a likely driver before assuming it's purely biological.")
if pm25_trend_pct < 0:
    recs.append("PM2.5 has been trending down for years — whatever air policy exists is "
                "working. Publicize this win, it builds public support to keep funding it.")
else:
    recs.append("PM2.5 is trending up — current mitigation is not winning. Escalate "
                "enforcement on emission sources now, before health costs compound further.")
recs.append(f"{dirtiest_year} had the worst air and {worst_year} had the most deaths — pull "
            f"city records for that window (construction surges, heatwaves, policy gaps) to "
            f"find the specific trigger event, then build an early-warning system around it.")
recs.append(f"Each death in this dataset carries roughly {daly_vs_death_ratio:.0f} DALYs — "
            f"respiratory disease isn't just killing people, it's draining years of healthy "
            f"life from survivors. Health budgets should weight DALYs, not just death counts.")
recs.append("Build a simple early-warning dashboard: when PM2.5 crosses last year's 75th "
            "percentile for 3+ consecutive days, auto-alert hospitals to stock up on "
            "respiratory medication and staff extra ER capacity.")
recs.append("GDP growth and death trends move independently here — economic growth alone "
            "won't fix this. Air quality needs its own dedicated budget line, not a hope "
            "that prosperity trickles down into cleaner lungs.")

print("\n" + "=" * 70)
print("RECOMMENDATIONS")
print("=" * 70)
for i, r in enumerate(recs, 1):
    print(f"{i}. {r}")


# 4) CHART THEME — dark, modern, consistent across all figures

BG = "#11151c"
PANEL = "#161b24"
GRID = "#232a36"
TEXT = "#cdd6e3"
MUTED = "#7c8aa0"
ACCENT_AMBER = "#ff9f43"
ACCENT_RED = "#ff5e5e"
ACCENT_TEAL = "#23d3c4"
ACCENT_BLUE = "#5b8def"
ACCENT_PURPLE = "#a78bfa"
PALETTE = [ACCENT_AMBER, ACCENT_TEAL, ACCENT_BLUE, ACCENT_PURPLE, ACCENT_RED, "#f4d35e"]

_first_chart = {"done": False}

def style(fig, height=380):
    fig.update_layout(
        height=height, paper_bgcolor=PANEL, plot_bgcolor=PANEL,
        font=dict(family="Inter, Segoe UI, sans-serif", color=TEXT, size=12),
        margin=dict(l=50, r=30, t=50, b=40),
        legend=dict(bgcolor="rgba(0,0,0,0)", font=dict(color=MUTED)),
        title=dict(font=dict(size=15, color=TEXT)),
    )
    fig.update_xaxes(gridcolor=GRID, zerolinecolor=GRID, linecolor=GRID, color=MUTED)
    fig.update_yaxes(gridcolor=GRID, zerolinecolor=GRID, linecolor=GRID, color=MUTED)
    include_js = "cdn" if not _first_chart["done"] else False
    _first_chart["done"] = True
    return fig.to_html(full_html=False, include_plotlyjs=include_js, config={"displaylogo": False})

# Chart 1: Deaths vs PM2.5 dual-axis
fig1 = make_subplots(specs=[[{"secondary_y": True}]])
fig1.add_trace(go.Scatter(x=yearly["year"], y=yearly["total_deaths"], name="Deaths",
                           mode="lines+markers", line=dict(color=ACCENT_RED, width=3),
                           marker=dict(size=7)))
fig1.add_trace(go.Scatter(x=yearly["year"], y=yearly["pm25"], name="PM2.5 (µg/m³)",
                           mode="lines+markers", line=dict(color=ACCENT_AMBER, width=2, dash="dot"),
                           marker=dict(size=6)), secondary_y=True)
fig1.update_layout(title="Deaths vs PM2.5 Over Time")
c1 = style(fig1)

# Chart 2: Population-adjusted death rate (the real trend)
fig2 = go.Figure()
fig2.add_trace(go.Scatter(x=yearly["year"], y=yearly["rate_per_100k"], fill="tozeroy",
                           line=dict(color=ACCENT_TEAL, width=3),
                           fillcolor="rgba(35,211,196,0.15)", name="Deaths per 100k"))
fig2.update_layout(title="Death Rate per 100,000 People (Population-Adjusted)")
c2 = style(fig2)

# Chart 3: Cause share donut
fig3 = go.Figure(go.Pie(labels=cause_totals.index, values=cause_totals.values, hole=0.55,
                         marker=dict(colors=PALETTE), textfont=dict(color=TEXT)))
fig3.update_layout(title="Share of Deaths by Cause")
c3 = style(fig3)

# Chart 4: Age group horizontal bar
age_sorted = age_totals.sort_values()
fig4 = go.Figure(go.Bar(x=age_sorted.values, y=age_sorted.index, orientation="h",
                         marker=dict(color=age_sorted.values, colorscale=[[0, ACCENT_BLUE], [1, ACCENT_RED]])))
fig4.update_layout(title="Deaths by Age Group")
c4 = style(fig4)

# Chart 5: Sex split donut
fig5 = go.Figure(go.Pie(labels=sex_totals.index, values=sex_totals.values, hole=0.55,
                         marker=dict(colors=[ACCENT_BLUE, ACCENT_PURPLE]), textfont=dict(color=TEXT)))
fig5.update_layout(title="Deaths by Sex")
c5 = style(fig5)

# Chart 6: DALYs trend
fig6 = go.Figure(go.Scatter(x=daly_yearly["year"], y=daly_yearly["total_dalys"], fill="tozeroy",
                             line=dict(color=ACCENT_PURPLE, width=3),
                             fillcolor="rgba(167,139,250,0.15)"))
fig6.update_layout(title="DALYs Trend (Years of Healthy Life Lost)")
c6 = style(fig6)

# Chart 7: COVID 3-period comparison
fig7 = go.Figure(go.Bar(x=covid_period_avg.index, y=covid_period_avg.values,
                         marker=dict(color=[ACCENT_BLUE, ACCENT_RED, ACCENT_TEAL][:len(covid_period_avg)])))
fig7.update_layout(title="Total Deaths: Pre-COVID vs COVID vs Post-COVID")
c7 = style(fig7)

# Chart 8: Heatmap age x cause
heat = cause_by_age.pivot(index="age_group", columns="cause", values="value").fillna(0)
fig8 = go.Figure(go.Heatmap(z=heat.values, x=heat.columns, y=heat.index,
                             colorscale=[[0, PANEL], [0.5, ACCENT_AMBER], [1, ACCENT_RED]],
                             colorbar=dict(title="Deaths")))
fig8.update_layout(title="Risk Heatmap — Age Group x Cause")
c8 = style(fig8, height=420)

# Chart 9: GDP growth vs deaths scatter
fig9 = go.Figure(go.Scatter(x=yearly["gdp"]*100, y=yearly["total_deaths"], mode="markers+text",
                             text=yearly["year"], textposition="top center",
                             marker=dict(size=12, color=ACCENT_TEAL, line=dict(width=1, color=TEXT))))
fig9.update_layout(title="GDP Growth (%) vs Total Deaths", xaxis_title="GDP growth %", yaxis_title="Deaths")
c9 = style(fig9)

# Chart 10: PM2.5 trend bar with color ramp
fig10 = go.Figure(go.Bar(x=yearly["year"], y=yearly["pm25"],
                          marker=dict(color=yearly["pm25"], colorscale=[[0, ACCENT_TEAL], [1, ACCENT_RED]])))
fig10.update_layout(title="PM2.5 Levels by Year (µg/m³)")
c10 = style(fig10)


# 5) PYGWALKER FREE EXPLORER
walker_html = pyg.to_html(df, env="jupyter", dark="dark")


# 6) ASSEMBLE FINAL HTML — modern dark UI shell

kpi_cards = [
    ("PM2.5 ↔ Death Rate", f"{corr_rate_pm25:.2f}", "correlation strength", ACCENT_TEAL),
    ("Top Killer", top_cause, f"{top_cause_share:.1f}% of all deaths", ACCENT_RED),
    ("Death Rate Trend", f"{rate_trend_pct:+.1f}%", "population-adjusted, long-term", ACCENT_AMBER),
    ("Most At Risk", top_age, "by total deaths", ACCENT_BLUE),
    ("Worst Year", str(worst_year), "highest death toll", ACCENT_PURPLE),
    ("DALYs per Death", f"{daly_vs_death_ratio:.1f}", "years of healthy life lost", "#f4d35e"),
]

kpi_html = "".join(f"""
<div class="kpi" style="--accent:{color}">
  <span class="kpi-label">{label}</span>
  <span class="kpi-value">{value}</span>
  <span class="kpi-sub">{sub}</span>
</div>""" for label, value, sub, color in kpi_cards)

recs_html = "".join(f'<li><span class="rec-num">{i:02d}</span><span>{r}</span></li>'
                     for i, r in enumerate(recs, 1))

insights_html = "".join(f"<li>{txt}</li>" for txt in [
    f"PM2.5 vs death rate correlation: <b>{corr_rate_pm25:.2f}</b> — population-adjusted, the cleanest signal in the data",
    f"COVID-era raw deaths changed <b>{covid_change:+.1f}%</b> vs pre-COVID",
    f"Top killer: <b>{top_cause}</b> at <b>{top_cause_share:.1f}%</b> of all deaths",
    f"Highest-risk combo: <b>{worst_combo['age_group']}</b> + <b>{worst_combo['cause']}</b>",
    f"{higher_sex}s carry <b>{sex_gap_pct:.1f}%</b> more of the death burden",
    f"Population-adjusted death RATE trend: <b>{rate_trend_pct:+.1f}%</b> long-term",
    f"PM2.5 trend: <b>{pm25_trend_pct:+.1f}%</b> long-term",
    f"Dirtiest air year: <b>{dirtiest_year}</b> | Cleanest: <b>{cleanest_year}</b>",
    f"Each death carries roughly <b>{daly_vs_death_ratio:.1f}</b> DALYs",
    f"GDP growth vs deaths correlation: <b>{corr_gdp_deaths:.2f}</b> — economic growth alone doesn't fix this",
])

html = f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Cairo Air Quality & Respiratory Health</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&family=JetBrains+Mono:wght@500&display=swap" rel="stylesheet">
<style>
  :root {{
    --bg: {BG}; --panel: {PANEL}; --grid: {GRID}; --text: {TEXT}; --muted: {MUTED};
    --amber: {ACCENT_AMBER}; --red: {ACCENT_RED}; --teal: {ACCENT_TEAL}; --blue: {ACCENT_BLUE};
  }}
  * {{ box-sizing: border-box; margin: 0; padding: 0; }}
  body {{
    background: radial-gradient(ellipse 80% 50% at 50% -10%, rgba(255,159,67,0.12), transparent),
                radial-gradient(ellipse 60% 40% at 90% 10%, rgba(35,211,196,0.08), transparent),
                var(--bg);
    color: var(--text); font-family: 'Inter', sans-serif; min-height: 100vh;
    background-attachment: fixed;
  }}
  .wrap {{ max-width: 1320px; margin: 0 auto; padding: 48px 28px 80px; }}
  header {{ margin-bottom: 40px; }}
  .eyebrow {{
    font-family: 'JetBrains Mono', monospace; font-size: 12px; letter-spacing: 2px;
    color: var(--teal); text-transform: uppercase; margin-bottom: 14px; display: block;
  }}
  h1 {{
    font-size: clamp(32px, 5vw, 52px); font-weight: 800; line-height: 1.05;
    background: linear-gradient(120deg, #fff 0%, var(--amber) 55%, var(--red) 100%);
    -webkit-background-clip: text; background-clip: text; color: transparent;
    margin-bottom: 14px; letter-spacing: -0.02em;
  }}
  .subtitle {{ color: var(--muted); font-size: 16px; max-width: 640px; line-height: 1.6; }}

  .kpi-grid {{
    display: grid; grid-template-columns: repeat(6, 1fr); gap: 14px; margin: 36px 0 48px;
  }}
  @media (max-width: 1100px) {{ .kpi-grid {{ grid-template-columns: repeat(3, 1fr); }} }}
  @media (max-width: 640px) {{ .kpi-grid {{ grid-template-columns: repeat(2, 1fr); }} }}
  .kpi {{
    background: linear-gradient(160deg, var(--panel) 0%, rgba(255,255,255,0.02) 100%);
    border: 1px solid var(--grid); border-radius: 14px; padding: 18px 16px;
    display: flex; flex-direction: column; gap: 6px; position: relative; overflow: hidden;
  }}
  .kpi::before {{
    content: ''; position: absolute; top: 0; left: 0; width: 3px; height: 100%;
    background: var(--accent);
  }}
  .kpi-label {{ font-size: 11px; color: var(--muted); text-transform: uppercase; letter-spacing: 1px; font-weight: 600; }}
  .kpi-value {{ font-size: 22px; font-weight: 700; color: var(--accent); line-height: 1.2; }}
  .kpi-sub {{ font-size: 12px; color: var(--muted); }}

  .section-title {{
    font-size: 13px; font-weight: 700; text-transform: uppercase; letter-spacing: 1.5px;
    color: var(--muted); margin: 56px 0 18px; display: flex; align-items: center; gap: 12px;
  }}
  .section-title::after {{ content: ''; flex: 1; height: 1px; background: var(--grid); }}

  .chart-grid {{ display: grid; grid-template-columns: repeat(2, 1fr); gap: 18px; }}
  .chart-grid.wide {{ grid-template-columns: 1fr; }}
  @media (max-width: 900px) {{ .chart-grid {{ grid-template-columns: 1fr; }} }}
  .chart-card {{
    background: var(--panel); border: 1px solid var(--grid); border-radius: 16px;
    padding: 8px; overflow: hidden;
  }}

  .two-col {{ display: grid; grid-template-columns: 1.1fr 0.9fr; gap: 28px; }}
  @media (max-width: 900px) {{ .two-col {{ grid-template-columns: 1fr; }} }}

  .insight-card, .rec-card {{
    background: linear-gradient(160deg, var(--panel) 0%, rgba(255,255,255,0.015) 100%);
    border: 1px solid var(--grid); border-radius: 16px; padding: 28px;
  }}
  .insight-card ul {{ list-style: none; display: flex; flex-direction: column; gap: 14px; }}
  .insight-card li {{
    font-size: 14px; color: var(--muted); line-height: 1.6; padding-left: 18px;
    border-left: 2px solid var(--teal); position: relative;
  }}
  .insight-card li b {{ color: var(--text); }}

  .rec-card ol, .rec-card ul {{ list-style: none; display: flex; flex-direction: column; gap: 16px; }}
  .rec-card li {{ display: flex; gap: 14px; font-size: 14px; color: var(--muted); line-height: 1.6; }}
  .rec-num {{
    font-family: 'JetBrains Mono', monospace; font-weight: 600; color: var(--amber);
    font-size: 13px; flex-shrink: 0; padding-top: 1px;
  }}

  .explorer-wrap {{
    background: var(--panel); border: 1px solid var(--grid); border-radius: 16px;
    padding: 20px; margin-top: 12px;
  }}

  footer {{ text-align: center; color: var(--muted); font-size: 12px; margin-top: 60px; }}
</style>
</head>
<body>
<div class="wrap">

  <header>
    <span class="eyebrow">Cairo &middot; 2010&ndash;2023 &middot; Respiratory Health Dataset</span>
    <h1>Air Quality & Respiratory Health</h1>
    <p class="subtitle">Fourteen years of PM2.5 exposure mapped against deaths and DALYs across
    age, sex, and disease — turned into one place to spot the pattern and act on it.</p>
  </header>

  <section class="kpi-grid">{kpi_html}</section>

  <div class="section-title">Trends</div>
  <div class="chart-grid">
    <div class="chart-card">{c1}</div>
    <div class="chart-card">{c2}</div>
  </div>

  <div class="section-title">Who Is Affected</div>
  <div class="chart-grid">
    <div class="chart-card">{c3}</div>
    <div class="chart-card">{c4}</div>
    <div class="chart-card">{c5}</div>
    <div class="chart-card">{c6}</div>
  </div>

  <div class="section-title">Risk Concentration</div>
  <div class="chart-grid wide">
    <div class="chart-card">{c8}</div>
  </div>

  <div class="section-title">Context & Drivers</div>
  <div class="chart-grid">
    <div class="chart-card">{c7}</div>
    <div class="chart-card">{c9}</div>
  </div>

  <div class="section-title">Pollution Over Time</div>
  <div class="chart-grid wide">
    <div class="chart-card">{c10}</div>
  </div>

  <div class="section-title">Findings & Action Plan</div>
  <div class="two-col">
    <div class="rec-card">
      <ol>{recs_html}</ol>
    </div>
    <div class="insight-card">
      <ul>{insights_html}</ul>
    </div>
  </div>

  <div class="section-title">Explore It Yourself</div>
  <div class="explorer-wrap">{walker_html}</div>

  <footer>Built from Cairo air quality & health records · PM2.5, WHO/IQAir, IHME GBD, World Bank</footer>
</div>
</body></html>"""

with open("cairo_air_health_dashboard.html", "w", encoding="utf-8") as f:
    f.write(html)

print("\nSaved: cairo_air_health_dashboard.html (open in browser)")
print("Saved: cairo_air_health_clean.csv (flat merged table)")