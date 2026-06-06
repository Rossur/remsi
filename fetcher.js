export async function fetchHistoricalData(ticker, interval) {
  const url = `https://query1.finance.yahoo.com/v8/finance/chart/${ticker}?range=2d&interval=${interval}`;
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Failed to fetch data for ${ticker}: ${response.statusText}`);
  }
  const data = await response.json();
  const result = data.chart?.result?.[0];
  if (!result) throw new Error(`Invalid data format for ${ticker}`);

  const rawCloses = result.indicators?.quote?.[0]?.close || [];
  
  // Forward-fill null values if trading was halted briefly
  const closes = [];
  let lastValidPrice = null;
  for (let price of rawCloses) {
    if (price !== null && price !== undefined) {
      lastValidPrice = price;
    }
    if (lastValidPrice !== null) {
      closes.push(lastValidPrice);
    }
  }

  return closes;
}
