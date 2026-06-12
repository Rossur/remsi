export function calculateWildersRSI(closes, period = 14) {
  if (closes.length <= period) return null;

  let changes = [];
  for (let i = 1; i < closes.length; i++) {
    changes.push(closes[i] - closes[i - 1]);
  }

  let gains = changes.map(val => val > 0 ? val : 0);
  let losses = changes.map(val => val < 0 ? -val : 0);

  // Seed averages
  let avgGain = gains.slice(0, period).reduce((a, b) => a + b, 0) / period;
  let avgLoss = losses.slice(0, period).reduce((a, b) => a + b, 0) / period;

  // Compute smoothed moving averages
  for (let i = period; i < changes.length; i++) {
    avgGain = (avgGain * (period - 1) + gains[i]) / period;
    avgLoss = (avgLoss * (period - 1) + losses[i]) / period;
  }

  if (avgLoss === 0) return 100;
  const rs = avgGain / avgLoss;
  return 100 - (100 / (1 + rs));
}

export function calculateWildersRSIHistory(closes, period = 14) {
  if (closes.length <= period) return [];

  let changes = [];
  for (let i = 1; i < closes.length; i++) {
    changes.push(closes[i] - closes[i - 1]);
  }

  let gains = changes.map(val => val > 0 ? val : 0);
  let losses = changes.map(val => val < 0 ? -val : 0);

  let rsiHistory = new Array(closes.length).fill(null);

  // Seed averages
  let avgGain = gains.slice(0, period).reduce((a, b) => a + b, 0) / period;
  let avgLoss = losses.slice(0, period).reduce((a, b) => a + b, 0) / period;

  // The first RSI point is calculated at index `period` of closes
  if (avgLoss === 0) {
    rsiHistory[period] = 100;
  } else {
    const rs = avgGain / avgLoss;
    rsiHistory[period] = 100 - (100 / (1 + rs));
  }

  // Compute smoothed moving averages
  for (let i = period; i < changes.length; i++) {
    avgGain = (avgGain * (period - 1) + gains[i]) / period;
    avgLoss = (avgLoss * (period - 1) + losses[i]) / period;
    
    if (avgLoss === 0) {
      rsiHistory[i + 1] = 100;
    } else {
      const rs = avgGain / avgLoss;
      rsiHistory[i + 1] = 100 - (100 / (1 + rs));
    }
  }

  return rsiHistory;
}

export function calculateEMA(closes, period) {
  if (closes.length < period) return new Array(closes.length).fill(null);

  const ema = new Array(closes.length).fill(null);
  const multiplier = 2 / (period + 1);

  let sum = 0;
  for (let i = 0; i < period; i++) {
    sum += closes[i];
  }
  let currentEma = sum / period;
  ema[period - 1] = currentEma;

  for (let i = period; i < closes.length; i++) {
    currentEma = (closes[i] - currentEma) * multiplier + currentEma;
    ema[i] = currentEma;
  }

  return ema;
}

export function calculateMACD(closes) {
  const ema12 = calculateEMA(closes, 12);
  const ema26 = calculateEMA(closes, 26);

  const macdLine = new Array(closes.length).fill(null);
  for (let i = 0; i < closes.length; i++) {
    if (ema12[i] !== null && ema26[i] !== null) {
      macdLine[i] = ema12[i] - ema26[i];
    }
  }

  const macdSignal = calculateEMAForArrayWithNulls(macdLine, 9);

  const macdHist = new Array(closes.length).fill(null);
  for (let i = 0; i < closes.length; i++) {
    if (macdLine[i] !== null && macdSignal[i] !== null) {
      macdHist[i] = macdLine[i] - macdSignal[i];
    }
  }

  return { macdLine, macdSignal, macdHist };
}

function calculateEMAForArrayWithNulls(arr, period) {
  const ema = new Array(arr.length).fill(null);
  
  let firstValidIndex = 0;
  while (firstValidIndex < arr.length && arr[firstValidIndex] === null) {
    firstValidIndex++;
  }

  if (arr.length - firstValidIndex < period) return ema;

  const multiplier = 2 / (period + 1);
  let sum = 0;
  for (let i = 0; i < period; i++) {
    sum += arr[firstValidIndex + i];
  }
  let currentEma = sum / period;
  ema[firstValidIndex + period - 1] = currentEma;

  for (let i = firstValidIndex + period; i < arr.length; i++) {
    currentEma = (arr[i] - currentEma) * multiplier + currentEma;
    ema[i] = currentEma;
  }

  return ema;
}

