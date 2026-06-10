import { fetchHistoricalData } from '../fetcher.js';
import { calculateWildersRSI } from '../rsi.js';
import { sendAlert } from '../notifier.js';
import fs from 'fs/promises';
import path from 'path';

export default async function handler(req, res) {
  // Enforce CRON_SECRET check if configured
  const cronSecret = process.env.CRON_SECRET;
  if (cronSecret) {
    const authHeader = req.headers.authorization;
    const urlObj = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
    const querySecret = urlObj.searchParams.get('secret');
    const token = authHeader ? authHeader.replace('Bearer ', '') : querySecret;

    if (token !== cronSecret) {
      return res.status(401).json({ success: false, error: 'Unauthorized' });
    }
  }

  try {
    const configPath = path.resolve(process.cwd(), 'config.json');
    const config = JSON.parse(await fs.readFile(configPath, 'utf8'));
    const results = [];

    for (const ticker of config.tickers) {
      for (const interval of config.intervals) {
        try {
          const closes = await fetchHistoricalData(ticker.symbol, interval);
          const rsi = calculateWildersRSI(closes, config.rsiPeriod);

          if (rsi === null) continue;

          const latestClose = closes[closes.length - 1];
          let status = 'normal';

          if (rsi <= config.thresholds.oversold) {
            status = 'oversold';
            sendAlert(`${ticker.name} RSI on ${interval} is OVERSOLD: ${rsi.toFixed(2)}`);
          } else if (rsi >= config.thresholds.overbought) {
            status = 'overbought';
            sendAlert(`${ticker.name} RSI on ${interval} is OVERBOUGHT: ${rsi.toFixed(2)}`);
          }

          results.push({
            symbol: ticker.symbol,
            interval,
            close: latestClose.toFixed(2),
            rsi: rsi.toFixed(2),
            status
          });
        } catch (err) {
          console.error(`Error checking ${ticker.name} (${interval}):`, err.message);
        }
      }
    }

    // Return the results as JSON so you can manually view them by visiting the URL
    res.status(200).json({ success: true, timestamp: new Date().toISOString(), results });
  } catch (err) {
    console.error('Check failed:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
}
