import { fetchHistoricalChartData } from '../fetcher.js';
import { 
  calculateWildersRSIHistory, 
  calculateEMA, 
  calculateMACD, 
  calculateATR, 
  calculateBollingerBands, 
  calculateStandardDeviation, 
  scanDivergences,
  runBacktest,
  calculateConfluenceScore
} from '../rsi.js';
import fs from 'fs/promises';
import path from 'path';

export default async function handler(req, res) {
  try {
    const configPath = path.resolve(process.cwd(), 'config.json');
    const config = JSON.parse(await fs.readFile(configPath, 'utf8'));
    
    const url = req.url || '';
    const urlObj = new URL(url, `http://${req.headers?.host || 'localhost'}`);
    const symbolParam = req.query?.symbol || urlObj.searchParams.get('symbol') || config.tickers[0].symbol;
    const intervalParam = req.query?.interval || urlObj.searchParams.get('interval') || '15m';
    
    const rsiPeriodParam = parseInt(req.query?.rsiPeriod || urlObj.searchParams.get('rsiPeriod') || config.rsiPeriod, 10);
    const overboughtParam = parseInt(req.query?.overbought || urlObj.searchParams.get('overbought') || config.thresholds.overbought, 10);
    const oversoldParam = parseInt(req.query?.oversold || urlObj.searchParams.get('oversold') || config.thresholds.oversold, 10);

    const ticker = config.tickers.find(t => t.symbol === symbolParam) || { symbol: symbolParam, name: symbolParam };
    
    const { closes, highs, lows, timestamps } = await fetchHistoricalChartData(ticker.symbol, intervalParam);
    const rsi = calculateWildersRSIHistory(closes, rsiPeriodParam);
    const ema9 = calculateEMA(closes, 9);
    const { macdLine, macdSignal, macdHist } = calculateMACD(closes);

    const atr = calculateATR(highs, lows, closes, 14);
    const { middleBand, upperBand, lowerBand } = calculateBollingerBands(closes, 20, 2);
    const rsiStdDev = calculateStandardDeviation(rsi, 20);
    const divergences = scanDivergences(closes, rsi, 35);

    const validRsis = rsi.filter(v => v !== null);
    const avgRsi = validRsis.length ? validRsis.reduce((a, b) => a + b, 0) / validRsis.length : 0;
    const latestRsiStdDev = rsiStdDev[rsiStdDev.length - 1] || 0;
    const latestAtr = atr[atr.length - 1] || 0;
    const latestPrice = closes[closes.length - 1] || 1;
    const latestAtrPercent = (latestAtr / latestPrice) * 100;

    const dataPoints = [];
    for (let i = 0; i < closes.length; i++) {
      const confScore = calculateConfluenceScore(
        rsi[i],
        closes[i],
        ema9[i],
        upperBand[i],
        lowerBand[i],
        macdHist[i],
        i > 0 ? macdHist[i - 1] : null
      );
      dataPoints.push({
        time: timestamps[i],
        close: parseFloat(closes[i].toFixed(2)),
        rsi: rsi[i] !== null && rsi[i] !== undefined ? parseFloat(rsi[i].toFixed(2)) : null,
        ema: ema9[i] !== null && ema9[i] !== undefined ? parseFloat(ema9[i].toFixed(2)) : null,
        macd: macdLine[i] !== null && macdLine[i] !== undefined ? parseFloat(macdLine[i].toFixed(2)) : null,
        macdSignal: macdSignal[i] !== null && macdSignal[i] !== undefined ? parseFloat(macdSignal[i].toFixed(2)) : null,
        macdHist: macdHist[i] !== null && macdHist[i] !== undefined ? parseFloat(macdHist[i].toFixed(2)) : null,
        bbUpper: upperBand[i] !== null && upperBand[i] !== undefined ? parseFloat(upperBand[i].toFixed(2)) : null,
        bbLower: lowerBand[i] !== null && lowerBand[i] !== undefined ? parseFloat(lowerBand[i].toFixed(2)) : null,
        bbMiddle: middleBand[i] !== null && middleBand[i] !== undefined ? parseFloat(middleBand[i].toFixed(2)) : null,
        atr: atr[i] !== null && atr[i] !== undefined ? parseFloat(atr[i].toFixed(2)) : null,
        confluenceScore: confScore
      });
    }

    const backtest = runBacktest(dataPoints, overboughtParam, oversoldParam, 10000);

    const responsePayload = {
      success: true,
      symbol: ticker.symbol,
      name: ticker.name,
      interval: intervalParam,
      rsiPeriod: rsiPeriodParam,
      thresholds: {
        overbought: overboughtParam,
        oversold: oversoldParam
      },
      stats: {
        avgRsi: parseFloat(avgRsi.toFixed(2)),
        rsiStdDev: parseFloat(latestRsiStdDev.toFixed(2)),
        latestAtr: parseFloat(latestAtr.toFixed(2)),
        latestAtrPercent: parseFloat(latestAtrPercent.toFixed(2))
      },
      divergences,
      backtest,
      dataPoints
    };

    if (typeof res.status === 'function') {
      res.status(200).json(responsePayload);
    } else {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(responsePayload));
    }
  } catch (err) {
    console.error('History API error:', err.message);
    const detailMsg = err.cause ? `${err.message} (${err.cause.message || err.cause})` : err.message;
    if (typeof res.status === 'function') {
      res.status(500).json({ success: false, error: detailMsg });
    } else {
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ success: false, error: detailMsg }));
    }
  }
}