export function calculateATR(highs, lows, closes, period = 14) {
  if (closes.length <= period) return new Array(closes.length).fill(null);

  const atr = new Array(closes.length).fill(null);
  const tr = new Array(closes.length).fill(0);

  tr[0] = highs[0] - lows[0];
  
  for (let i = 1; i < closes.length; i++) {
    const hl = highs[i] - lows[i];
    const hc = Math.abs(highs[i] - closes[i - 1]);
    const lc = Math.abs(lows[i] - closes[i - 1]);
    tr[i] = Math.max(hl, hc, lc);
  }

  let sum = 0;
  for (let i = 0; i < period; i++) {
    sum += tr[i];
  }
  let currentAtr = sum / period;
  atr[period - 1] = currentAtr;

  for (let i = period; i < closes.length; i++) {
    currentAtr = (currentAtr * (period - 1) + tr[i]) / period;
    atr[i] = currentAtr;
  }

  return atr;
}

export function calculateBollingerBands(closes, period = 20, numStdDev = 2) {
  const middleBand = new Array(closes.length).fill(null);
  const upperBand = new Array(closes.length).fill(null);
  const lowerBand = new Array(closes.length).fill(null);

  if (closes.length < period) return { middleBand, upperBand, lowerBand };

  for (let i = period - 1; i < closes.length; i++) {
    const slice = closes.slice(i - period + 1, i + 1);
    const sum = slice.reduce((a, b) => a + b, 0);
    const mean = sum / period;
    middleBand[i] = mean;

    const variance = slice.reduce((a, b) => a + Math.pow(b - mean, 2), 0) / period;
    const stdDev = Math.sqrt(variance);

    upperBand[i] = mean + numStdDev * stdDev;
    lowerBand[i] = mean - numStdDev * stdDev;
  }

  return { middleBand, upperBand, lowerBand };
}

export function calculateStandardDeviation(arr, period = 20) {
  const stdDev = new Array(arr.length).fill(null);
  
  for (let i = 0; i < arr.length; i++) {
    if (i < period - 1) continue;
    
    const slice = arr.slice(i - period + 1, i + 1);
    const validPoints = slice.filter(v => v !== null && v !== undefined);
    
    if (validPoints.length < period) continue;

    const mean = validPoints.reduce((a, b) => a + b, 0) / validPoints.length;
    const variance = validPoints.reduce((a, b) => a + Math.pow(b - mean, 2), 0) / validPoints.length;
    stdDev[i] = Math.sqrt(variance);
  }

  return stdDev;
}

export function scanDivergences(closes, rsi, lookback = 35) {
  const divergences = [];
  const len = closes.length;
  if (len < lookback) return divergences;

  const pivotHighs = [];
  const pivotLows = [];

  for (let i = len - lookback; i < len - 2; i++) {
    if (
      closes[i] > closes[i-1] && closes[i] > closes[i-2] &&
      closes[i] > closes[i+1] && closes[i] > closes[i+2] &&
      rsi[i] !== null
    ) {
      pivotHighs.push({ index: i, price: closes[i], rsi: rsi[i] });
    }
    if (
      closes[i] < closes[i-1] && closes[i] < closes[i-2] &&
      closes[i] < closes[i+1] && closes[i] < closes[i+2] &&
      rsi[i] !== null
    ) {
      pivotLows.push({ index: i, price: closes[i], rsi: rsi[i] });
    }
  }

  if (pivotLows.length >= 2) {
    const currentLow = pivotLows[pivotLows.length - 1];
    const previousLow = pivotLows[pivotLows.length - 2];

    if (currentLow.price < previousLow.price && currentLow.rsi > previousLow.rsi) {
      divergences.push({
        type: 'bullish',
        msg: `Bullish Divergence: Price made lower low ($${currentLow.price.toFixed(2)} vs $${previousLow.price.toFixed(2)}), but RSI made higher low (${currentLow.rsi.toFixed(1)} vs ${previousLow.rsi.toFixed(1)}). Potential upward reversal!`,
        index: currentLow.index
      });
    }
  }

  if (pivotHighs.length >= 2) {
    const currentHigh = pivotHighs[pivotHighs.length - 1];
    const previousHigh = pivotHighs[pivotHighs.length - 2];

    if (currentHigh.price > previousHigh.price && currentHigh.rsi < previousHigh.rsi) {
      divergences.push({
        type: 'bearish',
        msg: `Bearish Divergence: Price made higher high ($${currentHigh.price.toFixed(2)} vs $${previousHigh.price.toFixed(2)}), but RSI made lower high (${currentHigh.rsi.toFixed(1)} vs ${previousHigh.rsi.toFixed(1)}). Potential downward reversal!`,
        index: currentHigh.index
      });
    }
  }

  return divergences;
}

