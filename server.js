// Load .env for local development (no-op on Vercel where env vars are set via dashboard)
import 'dotenv/config';

import http from 'http';
import fs from 'fs/promises';
import path from 'path';
import checkHandler from './api/check.js';
import historyHandler from './api/history.js';
import pushHandler from './api/push.js';
import processQueueHandler from './api/process-queue.js';
import subscribeHandler from './api/subscribe.js';

const PORT = process.env.PORT || 3000;

const MIME_TYPES = {
  '.html': 'text/html',
  '.css': 'text/css',
  '.js': 'application/javascript',
  '.json': 'application/json',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml'
};

// Parse JSON body from POST requests — the bare http module doesn't do this automatically
async function parseBody(req) {
  return new Promise((resolve) => {
    let raw = '';
    req.on('data', chunk => { raw += chunk.toString(); });
    req.on('end', () => {
      try {
        resolve(raw ? JSON.parse(raw) : {});
      } catch {
        resolve({});
      }
    });
  });
}

// Build a Vercel-compatible res adapter around Node's raw ServerResponse
// so all api/ handlers work identically on Vercel and locally
function buildVercelRes(res) {
  return {
    _statusCode: 200,
    status(code) {
      this._statusCode = code;
      return this;
    },
    json(data) {
      res.writeHead(this._statusCode, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(data));
      return this;
    }
  };
}

const server = http.createServer(async (req, res) => {
  const urlObj = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  const pathname = urlObj.pathname;

  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    res.writeHead(200);
    res.end();
    return;
  }

  // Attach parsed query params and body to req so handlers can access them
  req.query = Object.fromEntries(urlObj.searchParams.entries());

  // Parse body for POST/DELETE requests
  if (req.method === 'POST' || req.method === 'DELETE') {
    req.body = await parseBody(req);
  }

  // ── API Routes ──────────────────────────────────────────────────────────────

  if (pathname === '/api/check') {
    try {
      await checkHandler(req, buildVercelRes(res));
    } catch (err) {
      buildVercelRes(res).status(500).json({ success: false, error: err.message });
    }
    return;
  }

  if (pathname === '/api/history') {
    try {
      await historyHandler(req, res); // history handler handles its own res.writeHead
    } catch (err) {
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ success: false, error: err.message }));
    }
    return;
  }

  if (pathname === '/api/push') {
    try {
      await pushHandler(req, buildVercelRes(res));
    } catch (err) {
      buildVercelRes(res).status(500).json({ success: false, error: err.message });
    }
    return;
  }

  if (pathname === '/api/process-queue') {
    try {
      await processQueueHandler(req, buildVercelRes(res));
    } catch (err) {
      buildVercelRes(res).status(500).json({ success: false, error: err.message });
    }
    return;
  }

  if (pathname === '/api/subscribe') {
    try {
      await subscribeHandler(req, buildVercelRes(res));
    } catch (err) {
      buildVercelRes(res).status(500).json({ success: false, error: err.message });
    }
    return;
  }

  // ── Static File Server ──────────────────────────────────────────────────────

  try {
    let filePath = path.join(process.cwd(), pathname === '/' ? 'index.html' : pathname);
    const resolvedPath = path.resolve(filePath);
    if (!resolvedPath.startsWith(process.cwd())) {
      res.writeHead(403, { 'Content-Type': 'text/plain' });
      res.end('Forbidden');
      return;
    }

    const content = await fs.readFile(resolvedPath);
    const ext = path.extname(resolvedPath).toLowerCase();
    const contentType = MIME_TYPES[ext] || 'application/octet-stream';

    res.writeHead(200, { 'Content-Type': contentType });
    res.end(content);
  } catch (err) {
    if (err.code === 'ENOENT') {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('Not Found');
    } else {
      res.writeHead(500, { 'Content-Type': 'text/plain' });
      res.end(`Server Error: ${err.message}`);
    }
  }
});

server.listen(PORT, () => {
  console.log(`[REMSI] Local dev server running at http://localhost:${PORT}`);
  console.log(`[REMSI] Routes: /api/check | /api/history | /api/push | /api/process-queue | /api/subscribe`);
});
