#!/usr/bin/env bash
# ─── Get a JWT from OpenAuth via PKCE + Code flow (CLI helper) ────────────────
# Opens the browser, starts a local callback server, exchanges the code for
# a token, and prints it ready to export.
#
# Usage:  ./scripts/get-token.sh

set -e

AUTH="http://localhost:3001"
CLIENT_ID="locci-web"
REDIRECT_URI="http://localhost:9797/callback"
PORT=9797

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${BLUE}ℹ️  $1${NC}"; }
ok()    { echo -e "${GREEN}✅ $1${NC}"; }
warn()  { echo -e "${YELLOW}⚠️  $1${NC}"; }

# Generate PKCE
CODE_VERIFIER=$(node -e "
const crypto = require('crypto');
const v = crypto.randomBytes(32).toString('base64url');
process.stdout.write(v);
")

CODE_CHALLENGE=$(node -e "
const crypto = require('crypto');
const v = '$CODE_VERIFIER';
const c = crypto.createHash('sha256').update(v).digest('base64url');
process.stdout.write(c);
")

STATE=$(node -e "process.stdout.write(require('crypto').randomBytes(16).toString('hex'))")

ENCODED_REDIRECT=$(node -e "process.stdout.write(encodeURIComponent('$REDIRECT_URI'))")

AUTH_URL="${AUTH}/authorize?response_type=code&client_id=${CLIENT_ID}&redirect_uri=${ENCODED_REDIRECT}&code_challenge=${CODE_CHALLENGE}&code_challenge_method=S256&state=${STATE}"

echo ""
info "Starting OAuth PKCE flow..."
echo ""
warn "After entering your email, check the OPENAUTH CONTAINER LOGS for your login code:"
echo "  docker compose logs -f openauth"
echo ""
info "Waiting for callback on port $PORT before opening browser..."

# Start callback server and exchange code for token.
#
# THE KEY FIX: the browser is opened inside server.listen()'s callback,
# which only fires once the TCP port is actually bound and ready to accept
# connections. The old version opened the browser in the shell BEFORE the
# Node process even started, so the browser hit localhost:9999 while nothing
# was listening yet — causing the 404. Now the sequence is guaranteed:
#   1. Node starts
#   2. Port 9999 binds successfully  ← listen() callback fires here
#   3. Browser opens                 ← browser launched here, port is ready
#   4. User logs in + gets code
#   5. OpenAuth redirects to localhost:9999/callback ← server catches it
#   6. Server exchanges code for token, resolves promise
#   7. Token printed to terminal
TOKEN=$(node --input-type=module << EOF
import http from 'node:http';
import { execSync } from 'node:child_process';

const token = await new Promise((resolve, reject) => {
  const server = http.createServer(async (req, res) => {
    const url = new URL(req.url, 'http://localhost:${PORT}');
    const code = url.searchParams.get('code');

    if (!code) {
      res.writeHead(400); res.end('Missing code');
      return;
    }

    res.writeHead(200, { 'Content-Type': 'text/html' });
    res.end(\`
      <html><body style="font-family:sans-serif;padding:2rem;text-align:center">
        <h2>✅ Authorization successful!</h2>
        <p>You can close this window and return to the terminal.</p>
      </body></html>
    \`);

    // Exchange code for tokens
    const resp = await fetch('${AUTH}/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'authorization_code',
        code,
        redirect_uri: '${REDIRECT_URI}',
        client_id: '${CLIENT_ID}',
        code_verifier: '${CODE_VERIFIER}',
      }),
    });

    const data = await resp.json();

    server.close(); // ← close after we have the token

    if (data.access_token) {
      resolve(data.access_token);
    } else {
      reject(new Error('Token exchange failed: ' + JSON.stringify(data)));
    }
  });

  // Open the browser only once the port is bound and ready.
  // listen() is async — its callback is the "port is open" signal.
  server.listen(${PORT}, () => {
    const cmd = process.platform === 'darwin' ? 'open' : 'xdg-open';
    try {
      execSync(\`\${cmd} "${AUTH_URL}"\`);
    } catch {
      // execSync throws if the open command fails (e.g. headless env)
      // Fall through — the URL was already printed above by the shell
      process.stderr.write('Could not open browser automatically.\\nOpen this URL manually:\\n${AUTH_URL}\\n');
    }
  });

  server.on('error', reject);
});

process.stdout.write(token);
process.exit(0);
EOF
)

echo ""
ok "Got token!"
echo ""
echo "────────────────────────────────────────"
echo "export TOKEN='$TOKEN'"
echo "────────────────────────────────────────"
echo ""
info "Now test the gateway:"
echo "  curl http://localhost:8080/users    -H \"Authorization: Bearer \$TOKEN\" | jq ."
echo "  curl http://localhost:8080/products -H \"Authorization: Bearer \$TOKEN\" | jq ."
echo "  curl http://localhost:8080/me       -H \"Authorization: Bearer \$TOKEN\" | jq ."
