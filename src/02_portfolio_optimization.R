# Load required libraries
library(DBI)
library(RSQLite)
library(dplyr)

# 1. Establish database connection
con <- dbConnect(SQLite(), "quant_portfolio.db")

tickers <- c("AAPL", "JPM", "VOW3.DE", "MC.PA")

# Initialize an empty data frame to store all historical data
all_historical_data <- data.frame()

# 2. Iterate through tickers to aggregate data into a long format (Tidy Data)
for (ticker in tickers) {
  
  # Read the individual CSV file
  temp_data <- read.csv(paste0(ticker, ".csv"))
  
  # Extract Date and Adjusted Close columns dynamically
  adj_close_col <- paste0(ticker, ".Adjusted")
  temp_data <- temp_data[, c("Date", adj_close_col)]
  
  # Standardize column names for the database
  colnames(temp_data) <- c("date", "adj_close")
  
  # Add a column to identify the asset
  temp_data$ticker <- ticker
  
  # Bind rows to the main data frame
  all_historical_data <- rbind(all_historical_data, temp_data)
}

# 3. Write the aggregated data to the SQLite database
dbWriteTable(con, "historical_prices", all_historical_data, overwrite = TRUE)

print("Database successfully created and populated!")


# --- PHASE 2: DATA EXTRACTION AND MATRIX PREPARATION ---
library(tidyr)

# 4. Extract Daily Returns using SQL
# We calculate the discrete daily returns using the LAG window function
query <- "
SELECT 
    date, 
    ticker, 
    (adj_close - LAG(adj_close, 1) OVER (PARTITION BY ticker ORDER BY date)) / 
    LAG(adj_close, 1) OVER (PARTITION BY ticker ORDER BY date) AS daily_return
FROM historical_prices;
"

returns_data_long <- dbGetQuery(con, query)

# 5. Data Transformation: Long to Wide format (Matrix representation)
returns_data_wide <- returns_data_long %>%
  select(date, ticker, daily_return) %>%
  pivot_wider(names_from = ticker, values_from = daily_return) %>%
  drop_na() # Remove the first row containing NA values (due to the LAG function)

# Isolate the numerical matrix for linear algebra operations (drop the 'date' column)
returns_matrix <- returns_data_wide[, -1]

# --- PHASE 3: STATISTICAL ENGINE (MARKOWITZ INPUTS) ---

# 6. Calculate the Expected Returns Vector (Mu)
# We use the sample mean as an estimator for the expected return
expected_returns <- colMeans(returns_matrix)

# 7. Calculate the Covariance Matrix (Sigma)
# cov() automatically computes the square, symmetric covariance matrix
cov_matrix <- cov(returns_matrix)

print("Expected Returns Vector (Mu):")
print(expected_returns)

print("Covariance Matrix (Sigma):")
print(cov_matrix)

# Clean up database connection
dbDisconnect(con)

# --- PHASE 4: MONTE CARLO SIMULATION (EFFICIENT FRONTIER) ---

# Number of random portfolios to simulate
num_portfolios <- 10000
num_assets <- length(expected_returns)

# Initialize data structures to store the results
portfolio_returns <- numeric(num_portfolios)
portfolio_risks <- numeric(num_portfolios)
portfolio_sharpe <- numeric(num_portfolios)
portfolio_weights <- matrix(nrow = num_portfolios, ncol = num_assets)
colnames(portfolio_weights) <- colnames(returns_matrix)

# Risk-free rate assumption (e.g., 0% for simplicity)
risk_free_rate <- 0.0

# Set seed for reproducibility of random numbers
set.seed(42)

# Monte Carlo Loop
for (i in 1:num_portfolios) {
  
  # 1. Generate random weights
  weights <- runif(num_assets)
  weights <- weights / sum(weights) # Normalize so they sum to 1
  
  # Store the weights
  portfolio_weights[i, ] <- weights
  
  # 2. Calculate Expected Return: w^T * Mu
  # Note: sum(w * mu) is equivalent to the dot product for 1D vectors
  port_ret <- sum(weights * expected_returns)
  portfolio_returns[i] <- port_ret
  
  # 3. Calculate Risk (Standard Deviation): sqrt(w^T * Sigma * w)
  # t() is the transpose, %*% is the matrix multiplication operator
  port_var <- t(weights) %*% cov_matrix %*% weights
  port_sd <- sqrt(port_var)
  portfolio_risks[i] <- port_sd
  
  # 4. Calculate Sharpe Ratio
  portfolio_sharpe[i] <- (port_ret - risk_free_rate) / port_sd
}

