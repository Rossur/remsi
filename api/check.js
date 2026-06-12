import { fetchHistoricalData } from '../fetcher.js';
import { 
  calculateWildersRSIHistory, 
  calculateEMA, 
  calculateMACD, 
  calculateBollingerBands, 
  calculateConfluenceScore 
} from '../rsi.js';
import { dispatchAlert } from '../notifier.js';
import fs from 'fs/promises';
import path from 'path';

export default async function handler(req, res) {
  const cronSecret = process.env.CRON_SECRET;
  let shouldSendAlert = true;

  // Verify cron secret for cron trigger
  if (cronSecret) {
    const authHeader = req.headers.authorization;
    const urlObj = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
    const querySecret = urlObj.searchParams.get('secret');
    const token = authHeader ? authHeader.replace('Bearer ', '') : querySecret;

    if (token !== cronSecret) {
      shouldSendAlert = false;
    }
  }

  try {
    const configPath = path.resolve(process.cwd(), 'config.json');
    const config = JSON.parse(await fs.readFile(configPath, 'utf8'));

    // Extract parameters from POST body or GET query
    const isPost = req.method === 'POST';
    const params = isPost ? (req.body || {}) : (req.query || {});
    
    // Support comma-separated symbols string
    let symbols = params.symbols || params.symbol;
    let tickersToScan = config.tickers;

    if (symbols) {
      const symbolsArray = typeof symbols === 'string' 
        ? symbols.split(',').map(s => s.trim().toUpperCase()).filter(Boolean)
        : symbols;
      
      if (Array.isArray(symbolsArray) && symbolsArray.length > 0) {
        tickersToScan = symbolsArray.map(sym => ({
          symbol: sym,
          name: sym
        }));
      }
    }

    // Custom Thresholds and periods
    const rsiPeriod = parseInt(params.rsiPeriod || config.rsiPeriod, 10);
    const overbought = parseInt(params.overbought || config.thresholds.overbought, 10);
    const oversold = parseInt(params.oversold || config.thresholds.oversold, 10);

    // Notification target coordinates
    const fcmToken = params.fcmToken || null;
    const discordWebhook = params.discordWebhook || null;
    const phoneNumber = params.phoneNumber || null;

    const results = [];

    for (const ticker of tickersToScan) {
      for (const interval of config.intervals) {
        try {
          const closes = await fetchHistoricalData(ticker.symbol, interval);
          if (!closes || closes.length === 0) continue;

          const rsiHistory = calculateWildersRSIHistory(closes, rsiPeriod);
          const rsi = rsiHistory[rsiHistory.length - 1];
          if (rsi === null || rsi === undefined) continue;

          const ema = calculateEMA(closes, 9);
          const { macdHist } = calculateMACD(closes);
          const { upperBand, lowerBand } = calculateBollingerBands(closes, 20, 2);

          const latestClose = closes[closes.length - 1];
          const latestEma = ema[ema.length - 1];
          const latestBbUpper = upperBand[upperBand.length - 1];
          const latestBbLower = lowerBand[lowerBand.length - 1];
          const latestMacdHist = macdHist[macdHist.length - 1];
          const prevMacdHist = macdHist.length > 1 ? macdHist[macdHist.length - 2] : null;

          const confluenceScore = calculateConfluenceScore(
            rsi,
            latestClose,
            latestEma,
            latestBbUpper,
            latestBbLower,
            latestMacdHist,
            prevMacdHist
          );

          let status = 'normal';
          let action = null;

          if (rsi <= oversold) {
            status = 'oversold';
            action = 'BUY';
          } else if (rsi >= overbought) {
            status = 'overbought';
            action = 'SELL';
          }

          if (action && (shouldSendAlert || fcmToken || discordWebhook || phoneNumber)) {
            // Dispatch alerts
            await dispatchAlert({
              ticker: ticker.symbol,
              interval,
              rsiVal: rsi,
              confluenceScore,
              action,
              fcmToken: fcmToken || (shouldSendAlert ? process.env.DEFAULT_FCM_TOKEN : null),
              discordWebhook: discordWebhook || (shouldSendAlert ? process.env.DEFAULT_DISCORD_WEBHOOK : null),
              phoneNumber: phoneNumber || (shouldSendAlert ? process.env.DEFAULT_PHONE_NUMBER : null)
            });
          }

          results.push({
            symbol: ticker.symbol,
            interval,
            close: latestClose.toFixed(2),
            rsi: rsi.toFixed(2),
            confluenceScore,
            status
          });
        } catch (err) {
          console.error(`Error checking ${ticker.name} (${interval}):`, err.message);
        }
      }
    }

    res.status(200).json({ success: true, timestamp: new Date().toISOString(), results });
  } catch (err) {
    console.error('Check failed:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
}

