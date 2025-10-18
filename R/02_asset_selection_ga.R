# -----------------------------------------------------------
# 02_asset_selection_ga.R
# Genetic Algorithm for Asset Selection
# Author: Ankit Kothawade
# -----------------------------------------------------------

# ---- Libraries ----
library(GA)
library(tidyquant)
library(dplyr)
library(PerformanceAnalytics)
library(tidyr)

# ---- Universe ----
tickers <- c("ASML","LRCX","SHOP","SQ","UBER","ZM","AAPL","MSFT","GOOGL","AMZN",
             "META","NVDA","NFLX","ADBE","INTC","AMD","CSCO","ORCL","IBM","QCOM",
             "TXN","AVGO","PYPL","CRM","SNPS","JPM","GS","BAC","C","WFC",
             "XOM","CVX","SLB","BP","COP","OXY","NEE","D","DUK","SO")

train_start <- as.Date("2021-01-01")
train_end   <- as.Date("2023-01-01")

# ---- Data ----
prices <- tq_get(tickers, from = train_start, to = train_end)
returns <- prices %>%
  group_by(symbol) %>%
  arrange(date) %>%
  mutate(ret = adjusted / lag(adjusted) - 1) %>%
  filter(!is.na(ret)) %>%
  select(date, symbol, ret)

train <- returns %>% filter(date >= train_start, date < train_end)
train_mat <- train %>%
  pivot_wider(names_from = symbol, values_from = ret) %>%
  select(-date)
R <- as.matrix(train_mat)

# ---- Fitness Function ----
selection_fitness <- function(bits) {
  if (sum(bits) < 8) return(0)  # minimum number of stocks
  selected <- which(bits == 1)
  mu <- colMeans(R[, selected], na.rm = TRUE)
  sdv <- apply(R[, selected], 2, sd, na.rm = TRUE)
  mean(mu / sdv)  # mean Sharpe proxy
}

# ---- Binary GA ----
ga_sel <- ga(
  type = "binary",
  fitness = selection_fitness,
  nBits = ncol(R),
  popSize = 100,
  maxiter = 300,
  run = 50,
  pmutation = 0.2
)

selected_assets <- colnames(R)[which(ga_sel@solution[1, ] == 1)]

if (!dir.exists("results")) dir.create("results")
write.csv(data.frame(Selected_Assets = selected_assets),
          "results/asset_selection_list.csv", row.names = FALSE)

cat("✅ Selected Assets:\n")
print(selected_assets)
cat("\nResults saved in results/asset_selection_list.csv\n")
