import admin from 'firebase-admin';
import nodemailer from 'nodemailer';
import { Redis } from '@upstash/redis';

// ── Redis Client ────────────────────────────────────────────────────────────
// Lazily initialized so the app still boots without Redis configured.
// All Redis operations are no-ops when credentials are absent (falls back gracefully).

let _redis = null;
function getRedis() {
  if (_redis) return _redis;
  const url = process.env.UPSTASH_REDIS_REST_URL;
  const token = process.env.UPSTASH_REDIS_REST_TOKEN;
  if (!url || !token) {
    console.warn('[Redis] UPSTASH_REDIS_REST_URL or TOKEN not set — Redis features disabled.');
    return null;
  }
  _redis = new Redis({ url, token });
  return _redis;
}

// ── Alert Queue (Redis List: remsi:queue) ───────────────────────────────────

/**
 * Pushes an alert task onto the Redis queue.
 * Falls back to console log if Redis is not configured.
 */
export async function enqueueAlert(alertParams) {
  const redis = getRedis();

  const task = {
    id: Math.random().toString(36).substring(2, 9),
    timestamp: new Date().toISOString(),
    params: alertParams,
    retries: 0,
  };

  if (!redis) {
    console.warn('[Queue] Redis not available — alert task dropped:', JSON.stringify(task));
    return task;
  }

  await redis.rpush('remsi:queue', JSON.stringify(task));
  console.log(`[Queue] Enqueued task ${task.id} for ${alertParams.ticker} [${alertParams.interval}]`);
  return task;
}

/**
 * Atomically dequeues all tasks from the Redis queue.
 * Returns an array of parsed task objects. Returns [] if queue is empty or Redis unavailable.
 */
export async function dequeueAllAlerts() {
  const redis = getRedis();
  if (!redis) return [];

  // Get all items then clear the list atomically
  const [items] = await Promise.all([
    redis.lrange('remsi:queue', 0, -1),
    redis.del('remsi:queue'),
  ]);

  return (items || []).map(item => {
    try {
      return typeof item === 'string' ? JSON.parse(item) : item;
    } catch {
      return null;
    }
  }).filter(Boolean);
}

/**
 * Re-pushes a failed task back to the queue (for retry logic in process-queue).
 */
export async function requeueTask(task) {
  const redis = getRedis();
  if (!redis) return;
  await redis.rpush('remsi:queue', JSON.stringify(task));
}

// ── Alert Deduplication State (Redis strings with TTL) ─────────────────────
// Key pattern: remsi:state:<symbol>:<interval>
// Value: "oversold" | "overbought" | "normal"
// TTL: 45 minutes — prevents duplicate alerts across cold starts for 3 check windows

const DEDUP_TTL_SECONDS = 45 * 60; // 45 minutes

export async function getAlertState(symbol, interval) {
  const redis = getRedis();
  if (!redis) return null;
  try {
    return await redis.get(`remsi:state:${symbol}:${interval}`);
  } catch (err) {
    console.error(`[State] Failed to get state for ${symbol}:${interval}:`, err.message);
    return null;
  }
}

export async function setAlertState(symbol, interval, state) {
  const redis = getRedis();
  if (!redis) return;
  try {
    await redis.set(`remsi:state:${symbol}:${interval}`, state, { ex: DEDUP_TTL_SECONDS });
  } catch (err) {
    console.error(`[State] Failed to set state for ${symbol}:${interval}:`, err.message);
  }
}

// ── Subscriber Management (Redis Set + Hash) ────────────────────────────────
// remsi:subscribers         → Redis Set of all registered FCM tokens
// remsi:sub:<fcmToken>      → Redis JSON string { tickers: [...], createdAt, updatedAt }

export async function saveSubscriber(fcmToken, tickers) {
  const redis = getRedis();
  if (!redis) return false;
  try {
    // Add token to the global subscriber set
    await redis.sadd('remsi:subscribers', fcmToken);
    // Store the subscriber's watchlist
    await redis.set(`remsi:sub:${fcmToken}`, JSON.stringify({
      tickers,
      updatedAt: new Date().toISOString(),
    }));
    console.log(`[Subscribe] Registered ${fcmToken.substring(0, 10)}... with tickers: ${tickers.join(', ')}`);
    return true;
  } catch (err) {
    console.error('[Subscribe] Failed to save subscriber:', err.message);
    return false;
  }
}

