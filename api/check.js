import { fetchHistoricalData } from '../fetcher.js';
import {
  calculateWildersRSIHistory,
  calculateEMA,
  calculateMACD,
  calculateBollingerBands,
  calculateConfluenceScore
} from '../rsi.js';
import {
  enqueueAlert,
  getAlertState,
  setAlertState,
  getAllSubscribers
} from '../notifier.js';
import fs from 'fs/promises';
import path from 'path';

export default async function handler(req, res) {
  // ── Auth: Verify cron secret ──────────────────────────────────────────────
  // When triggered by cronjob.org, the secret is passed via Authorization header
  // or ?secret= query param. If CRON_SECRET is set, requests without it still
  // run checks and return data but will NOT dispatch alerts to subscribers.
  const cronSecret = process.env.CRON_SECRET;
  let isAuthorizedCron = false;

  if (cronSecret) {
    const authHeader = req.headers.authorization;
    const urlObj = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
    const querySecret = urlObj.searchParams.get('secret');
    const token = authHeader ? authHeader.replace('Bearer ', '') : querySecret;
    isAuthorizedCron = (token === cronSecret);
  } else {
    // No secret configured — treat all requests as authorized (dev mode)
    isAuthorizedCron = true;
  }

  try {
    const configPath = path.resolve(process.cwd(), 'config.json');
    const config = JSON.parse(await fs.readFile(configPath, 'utf8'));

    // ── Extract per-request params (manual check from Flutter app or web UI) ─
    const isPost = req.method === 'POST';
    const params = isPost ? (req.body || {}) : (req.query || {});

    // Support comma-separated symbols string (e.g. "GC=F,SI=F")
    let symbols = params.symbols || params.symbol;
    let tickersToScan = config.tickers;

    if (symbols) {
      const symbolsArray = typeof symbols === 'string'
        ? symbols.split(',').map(s => s.trim().toUpperCase()).filter(Boolean)
        : symbols;
      if (Array.isArray(symbolsArray) && symbolsArray.length > 0) {
        tickersToScan = symbolsArray.map(sym => ({ symbol: sym, name: sym }));
      }
    }

    const rsiPeriod = parseInt(params.rsiPeriod || config.rsiPeriod, 10);
    const overbought = parseInt(params.overbought || config.thresholds.overbought, 10);
    const oversold = parseInt(params.oversold || config.thresholds.oversold, 10);

    // Manual notification targets (passed directly in request — not from Redis)
    const manualFcmToken = params.fcmToken || null;
    const manualDiscordWebhook = params.discordWebhook || null;
    const manualEmail = params.email || null;

    // ── Load subscribers from Redis (for cron-triggered alerts) ───────────────
    // Only load when this is an authorized cron run. Subscriber list tells us
    // which tickers each user wants alerts for, and their FCM token.
    let subscribers = [];
    if (isAuthorizedCron) {
      subscribers = await getAllSubscribers();
      console.log(`[Check] Loaded ${subscribers.length} subscriber(s) from Redis.`);
    }

    const results = [];

    // ── Main check loop ───────────────────────────────────────────────────────
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
            rsi, latestClose, latestEma,
            latestBbUpper, latestBbLower,
            latestMacdHist, prevMacdHist
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

          // ── Deduplication check (Redis state) ────────────────────────────
          // Prevents spamming the same alert across consecutive cron runs or cold starts
          const currentState = await getAlertState(ticker.symbol, interval);
          const stateChanged = (currentState !== status);

          if (stateChanged) {
            // Update stored state in Redis with 45-min TTL
            await setAlertState(ticker.symbol, interval, status);
          }

          // ── Dispatch alerts ───────────────────────────────────────────────
          if (action && stateChanged) {
            const alertBase = {
              ticker: ticker.symbol,
              interval,
              rsiVal: rsi,
              confluenceScore,
              action,
            };

            let enqueued = false;

            // 1. Send to subscribers watching this ticker (cron case)
            for (const sub of subscribers) {
              // If sub has empty watchlist or explicitly includes this symbol
              if (!sub.tickers || sub.tickers.length === 0 || sub.tickers.includes(ticker.symbol)) {
                await enqueueAlert({
                  ...alertBase,
                  fcmToken: sub.fcmToken || process.env.DEFAULT_FCM_TOKEN || null,
                  discordWebhook: sub.discordWebhook || process.env.DEFAULT_DISCORD_WEBHOOK || process.env.DISCORD_WEBHOOK || null,
                  email: sub.email || process.env.DEFAULT_EMAIL || null,
                });
                enqueued = true;
              }
            }

            // 2. Send to any manually-passed targets (manual check / web UI case)
            if (manualFcmToken || manualDiscordWebhook || manualEmail) {
              await enqueueAlert({
                ...alertBase,
                fcmToken: manualFcmToken,
                discordWebhook: manualDiscordWebhook || process.env.DEFAULT_DISCORD_WEBHOOK || process.env.DISCORD_WEBHOOK || null,
                email: manualEmail || process.env.DEFAULT_EMAIL || null,
              });
              enqueued = true;
            }

            // 3. Fallback: Always dispatch to default system channels if no target matched
            if (!enqueued && isAuthorizedCron) {
              await enqueueAlert({
                ...alertBase,
                fcmToken: process.env.DEFAULT_FCM_TOKEN || null,
                discordWebhook: process.env.DEFAULT_DISCORD_WEBHOOK || process.env.DISCORD_WEBHOOK || null,
                email: process.env.DEFAULT_EMAIL || null,
              });
            }
          }

          results.push({
            symbol: ticker.symbol,
            interval,
            close: latestClose.toFixed(2),
            rsi: rsi.toFixed(2),
            confluenceScore,
            status,
            stateChanged,
            alertDispatched: !!(action && stateChanged),
          });

        } catch (err) {
          console.error(`[Check] Error for ${ticker.symbol} (${interval}):`, err.message);
        }
      }
    }

    // ── Fire-and-forget queue processor ──────────────────────────────────────
    // Triggers process-queue to flush any newly enqueued alerts without
    // blocking this response. Fire-and-forget — we don't await this.
    const host = req.headers.host || 'localhost:3000';
    const protocol = req.headers['x-forwarded-proto'] || (host.includes('localhost') ? 'http' : 'https');
    fetch(`${protocol}://${host}/api/process-queue`).catch(err => {
      console.error('[Check] Queue flush trigger failed:', err.message);
    });

    return res.status(200).json({
      success: true,
      timestamp: new Date().toISOString(),
      subscribersNotified: subscribers.length,
      results,
    });

  } catch (err) {
    console.error('[Check] Handler failed:', err.message);
    return res.status(500).json({ success: false, error: err.message });
  }
}
