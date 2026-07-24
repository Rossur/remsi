import { enqueueAlert } from '../notifier.js';

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    return res.status(405).json({ success: false, error: 'Method Not Allowed' });
  }

  const {
    symbol,
    interval,
    rsi,
    confluenceScore,
    action,
    fcmToken,
    discordWebhook,
    email
  } = req.body || {};

  if (!symbol || !interval || !action) {
    return res.status(400).json({ success: false, error: 'Missing required parameters: symbol, interval, action.' });
  }

  try {
    const rsiVal = rsi ? parseFloat(rsi) : 50.0;
    const scoreVal = confluenceScore ? parseFloat(confluenceScore) : 5.5;

    await enqueueAlert({
      ticker: symbol,
      interval,
      rsiVal,
      confluenceScore: scoreVal,
      action,
      fcmToken,
      discordWebhook,
      email
    });

    // Fire-and-forget queue processor trigger
    const host = req.headers.host || 'localhost:3000';
    const protocol = req.headers.referer?.startsWith('https') ? 'https' : 'http';
    fetch(`${protocol}://${host}/api/process-queue`).catch(err => {
      console.error('[Push API Trigger] Error flushing queue:', err.message);
    });

    return res.status(200).json({ success: true, queued: true, message: 'Alert queued successfully.' });
  } catch (err) {
    console.error('Push API failed:', err.message);
    return res.status(500).json({ success: false, error: err.message });
  }
}
