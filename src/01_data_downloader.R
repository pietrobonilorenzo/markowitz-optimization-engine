

# Load the library
library(quantmod)

# Define of the tickers and the date
tickers <- c("AAPL", "JPM", "VOW3.DE", "MC.PA")
start_date <- "2021-07-11"
end_date <- "2026-07-11"

# Loop in order to download the datas 
for (ticker in tickers) {
  
  getSymbols(ticker, src = "yahoo", from = start_date, to = end_date)
  
  
  data <- get(ticker)
  

  data_df <- data.frame(Date = index(data), coredata(data))
  
  
  filename <- paste0(ticker, ".csv")
  write.csv(data_df, filename, row.names = FALSE)
  
  print(paste("Downloaded and saved:", filename))
}