export function runBacktest(dataPoints, overbought, oversold, startingCapital = 10000) {
  if (!dataPoints || dataPoints.length === 0) {
    return {
      trades: [],
      summary: {
        startingCapital,
        endingCapital: startingCapital,
        netProfit: 0,
        strategyReturn: 0,
        buyAndHoldReturn: 0,
        totalTrades: 0,
        winRate: 0
      }
    };
  }

  let capital = startingCapital;
  let position = null;
  const trades = [];
  
  for (let i = 0; i < dataPoints.length; i++) {
    const dp = dataPoints[i];
    const prevDp = i > 0 ? dataPoints[i - 1] : null;

    const rsiVal = dp.rsi;
    const closeVal = dp.close;
    const bbLower = dp.bbLower;
    const bbUpper = dp.bbUpper;
    const macdHist = dp.macdHist;
    const prevMacdHist = prevDp ? prevDp.macdHist : null;

    let rsiSignal = 'HOLD';
    if (rsiVal !== null && rsiVal !== undefined) {
      if (rsiVal <= oversold) rsiSignal = 'BUY';
      else if (rsiVal >= overbought) rsiSignal = 'SELL';
    }

    let bbSignal = 'HOLD';
    if (bbLower !== null && bbUpper !== null && bbLower !== undefined && bbUpper !== undefined) {
      if (closeVal <= bbLower) bbSignal = 'BUY';
      else if (closeVal >= bbUpper) bbSignal = 'SELL';
    }

    let macdSignal = 'HOLD';
    if (macdHist !== null && prevMacdHist !== null && macdHist !== undefined && prevMacdHist !== undefined) {
      if (macdHist > prevMacdHist && macdHist > 0) macdSignal = 'BUY';
      else if (macdHist < prevMacdHist && macdHist < 0) macdSignal = 'SELL';
    }

    let emaSignal = 'HOLD';
    if (dp.ema !== null && dp.ema !== undefined) {
      if (closeVal > dp.ema) emaSignal = 'BUY';
      else if (closeVal < dp.ema) emaSignal = 'SELL';
    }

    dp.indicatorSignals = {
      rsi: rsiSignal,
      bb: bbSignal,
      macd: macdSignal,
      ema: emaSignal
    };

    let signal = 'HOLD';
    const isOversold = (rsiSignal === 'BUY' || bbSignal === 'BUY');
    const isOverbought = (rsiSignal === 'SELL' || bbSignal === 'SELL');
    
    // Improved logic: 
    // Buy when oversold and price crosses above EMA (trend reversal confirmed)
    // Sell when overbought or price crosses below EMA (trend reversal down)
    
    if (isOversold && emaSignal === 'BUY') {
      signal = 'BUY';
    } else if (isOverbought || (position !== null && emaSignal === 'SELL')) {
      signal = 'SELL';
    }

    dp.signal = signal;

    if (position === null) {
      if (signal === 'BUY') {
        const shares = capital / closeVal;
        position = {
          entryIndex: i,
          entryPrice: closeVal,
          entryTime: dp.time,
          shares
        };
      }
    } else {
      if (signal === 'SELL') {
        const entryPrice = position.entryPrice;
        const exitPrice = closeVal;
        const shares = position.shares;
        const grossReturn = exitPrice * shares;
        const profit = grossReturn - (shares * entryPrice);
        const returnPercent = ((exitPrice - entryPrice) / entryPrice) * 100;
        capital = grossReturn;

        trades.push({
          type: 'LONG',
          entryPrice: parseFloat(entryPrice.toFixed(2)),
          entryTime: position.entryTime,
          exitPrice: parseFloat(exitPrice.toFixed(2)),
          exitTime: dp.time,
          profit: parseFloat(profit.toFixed(2)),
          returnPercent: parseFloat(returnPercent.toFixed(2)),
          capitalAfter: parseFloat(capital.toFixed(2))
        });
        position = null;
      }
    }
  }

  const firstClose = dataPoints[0].close;
  const lastClose = dataPoints[dataPoints.length - 1].close;

  let endingCapital = capital;
  if (position !== null) {
    const entryPrice = position.entryPrice;
    const exitPrice = lastClose;
    const shares = position.shares;
    const grossReturn = exitPrice * shares;
    const profit = grossReturn - (shares * entryPrice);
    const returnPercent = ((exitPrice - entryPrice) / entryPrice) * 100;
    endingCapital = grossReturn;

    trades.push({
      type: 'LONG (OPEN)',
      entryPrice: parseFloat(entryPrice.toFixed(2)),
      entryTime: position.entryTime,
      exitPrice: parseFloat(exitPrice.toFixed(2)),
      exitTime: dataPoints[dataPoints.length - 1].time,
      profit: parseFloat(profit.toFixed(2)),
      returnPercent: parseFloat(returnPercent.toFixed(2)),
      capitalAfter: parseFloat(endingCapital.toFixed(2)),
      isOpen: true
    });
  }

  const totalTrades = trades.length;
  const winningTrades = trades.filter(t => t.profit > 0).length;
  const winRate = totalTrades > 0 ? (winningTrades / totalTrades) * 100 : 0;
  const strategyReturn = ((endingCapital - startingCapital) / startingCapital) * 100;
  const buyAndHoldReturn = ((lastClose - firstClose) / firstClose) * 100;

  return {
    trades,
    summary: {
      startingCapital: parseFloat(startingCapital.toFixed(2)),
      endingCapital: parseFloat(endingCapital.toFixed(2)),
      netProfit: parseFloat((endingCapital - startingCapital).toFixed(2)),
      strategyReturn: parseFloat(strategyReturn.toFixed(2)),
      buyAndHoldReturn: parseFloat(buyAndHoldReturn.toFixed(2)),
      totalTrades,
      winRate: parseFloat(winRate.toFixed(2))
    }
  };
}

