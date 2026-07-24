# VenturePulse — Biobyte Bots Hackathon 2026

A time-series forecasting project combining macroeconomic and commodity
indicators (Baltic Dry Index, Brent crude, Botswana policy rate, FAO food
prices, human capital data) into a monthly feature set, used to train and
compare a classical baseline (XGBoost) and a deep learning (LSTM) model —
LSTM is the final model used for submitted predictions; XGBoost replaced an
earlier SARIMA baseline, improving RMSE but still not outperforming the LSTM.

## Project structure

```
├── data/
│   ├── raw/            # Original source data (unmodified)
│   └── processed/      # Cleaned, merged, and feature-engineered data
├── notebooks/
│   ├── 01_merge_hackathon_data.R         # Data merging (R)
│   ├── 02_feature_engineering.ipynb
│   ├── 03_model_ets_arima.ipynb
│   ├── 04_model_dnn.ipynb
│   └── 05_hcp_granger_causality.ipynb
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

1. **01_merge_hackathon_data.R** — merges raw source datasets into a monthly feature table
3. **02_feature_engineering.ipynb** — cleans and engineers features, produces
   `data/processed/model_ready_data.csv`
4. **03_model_ets_arima.ipynb** — fits ETS and SARIMAX baseline models,
   saves diagnostic plots to `outputs/figures/`
5. **04_model_dnn.ipynb** — trains an LSTM model, saves weights to `models/`,
   saves training/prediction plots to `outputs/figures/`, and writes final
   predictions to `outputs/predictions.csv`
6. **05_hcp_granger_causality.ipynb** — uses the final LSTM predictions to
   run Granger causality analysis for the HCP linkage section

## Data sources

- Baltic Dry Index (daily)
- Brent crude oil prices (monthly)
- Botswana policy rate
- FAO Botswana food price index
- Human Capital Project indicators

## Team

Biobyte Bots — Hackathon 2026
