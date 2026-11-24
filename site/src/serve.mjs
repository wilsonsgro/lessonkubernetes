// Minimal static server for dist/ (local preview without nginx); refuses paths outside dist.
import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { join, normalize, extname, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const DIST = join(dirname(fileURLToPath(import.meta.url)), '..', 'dist');
const TIPI = { '.html': 'text/html; charset=utf-8', '.css': 'text/css', '.js': 'text/javascript', '.mjs': 'text/javascript', '.json': 'application/json', '.svg': 'image/svg+xml', '.md': 'text/plain; charset=utf-8', '.sh': 'text/plain; charset=utf-8', '.yaml': 'text/plain; charset=utf-8', '.yml': 'text/plain; charset=utf-8', '.tf': 'text/plain; charset=utf-8', '.hcl': 'text/plain; charset=utf-8', '.txt': 'text/plain; charset=utf-8' };
const PORTA = Number(process.env.PORT || 8080);
const HOST = process.env.HOST || '127.0.0.1';

createServer(async (req, res) => {
  let p = normalize(decodeURIComponent(new URL(req.url, 'http://x').pathname)).replace(/^(\.\.[/\\])+/, '');
  let f = join(DIST, p);
  if (!f.startsWith(DIST)) { res.writeHead(403).end(); return; }
  try { if ((await stat(f)).isDirectory()) f = join(f, 'index.html'); const b = await readFile(f); res.writeHead(200, { 'content-type': TIPI[extname(f)] || 'application/octet-stream' }).end(b); }
  catch { res.writeHead(404, { 'content-type': 'text/plain' }).end('404'); }
}).listen(PORTA, HOST, () => console.log(`http://${HOST}:${PORTA}/`));
