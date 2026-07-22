# VenturePulse — Biobyte Bots Hackathon 2026

A time-series forecasting project combining macroeconomic and commodity
indicators (Baltic Dry Index, Brent crude, Botswana policy rate, FAO food
prices, human capital data) into a monthly feature set, used to train and
compare ETS/ARIMA and deep learning (LSTM) forecasting models.

## Project structure

```
├── data/
│   ├── raw/            # Original source data (unmodified)
│   └── processed/      # Cleaned, merged, and feature-engineered data
├── notebooks/
│   ├── 01_...           # Data merging (R)
│   ├── 02_feature_engineering.ipynb
│   ├── 03_model_ets_arima.ipynb
│   └── 04_model_dnn.ipynb
├── models/              # Saved trained model weights (.pth)
├── outputs/
│   ├── figures/          # Generated plots
│   └── predictions.csv   # Final model predictions
├── requirements.txt
└── README.md
```

## Setup

```bash
pip install -r requirements.txt
```

## Running the notebooks

Run in order — each notebook depends on outputs from the previous one:

1. **01 (R)** — merges raw source datasets into a monthly feature table
2. **02_feature_engineering.ipynb** — cleans and engineers features, produces
   `data/processed/model_ready_data.csv`
3. **03_model_ets_arima.ipynb** — fits ETS and SARIMAX baseline models,
   saves diagnostic plots to `outputs/figures/`
4. **04_model_dnn.ipynb** — trains an LSTM model, saves weights to `models/`,
   saves training/prediction plots to `outputs/figures/`, and writes final
   predictions to `outputs/predictions.csv`

## Data sources

- Baltic Dry Index (daily)
- Brent crude oil prices (monthly)
- Botswana policy rate
- FAO Botswana food price index
- Human Capital Project indicators

## Team

Biobyte Bots — Hackathon 2026