export async function removeSubscriber(fcmToken) {
  const redis = getRedis();
  if (!redis) return false;
  try {
    await redis.srem('remsi:subscribers', fcmToken);
    await redis.del(`remsi:sub:${fcmToken}`);
    console.log(`[Unsubscribe] Removed ${fcmToken.substring(0, 10)}...`);
    return true;
  } catch (err) {
    console.error('[Unsubscribe] Failed to remove subscriber:', err.message);
    return false;
  }
}

/**
 * Returns all subscribers as: [{ fcmToken, tickers }]
 */
export async function getAllSubscribers() {
  const redis = getRedis();
  if (!redis) return [];
  try {
    const tokens = await redis.smembers('remsi:subscribers');
    if (!tokens || tokens.length === 0) return [];

    const subscribers = [];
    for (const token of tokens) {
      const raw = await redis.get(`remsi:sub:${token}`);
      if (raw) {
        const data = typeof raw === 'string' ? JSON.parse(raw) : raw;
        subscribers.push({ fcmToken: token, tickers: data.tickers || [] });
      }
    }
    return subscribers;
  } catch (err) {
    console.error('[Subscribe] Failed to read subscribers:', err.message);
    return [];
  }
}

// ── Firebase Admin SDK ──────────────────────────────────────────────────────

if (process.env.FIREBASE_SERVICE_ACCOUNT && admin.apps.length === 0) {
  try {
    const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount)
    });
    console.log('[FCM] Firebase Admin successfully initialized.');
  } catch (err) {
    console.error('[FCM] Failed to initialize Firebase Admin:', err.message);
  }
}

// ── FCM Push Notification ───────────────────────────────────────────────────

/**
 * Sends a push notification via Firebase Cloud Messaging.
 *
 * Sends BOTH a visible notification payload (banner) AND a silent data payload
 * so the Flutter app can refresh its dashboard in the background without the
 * user needing to open the app.
 */
export async function sendFCMNotification(token, title, body, dataPayload = {}) {
  if (!token) return;
  if (admin.apps.length === 0) {
    console.warn('[FCM] Firebase Admin not initialized — push notification skipped.');
    return;
  }
  try {
    await admin.messaging().send({
      token,
      // Visible notification banner on the device
      notification: { title, body },
      // Silent data payload — Flutter's onBackgroundMessage handler reads this
      // to silently refresh dashboard state without the user tapping anything
      data: {
        type: 'rsi_alert',
        title,
        body,
        timestamp: Date.now().toString(),
        ...Object.fromEntries(
          Object.entries(dataPayload).map(([k, v]) => [k, String(v)])
        ),
      },
      webpush: { headers: { Urgency: 'high' } },
      android: {
        priority: 'high',
        notification: { sound: 'default' },
      },
    });
    console.log(`[FCM] Notification sent to token: ${token.substring(0, 10)}...`);
  } catch (err) {
    // Log the full FCM error code so stale/invalid tokens can be identified
    console.error(`[FCM] Error (${err.errorInfo?.code || 'unknown'}):`, err.message);
    throw err;
  }
}

// ── SMTP Email ──────────────────────────────────────────────────────────────

let mailTransporter = null;
function getMailTransporter() {
  if (mailTransporter) return mailTransporter;
  const host = process.env.SMTP_HOST;
  const port = parseInt(process.env.SMTP_PORT || '587', 10);
  const user = process.env.SMTP_USER;
  const pass = process.env.SMTP_PASS;
  if (!host || !user || !pass) {
    console.warn('[SMTP] Missing SMTP_HOST, SMTP_USER, or SMTP_PASS — email alerts disabled.');
    return null;
  }
  mailTransporter = nodemailer.createTransport({
    host, port,
    secure: port === 465,
    auth: { user, pass }
  });
  return mailTransporter;
}

