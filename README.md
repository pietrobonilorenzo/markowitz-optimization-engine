# Markowitz Portfolio Optimization Engine: From SQL Data Engineering to Quadratic Programming

## 1. Abstract

This project implements a complete end-to-end quantitative finance pipeline for portfolio optimization based on Harry Markowitz's Modern Portfolio Theory (MPT). The architecture bridges Data Engineering (SQL), Statistical Computing, and Operations Research (R) to construct an optimal asset allocation strategy. The engine retrieves raw historical data, computes discrete returns, generates a Monte Carlo simulation for the Efficient Frontier, and utilizes Quadratic Programming to find the mathematically exact Global Minimum Variance Portfolio.

## 2. Data Engineering & Transformation

Financial models require rigorous data preparation. Raw closing prices are insufficient due to corporate actions (e.g., stock splits, dividends). We use **Adjusted Close** prices stored in a local SQLite database.

To transition from prices to stationary returns, we compute the discrete daily return $R_t$ within the SQL query using Window Functions. Specifically, the `LAG()` function enables row-over-row calculations partitioned by asset ticker:

$$R_t = \frac{P_t - P_{t-1}}{P_{t-1}}$$

The extracted long-format data is then pivoted in R into an $T \times N$ matrix (where $T$ represents trading days and $N$ represents the number of assets), creating the vector space required for subsequent linear algebra operations.

## 3. Mathematical Framework (Statistical Engine)

The core of the optimization relies on estimating the future behavior of the assets based on historical data, assuming weak stationarity.

Let $r_i$ be the vector of historical returns for asset $i$. We compute two foundational estimators:

* **Expected Returns Vector ($\mu$):** The sample mean of each asset's returns, representing the expected reward. $\mu \in \mathbb{R}^N$
* **Covariance Matrix ($\Sigma$):** An $N \times N$ symmetric and positive semi-definite matrix. The diagonal elements $\sigma_i^2$ represent the variance (absolute risk) of individual assets, while off-diagonal elements $\sigma_{ij}$ capture the linear dependence between asset pairs.

A portfolio is defined by a weight vector $w \in \mathbb{R}^N$, subject to the budget constraint $\sum w_i = 1$. The portfolio's expected return and variance are computed through linear algebraic operations:

**Expected Portfolio Return (Dot Product):**


$$\mathbb{E}[R_p] = w^T \mu$$

**Portfolio Variance (Quadratic Form):**


$$\text{Var}(R_p) = w^T \Sigma w$$

## 4. Optimization via Quadratic Programming

While Monte Carlo simulations (also implemented in this engine) provide an excellent visual mapping of the solution space, finding the exact Global Minimum Variance Portfolio requires solving a constrained convex optimization problem.

The objective is to find the optimal weight vector $w$ that minimizes the portfolio variance, subject to specific constraints (e.g., full capital allocation and no short-selling). We formulate the following Quadratic Programming (QP) problem:

**Objective Function:**


$$\min_{w} \frac{1}{2} w^T \Sigma w$$

**Subject to Constraints:**

1. **Budget Constraint (Equality):**

$$\sum_{i=1}^{N} w_i = 1$$


2. **No Short-Selling Constraint (Inequality):**

$$w_i \ge 0, \quad \forall i = 1, \dots, N$$



The algorithm uses the `quadprog` package to translate these mathematical constraints into matrix format (binding an equality vector and an identity matrix) to iteratively find the exact minimum of the quadratic surface.
Perfetto, completiamo il nostro *White Paper*. Avere una documentazione chiara su come installare ed eseguire il progetto è fondamentale: su GitHub, il 90% di chi visita una repository decide se fermarsi a leggere il codice basandosi esclusivamente sulla qualità delle istruzioni nel README.

## 5. Repository Structure

The project is organized in a modular architecture to separate data extraction, database management, and mathematical computation.

```text
.
├── data/
│   ├── AAPL.csv
│   ├── JPM.csv
│   ├── VOW3.DE.csv
│   └── MC.PA.csv
├── src/
│   ├── 01_data_downloader.R
│   ├── 02_database_setup.R
│   └── 03_portfolio_optimization.R
├── quant_portfolio.db      # SQLite database (generated locally)
└── README.md

```

## 6. Prerequisites and Installation

To run this project locally, **R** and **RStudio** are required. The engine relies on the following R packages for data retrieval, SQL interfacing, and convex optimization:

* `quantmod`: For API data extraction (Yahoo Finance).
* `RSQLite` & `DBI`: For SQLite database creation and querying.
* `dplyr` & `tidyr`: For data manipulation and matrix pivoting.
* `ggplot2`: For Monte Carlo scatter plots.
* `quadprog`: For Operations Research and Quadratic Programming.

Install all dependencies by running the following command in the R console:

```R
install.packages(c("quantmod", "RSQLite", "DBI", "dplyr", "tidyr", "ggplot2", "quadprog"))

```

## 7. How to Run the Engine

Execute the scripts in the following sequential order:

1. **Extract Data:** Run `src/01_data_downloader.R` to fetch the 5-year historical prices and save them into the `data/` directory.
2. **Build Database:** Run `src/02_database_setup.R` to aggregate the CSV files, compute the Tidy Data format, and initialize the SQLite database (`quant_portfolio.db`).
3. **Optimize Portfolio:** Run `src/03_portfolio_optimization.R` to compute the statistical estimators ($\mu$ and $\Sigma$), execute the Monte Carlo simulation, and solve the exact optimal asset allocation.

## 8. Future Enhancements

This foundational quantitative engine can be expanded in several directions:

* **Black-Litterman Model Integration:** To overcome the extreme sensitivity of Markowitz's weights to the expected returns vector by incorporating subjective market views.
* **Out-of-Sample Backtesting:** To test the strategy's robustness by optimizing the portfolio on a rolling historical window and evaluating its performance on unseen data.
* **Alternative Risk Measures:** Replacing standard deviation with Conditional Value-at-Risk (CVaR) to penalize only downside tail risk.
