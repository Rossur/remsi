import admin from 'firebase-admin';

// Initialize Firebase Admin SDK if service account is provided in environment variables
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

export async function sendFCMNotification(token, title, body) {
  if (!token) return;
  if (admin.apps.length === 0) {
    console.warn('[FCM] Firebase Admin not initialized, cannot send push notification.');
    return;
  }
  try {
    await admin.messaging().send({
      token,
      notification: {
        title,
        body
      },
      webpush: {
        headers: {
          Urgency: 'high'
        }
      }
    });
    console.log(`[FCM] Notification sent successfully to token: ${token.substring(0, 10)}...`);
  } catch (err) {
    console.error('[FCM] Error sending notification:', err.message);
  }
}

export async function sendDiscordAlert(webhookUrl, ticker, interval, rsiVal, confluenceScore, action) {
  if (!webhookUrl) return;
  
  const color = action === 'BUY' ? 0x00FF00 : 0xFF0000; // Green for Buy, Red for Sell
  const embed = {
    title: `🚨 REMSI Alert: ${ticker} (${interval})`,
    description: `Confluence signal detected for **${ticker}** on **${interval}** timeframe.`,
    color: color,
    fields: [
      { name: 'Action', value: `**${action === 'BUY' ? 'BUY (OVERSOLD)' : 'SELL (OVERBOUGHT)'}**`, inline: true },
      { name: 'RSI', value: `${rsiVal.toFixed(2)}`, inline: true },
      { name: 'Confluence Score', value: `${confluenceScore}/10`, inline: true }
    ],
    timestamp: new Date().toISOString(),
    footer: { text: 'REMSI Scanner Engine' }
  };

  try {
    const res = await fetch(webhookUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ embeds: [embed] })
    });
    if (!res.ok) {
      console.error(`[Discord] Webhook returned status ${res.status}`);
    } else {
      console.log(`[Discord] Alert sent to webhook: ${webhookUrl.substring(0, 30)}...`);
    }
  } catch (err) {
    console.error('[Discord] Error sending alert:', err.message);
  }
}

export async function sendSMSAlert(phoneNumber, message) {
  const accountSid = process.env.TWILIO_ACCOUNT_SID;
  const authToken = process.env.TWILIO_AUTH_TOKEN;
  const twilioPhone = process.env.TWILIO_PHONE_NUMBER;

  if (!accountSid || !authToken || !twilioPhone || !phoneNumber) {
    console.warn('[SMS] Missing Twilio credentials or destination phone number.');
    return;
  }

  const url = `https://api.twilio.com/2010-04-01/Accounts/${accountSid}/Messages.json`;
  const auth = Buffer.from(`${accountSid}:${authToken}`).toString('base64');

  const params = new URLSearchParams();
  params.append('To', phoneNumber);
  params.append('From', twilioPhone);
  params.append('Body', message);

  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Authorization': `Basic ${auth}`,
        'Content-Type': 'application/x-www-form-urlencoded'
      },
      body: params.toString()
    });
    const resData = await res.json();
    if (!res.ok) {
      console.error(`[SMS] Twilio returned error: ${resData.message}`);
    } else {
      console.log(`[SMS] SMS sent to ${phoneNumber}. SID: ${resData.sid}`);
    }
  } catch (err) {
    console.error('[SMS] Error sending SMS:', err.message);
  }
}

export async function dispatchAlert({ ticker, interval, rsiVal, confluenceScore, action, fcmToken, discordWebhook, phoneNumber }) {
  const message = `REMSI ALERT: ${ticker} [${interval}] is ${action === 'BUY' ? 'OVERSOLD' : 'OVERBOUGHT'}. RSI: ${rsiVal.toFixed(2)}, Confluence Score: ${confluenceScore}/10.`;
  
  console.log(`[Alert Dispatcher] Dispatching: ${message}`);
  
  const promises = [];
  
  if (fcmToken) {
    promises.push(sendFCMNotification(fcmToken, `REMSI Alert: ${ticker} (${interval})`, message));
  }
  
  if (discordWebhook) {
    promises.push(sendDiscordAlert(discordWebhook, ticker, interval, rsiVal, confluenceScore, action));
  }
  
  if (phoneNumber) {
    promises.push(sendSMSAlert(phoneNumber, message));
  }
  
  await Promise.all(promises);
}

// Backward compatibility helper
export function sendAlert(message) {
  console.log(`[LEGACY ALERT] ${message}`);
  // Fallback to default discord webhook or phone number if configured
  if (process.env.DEFAULT_DISCORD_WEBHOOK) {
    fetch(process.env.DEFAULT_DISCORD_WEBHOOK, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ content: message })
    }).catch(err => console.error('[Legacy Discord] Error:', err.message));
  }
}