export async function sendEmailAlert(emailAddress, subject, body) {
  if (!emailAddress) return;
  const transporter = getMailTransporter();
  if (!transporter) {
    console.warn('[SMTP] Mail transporter not available — email alert skipped.');
    return;
  }
  const mailOptions = {
    from: process.env.SMTP_FROM || process.env.SMTP_USER,
    to: emailAddress,
    subject,
    text: body,
    html: `<p>${body.replace(/\n/g, '<br>')}</p>`
  };
  try {
    const info = await transporter.sendMail(mailOptions);
    console.log(`[SMTP] Email sent to ${emailAddress}. ID: ${info.messageId}`);
  } catch (err) {
    console.error('[SMTP] Error sending email:', err.message);
    throw err;
  }
}

// ── Discord Webhook ─────────────────────────────────────────────────────────

/**
 * Sends a rich Discord embed with confluence score visualised as a progress bar.
 * Phase 1c — wired but Discord integration is enabled in the next iteration.
 */
export async function sendDiscordAlert(webhookUrl, ticker, interval, rsiVal, confluenceScore, action) {
  if (!webhookUrl) return;

  const isBuy = action === 'BUY';
  const color = isBuy ? 0x00C853 : 0xD50000;
  const emoji = isBuy ? '🟢' : '🔴';

  // Visual bar: ████████░░ style (10 blocks)
  const filled = Math.round(confluenceScore);
  const bar = '█'.repeat(filled) + '░'.repeat(10 - filled);

  const embed = {
    title: `${emoji} REMSI Alert: ${ticker} (${interval})`,
    description: `**${isBuy ? 'BUY — OVERSOLD' : 'SELL — OVERBOUGHT'}** signal detected.`,
    color,
    fields: [
      { name: 'RSI', value: `\`${rsiVal.toFixed(2)}\``, inline: true },
      { name: 'Confluence', value: `\`${confluenceScore}/10\``, inline: true },
      { name: 'Score', value: `\`${bar}\``, inline: false },
    ],
    timestamp: new Date().toISOString(),
    footer: { text: 'REMSI Scanner Engine' },
  };

  try {
    const res = await fetch(webhookUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ embeds: [embed] })
    });
    if (!res.ok) throw new Error(`Discord returned status ${res.status}`);
    console.log(`[Discord] Alert sent to webhook.`);
  } catch (err) {
    console.error('[Discord] Error sending alert:', err.message);
    throw err;
  }
}

// ── Unified Alert Dispatcher ────────────────────────────────────────────────

/**
 * Dispatches an alert to all configured channels: FCM, Email, Discord.
 * Called by process-queue.js for each queued task.
 */
export async function dispatchAlert({ ticker, interval, rsiVal, confluenceScore, action, fcmToken, discordWebhook, email }) {
  const message = `REMSI: ${ticker} [${interval}] is ${action === 'BUY' ? 'OVERSOLD' : 'OVERBOUGHT'}. RSI: ${rsiVal.toFixed(2)}, Confluence: ${confluenceScore}/10`;
  console.log(`[Dispatch] ${message}`);

  const fcmData = { ticker, interval, rsi: String(rsiVal.toFixed(2)), confluenceScore: String(confluenceScore), action };
  const promises = [];

  if (fcmToken) {
    promises.push(
      sendFCMNotification(
        fcmToken,
        `REMSI Alert: ${ticker} (${interval})`,
        `${action === 'BUY' ? '🟢 Oversold' : '🔴 Overbought'} — RSI: ${rsiVal.toFixed(2)} | Score: ${confluenceScore}/10`,
        fcmData
      )
    );
  }

  if (email) {
    promises.push(sendEmailAlert(email, `REMSI Alert: ${ticker} (${interval})`, message));
  }

  if (discordWebhook) {
    promises.push(sendDiscordAlert(discordWebhook, ticker, interval, rsiVal, confluenceScore, action));
  }

  const results = await Promise.allSettled(promises);
  results.forEach((res, i) => {
    if (res.status === 'rejected') {
      console.error(`[Dispatch Channel ${i}] Failed:`, res.reason?.message || res.reason);
    }
  });
}

// ── Backward Compatibility ──────────────────────────────────────────────────

export function sendAlert(message) {
  console.log(`[LEGACY ALERT] ${message}`);
  const webhook = process.env.DEFAULT_DISCORD_WEBHOOK || process.env.DISCORD_WEBHOOK;
  if (webhook) {
    fetch(webhook, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ content: message })
    }).catch(err => console.error('[Legacy Discord] Error:', err.message));
  }
}
