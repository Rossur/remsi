import { saveSubscriber, removeSubscriber, getAllSubscribers } from '../notifier.js';

// Default tickers shown as pre-selected when a user first enables notifications
const DEFAULT_TICKERS = ['GC=F', 'SI=F'];

/**
 * POST /api/subscribe
 * Register or update a device's FCM token and watchlist.
 * Body: { fcmToken: string, tickers?: string[] }
 * - If tickers is omitted, defaults to ['GC=F', 'SI=F']
 *
 * DELETE /api/subscribe
 * Remove a device subscription entirely.
 * Body: { fcmToken: string }
 *
 * GET /api/subscribe
 * (Debug only — returns subscriber count. Remove in production if needed.)
 */
export default async function handler(req, res) {
  // ── POST — Register or update subscription ────────────────────────────────
  if (req.method === 'POST') {
    const { fcmToken, tickers } = req.body || {};

    if (!fcmToken || typeof fcmToken !== 'string' || fcmToken.length < 10) {
      return res.status(400).json({
        success: false,
        error: 'Missing or invalid fcmToken.'
      });
    }

    // Use provided tickers, fall back to defaults (Gold + Silver)
    const watchlist = Array.isArray(tickers) && tickers.length > 0
      ? tickers.map(t => t.trim().toUpperCase())
      : DEFAULT_TICKERS;

    const ok = await saveSubscriber(fcmToken, watchlist);

    if (!ok) {
      return res.status(503).json({
        success: false,
        error: 'Redis unavailable — subscription could not be saved.'
      });
    }

    return res.status(200).json({
      success: true,
      message: `Subscribed to ${watchlist.length} ticker(s): ${watchlist.join(', ')}`,
      tickers: watchlist,
    });
  }

  // ── DELETE — Unsubscribe device ───────────────────────────────────────────
  if (req.method === 'DELETE') {
    const { fcmToken } = req.body || {};

    if (!fcmToken || typeof fcmToken !== 'string') {
      return res.status(400).json({ success: false, error: 'Missing fcmToken.' });
    }

    const ok = await removeSubscriber(fcmToken);

    if (!ok) {
      return res.status(503).json({
        success: false,
        error: 'Redis unavailable — subscription could not be removed.'
      });
    }

    return res.status(200).json({ success: true, message: 'Unsubscribed successfully.' });
  }

  // ── GET — Debug: subscriber count ────────────────────────────────────────
  if (req.method === 'GET') {
    const subscribers = await getAllSubscribers();
    return res.status(200).json({
      success: true,
      count: subscribers.length,
      // Only expose token prefix + tickers, never the full token
      subscribers: subscribers.map(s => ({
        tokenPrefix: s.fcmToken.substring(0, 12) + '...',
        tickers: s.tickers,
      })),
    });
  }

  return res.status(405).json({ success: false, error: 'Method not allowed.' });
}
