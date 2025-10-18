# -----------------------------------------------------------
# 01_portfolio_optimization.R
# Portfolio Optimization using Genetic Algorithms (Full Version)
# Author: Ankit Kothawade
# -----------------------------------------------------------

library(GA)
library(tidyquant)
library(dplyr)
library(tidyr)
library(PerformanceAnalytics)
library(ggplot2)

# ---- Parameters ----
tickers <- c("ORCL","IBM","UNH","ABBV","CVX","NEE","NKE","COST","JPM","GS")
train_start <- as.Date("2021-01-01")
train_end   <- as.Date("2023-01-01")
test_end    <- as.Date("2024-01-01")
lambda_default <- 0.5
n_random <- 100

# ---- Create results folder ----
if (!dir.exists("results")) dir.create("results")

# ---- Data ----
prices <- tq_get(tickers, from = train_start, to = test_end)
returns <- prices %>%
  group_by(symbol) %>%
  arrange(date) %>%
  mutate(ret = adjusted / lag(adjusted) - 1) %>%
  filter(!is.na(ret)) %>%
  select(date, symbol, ret)

train <- returns %>% filter(date >= train_start, date < train_end)
test  <- returns %>% filter(date >= train_end,   date < test_end)

train_mat <- train %>%
  pivot_wider(names_from = symbol, values_from = ret) %>%
  select(-date)
test_mat <- test %>%
  pivot_wider(names_from = symbol, values_from = ret) %>%
  select(-date)

R_train <- as.matrix(train_mat)
R_test  <- as.matrix(test_mat)
n <- ncol(R_train)

# ---- Fitness Function ----
fitness_function <- function(weights, R, lambda = lambda_default) {
  w <- weights / sum(weights)
  mu <- colMeans(R, na.rm = TRUE)
  port_ret  <- sum(w * mu)
  port_risk <- sqrt(t(w) %*% cov(R, use = "pairwise.complete.obs") %*% w)
  ((1 - lambda) * port_ret) - (lambda * port_risk)
}

# ---- Train GA ----
ga_opt <- ga(
  type = "real-valued",
  fitness = function(w) fitness_function(w, R_train, lambda_default),
  lower = rep(0, n),
  upper = rep(1, n),
  popSize = 50,
  maxiter = 100,
  run = 50
)

w_opt <- as.numeric(ga_opt@solution)
w_opt <- w_opt / sum(w_opt)
write.csv(data.frame(Stock = colnames(R_train), Weight = round(w_opt, 3)),
          "results/optimized_weights.csv", row.names = FALSE)

# ---- Train/Test Evaluation ----
evaluate_portfolio <- function(w, R) {
  w <- w / sum(w)
  mu <- colMeans(R, na.rm = TRUE)
  ret <- sum(w * mu)
  risk <- sqrt(t(w) %*% cov(R, use = "pairwise.complete.obs") %*% w)
  sharpe <- ret / risk
  c(Return = ret, Risk = risk, Sharpe = sharpe)
}

train_eval <- evaluate_portfolio(w_opt, R_train)
test_eval  <- evaluate_portfolio(w_opt, R_test)

# ---- Annualized metrics ----
annualize <- function(ret, risk, periods = 252) {
  c(Annual_Return = ret * periods, Annual_Risk = risk * sqrt(periods))
}
train_ann <- annualize(train_eval["Return"], train_eval["Risk"])
test_ann  <- annualize(test_eval["Return"], test_eval["Risk"])

summary_df <- data.frame(
  Dataset = c("Train", "Test"),
  Return = c(train_eval["Return"], test_eval["Return"]),
  Risk = c(train_eval["Risk"], test_eval["Risk"]),
  Sharpe = c(train_eval["Sharpe"], test_eval["Sharpe"]),
  Annual_Return = c(train_ann["Annual_Return"], test_ann["Annual_Return"]),
  Annual_Risk = c(train_ann["Annual_Risk"], test_ann["Annual_Risk"])
)
write.csv(summary_df, "results/performance_summary.csv", row.names = FALSE)

# ---- Equal-weight baseline ----
w_eq <- rep(1 / n, n)
eq_train <- evaluate_portfolio(w_eq, R_train)
eq_test  <- evaluate_portfolio(w_eq, R_test)

# ---- Random baseline ----
set.seed(7)
random_metrics <- replicate(n_random, {
  w <- runif(n)
  w <- w / sum(w)
  c(evaluate_portfolio(w, R_train), evaluate_portfolio(w, R_test))
})
random_df <- data.frame(t(random_metrics))
colnames(random_df) <- c("train_ret","train_risk","train_sharpe",
                         "test_ret","test_risk","test_sharpe")
write.csv(random_df, "results/random_baseline.csv", row.names = FALSE)

# ---- Lambda Sweep ----
lambdas <- c(0.2, 0.4, 0.6, 0.8, 1.0)
lambda_results <- data.frame()
for (lam in lambdas) {
  ga_temp <- ga(
    type = "real-valued",
    fitness = function(w) fitness_function(w, R_train, lambda = lam),
    lower = rep(0, n),
    upper = rep(1, n),
    popSize = 50,
    maxiter = 100,
    run = 50
  )
  w <- as.numeric(ga_temp@solution)
  w <- w / sum(w)
  tr <- evaluate_portfolio(w, R_train)
  te <- evaluate_portfolio(w, R_test)
  lambda_results <- rbind(lambda_results,
                          data.frame(lambda = lam,
                                     Train_Return = tr["Return"],
                                     Train_Risk = tr["Risk"],
                                     Train_Sharpe = tr["Sharpe"],
                                     Test_Return = te["Return"],
                                     Test_Risk = te["Risk"],
                                     Test_Sharpe = te["Sharpe"]))
}
write.csv(lambda_results, "results/lambda_sweep.csv", row.names = FALSE)

# ---- Visualization ----
png("results/ga_generations.png", width = 700, height = 450)
plot(ga_opt, main = "GA Evolution – Portfolio Fitness (λ=0.5)")
dev.off()

cat("✅ Portfolio Optimization completed!\n")
cat("Results saved in /results folder\n")