export function calculateConfluenceScore(rsiVal, closeVal, emaVal, bbUpper, bbLower, macdHist, prevMacdHist) {
  let score = 5.5; // neutral base

  // 1. RSI contribution (neutral around 50)
  if (rsiVal !== null && rsiVal !== undefined) {
    const rsiDelta = 50 - rsiVal;
    score += (rsiDelta / 50) * 3.0;
  }

  // 2. EMA contribution
  if (closeVal !== null && emaVal !== null && emaVal !== undefined) {
    if (closeVal > emaVal) {
      score += 1.5;
    } else {
      score -= 1.5;
    }
  }

  // 3. Bollinger Bands contribution
  if (closeVal !== null && bbUpper !== null && bbLower !== null && bbUpper !== undefined && bbLower !== undefined) {
    const width = bbUpper - bbLower;
    if (width > 0) {
      const pct = (closeVal - bbLower) / width;
      score += (0.5 - pct) * 4.0;
    }
  }

  // 4. MACD contribution
  if (macdHist !== null && macdHist !== undefined) {
    if (prevMacdHist !== null && prevMacdHist !== undefined) {
      if (macdHist > 0) {
        if (macdHist > prevMacdHist) {
          score += 1.5;
        } else {
          score += 0.5;
        }
      } else {
        if (macdHist < prevMacdHist) {
          score -= 1.5;
        } else {
          score -= 0.5;
        }
      }
    } else {
      score += macdHist > 0 ? 0.75 : -0.75;
    }
  }

  // Bound between 1.0 and 10.0
  score = Math.max(1.0, Math.min(10.0, score));
  return parseFloat(score.toFixed(1));
}