# Combine all results into a single DataFrame for visualization
simulation_results <- data.frame(
  Return = portfolio_returns,
  Risk = portfolio_risks,
  SharpeRatio = portfolio_sharpe
)

# Bind the asset weights to the results
simulation_results <- cbind(simulation_results, portfolio_weights)

print("Monte Carlo Simulation completed successfully.")

# --- PHASE 5: DATA VISUALIZATION (THE EFFICIENT FRONTIER) ---
library(ggplot2)

# 1. Identify the Optimal Portfolios
# Find the row with the maximum Sharpe Ratio
max_sharpe_portfolio <- simulation_results[which.max(simulation_results$SharpeRatio), ]

# Find the row with the minimum Risk
min_variance_portfolio <- simulation_results[which.min(simulation_results$Risk), ]

# 2. Plot the Efficient Frontier using ggplot2
frontier_plot <- ggplot(simulation_results, aes(x = Risk, y = Return, color = SharpeRatio)) +
  # Draw the 10,000 random portfolios
  geom_point(alpha = 0.5, size = 1) +
  # Apply a professional color gradient
  scale_color_viridis_c(option = "plasma", name = "Sharpe Ratio") +
  
  # Highlight the Max Sharpe Portfolio (Red Star)
  geom_point(data = max_sharpe_portfolio, aes(x = Risk, y = Return), 
             color = "red", shape = 8, size = 4) +
  
  # Highlight the Minimum Variance Portfolio (Blue Star)
  geom_point(data = min_variance_portfolio, aes(x = Risk, y = Return), 
             color = "blue", shape = 8, size = 4) +
  
  # Clean, minimalist theme
  theme_minimal() +
  labs(title = "Markowitz Efficient Frontier (Monte Carlo Simulation)",
       subtitle = "10,000 Simulated Portfolios",
       x = "Risk (Standard Deviation)",
       y = "Expected Return") +
  theme(legend.position = "right")

# Display the plot
print(frontier_plot)

# 3. Print the asset allocation for the optimal portfolios
print("--- MAXIMUM SHARPE RATIO PORTFOLIO (Optimal Risk-Adjusted Return) ---")
print(max_sharpe_portfolio)

print("--- MINIMUM VARIANCE PORTFOLIO (Absolute Lowest Risk) ---")
print(min_variance_portfolio)

# --- PHASE 6: QUADRATIC PROGRAMMING (EXACT SOLUTION) ---
library(quadprog)

num_assets <- length(expected_returns)

# 1. Setup the Objective Function inputs
# Dmat: Covariance matrix (multiplied by 2 because solve.QP minimizes 1/2*w^T*D*w)
Dmat <- 2 * cov_matrix 
# dvec: Zero vector (no linear part in our objective function)
dvec <- rep(0, num_assets) 

# 2. Setup the Constraints Matrix (Amat) step-by-step
# Column 1: Equality constraint (sum of weights = 1)
eq_constraint <- rep(1, num_assets)
# Columns 2 to N+1: Inequality constraints (Identity matrix for w_i >= 0)
ineq_constraints <- diag(num_assets)

# Combine them into a single matrix (Amat)
Amat <- cbind(eq_constraint, ineq_constraints)

# 3. Setup the limits for constraints (bvec)
# The first constraint equals 1, the others are >= 0
bvec <- c(1, rep(0, num_assets))

# 4. Solve the Quadratic Programming problem
# meq = 1 tells the solver that the FIRST constraint is an equality, the rest are inequalities
qp_solution <- solve.QP(Dmat, dvec, Amat, bvec, meq = 1)

# Extract the optimal weights and clean up rounding errors (e.g., e-17 to 0)
optimal_weights <- round(qp_solution$solution, 4)
names(optimal_weights) <- colnames(returns_matrix)

# Print the final mathematically exact portfolio
print("--- EXACT GLOBAL MINIMUM VARIANCE PORTFOLIO (Quadratic Programming) ---")
print(optimal_weights)