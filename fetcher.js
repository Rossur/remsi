function getRangeForInterval(interval) {
  switch (interval) {
    case '5m': return '2d';
    case '15m': return '5d';
    case '1h': return '14d';
    case '1d':
    case 'daily': return '3mo';
    case '1wk':
    case 'weekly': return '1y';
    default: return '5d';
  }
}

function normalizeInterval(interval) {
  if (interval === 'daily') return '1d';
  if (interval === 'weekly') return '1wk';
  return interval;
}

async function fetchWithRetry(url, options = {}, retries = 3, delay = 500) {
  const headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept': 'application/json',
    ...options.headers
  };

  for (let i = 0; i < retries; i++) {
    try {
      const response = await fetch(url, { ...options, headers });
      if (response.ok) return response;

      if (response.status === 429 || response.status >= 500) {
        console.warn(`[FETCH] Status ${response.status}. Retrying (${i + 1}/${retries})...`);
        await new Promise(res => setTimeout(res, delay * (i + 1)));
        continue;
      }
      return response;
    } catch (err) {
      if (i === retries - 1) {
        console.error(`[FETCH] Error details:`, err, err.cause);
        throw err;
      }
      console.warn(`[FETCH] Network error: ${err.message}. Retrying (${i + 1}/${retries})...`);
      await new Promise(res => setTimeout(res, delay * (i + 1)));
    }
  }
}

export async function fetchHistoricalData(ticker, interval) {
  const range = getRangeForInterval(interval);
  const apiInterval = normalizeInterval(interval);
  const url = `https://query1.finance.yahoo.com/v8/finance/chart/${ticker}?range=${range}&interval=${apiInterval}`;
  
  const response = await fetchWithRetry(url);
  if (!response.ok) {
    throw new Error(`Failed to fetch data for ${ticker}: ${response.statusText}`);
  }
  const data = await response.json();
  const result = data.chart?.result?.[0];
  if (!result) throw new Error(`Invalid data format for ${ticker}`);

  const rawCloses = result.indicators?.quote?.[0]?.close || [];
  
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

export async function fetchHistoricalChartData(ticker, interval) {
  const range = getRangeForInterval(interval);
  const apiInterval = normalizeInterval(interval);
  const url = `https://query1.finance.yahoo.com/v8/finance/chart/${ticker}?range=${range}&interval=${apiInterval}`;
  
  const response = await fetchWithRetry(url);
  if (!response.ok) {
    throw new Error(`Failed to fetch data for ${ticker}: ${response.statusText}`);
  }
  const data = await response.json();
  const result = data.chart?.result?.[0];
  if (!result) throw new Error(`Invalid data format for ${ticker}`);

  const rawCloses = result.indicators?.quote?.[0]?.close || [];
  const rawHighs = result.indicators?.quote?.[0]?.high || [];
  const rawLows = result.indicators?.quote?.[0]?.low || [];
  const rawTimestamps = result.timestamp || [];

  const closes = [];
  const highs = [];
  const lows = [];
  const timestamps = [];
  let lastValidPrice = null;
  let lastValidHigh = null;
  let lastValidLow = null;

  for (let i = 0; i < rawCloses.length; i++) {
    const price = rawCloses[i];
    const high = rawHighs[i];
    const low = rawLows[i];

    if (price !== null && price !== undefined) {
      lastValidPrice = price;
      lastValidHigh = high !== null && high !== undefined ? high : price;
      lastValidLow = low !== null && low !== undefined ? low : price;
    }
    if (lastValidPrice !== null) {
      closes.push(lastValidPrice);
      highs.push(lastValidHigh);
      lows.push(lastValidLow);
      timestamps.push(rawTimestamps[i]);
    }
  }

  return { closes, highs, lows, timestamps };
}
