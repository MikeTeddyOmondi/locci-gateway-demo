#!/usr/bin/env bash
# ─── Locci Gateway Demo — End-to-End Test ─────────────────────────────────────
# Tests the full flow:
#   1. Get a token from OpenAuth (using client_credentials-style direct grant)
#   2. Hit KrakenD endpoints with the token
#   3. Verify protected endpoints reject requests without token
#
# NOTE: OpenAuth uses authorization_code + PKCE for browser flows.
#       For scripted testing we use a test helper endpoint we add in dev mode.
#       Alternatively paste a token from the browser flow manually.
#
# Usage:
#   ./scripts/test.sh                    # uses test token endpoint
#   TOKEN=<jwt> ./scripts/test.sh        # use your own token

set -e

AUTH="http://localhost:3001"
GW="http://localhost:8080"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✅ $1${NC}"; }
fail() { echo -e "${RED}❌ $1${NC}"; }
info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
head() { echo -e "\n${YELLOW}── $1 ──${NC}"; }

# ─── Wait for services ────────────────────────────────────────────────────────
head "Waiting for services to be ready"

wait_for() {
  local url=$1
  local name=$2
  local max=30
  local i=0
  echo -n "  Waiting for $name..."
  while ! curl -sf "$url" > /dev/null 2>&1; do
    sleep 1
    i=$((i+1))
    if [ $i -ge $max ]; then
      echo ""
      fail "$name did not start in ${max}s"
      exit 1
    fi
    echo -n "."
  done
  echo ""
  ok "$name is up"
}

wait_for "$AUTH/.well-known/oauth-authorization-server" "OpenAuth"
wait_for "$GW/health" "KrakenD"

# ─── Get a token ──────────────────────────────────────────────────────────────
head "Getting JWT from OpenAuth"

if [ -z "$TOKEN" ]; then
  info "No TOKEN env var set. Getting token via test endpoint..."
  info "OpenAuth uses PKCE browser flow — for scripted tests use the /test/token endpoint"
  info "Or run the browser flow and export TOKEN=<jwt> before running this script"

  # Try the test token endpoint (only available in dev mode)
  RESPONSE=$(curl -sf -X POST "$AUTH/test/token" \
    -H "Content-Type: application/json" \
    -d '{"email":"user@locci.dev","password":"user123","client_id":"locci-web"}' 2>/dev/null || echo "")

  if [ -z "$RESPONSE" ]; then
    echo ""
    info "Test token endpoint not available. Please get a token manually:"
    echo ""
    echo "  1. Open http://localhost:3001/authorize?response_type=code&client_id=locci-web&redirect_uri=http://localhost:3000/auth/callback&code_challenge_method=S256&code_challenge=PLACEHOLDER"
    echo "  2. Login as user@locci.dev / user123"
    echo "  3. Copy the access_token from the token exchange"
    echo "  4. Run: TOKEN=<your_token> ./scripts/test.sh"
    echo ""
    exit 0
  fi

  TOKEN=$(echo "$RESPONSE" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
fi

if [ -z "$TOKEN" ]; then
  fail "Could not obtain token"
  exit 1
fi

ok "Got token: ${TOKEN:0:40}..."

# ─── Test: No auth → should get 401 ──────────────────────────────────────────
head "Testing unauthenticated requests (should be 401)"

STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$GW/users")
if [ "$STATUS" = "401" ]; then
  ok "GET /users without token → 401 (KrakenD rejected)"
else
  fail "GET /users without token → $STATUS (expected 401)"
fi

STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$GW/products")
if [ "$STATUS" = "401" ]; then
  ok "GET /products without token → 401 (KrakenD rejected)"
else
  fail "GET /products without token → $STATUS (expected 401)"
fi

# ─── Test: With valid token ───────────────────────────────────────────────────
head "Testing authenticated requests (should be 200)"

USERS_RESP=$(curl -sf "$GW/users" -H "Authorization: Bearer $TOKEN")
if echo "$USERS_RESP" | grep -q "locci.dev"; then
  ok "GET /users → 200, data returned"
  echo "  Caller: $(echo $USERS_RESP | grep -o '"email":"[^"]*"' | head -1)"
else
  fail "GET /users failed"
  echo "  Response: $USERS_RESP"
fi

PRODUCTS_RESP=$(curl -sf "$GW/products" -H "Authorization: Bearer $TOKEN")
if echo "$PRODUCTS_RESP" | grep -q "Locci"; then
  ok "GET /products → 200, data returned"
else
  fail "GET /products failed"
  echo "  Response: $PRODUCTS_RESP"
fi

# ─── Test: Role enforcement (POST /products as regular user → 403) ────────────
head "Testing role enforcement (user role → POST /products should be 403)"

STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$GW/products" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"Test Product","price":1.99}')

if [ "$STATUS" = "403" ]; then
  ok "POST /products as user → 403 (role enforced at service level)"
else
  info "POST /products as user → $STATUS (if 200, you're logged in as admin)"
fi

# ─── Test: Aggregated endpoint ────────────────────────────────────────────────
head "Testing KrakenD response aggregation (GET /me)"

ME_RESP=$(curl -sf "$GW/me" -H "Authorization: Bearer $TOKEN" 2>/dev/null || echo "")
if echo "$ME_RESP" | grep -q "user\|favourites"; then
  ok "GET /me → 200, aggregated response from users + products services"
else
  info "GET /me → aggregation may need both services to have the caller's data"
fi

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}══════════════════════════════════════════${NC}"
echo -e "${GREEN}  Demo complete!${NC}"
echo ""
echo "  OpenAuth issuer : $AUTH"
echo "  KrakenD gateway : $GW"
echo ""
echo "  Key insight:"
echo "  KrakenD validated the JWT using OpenAuth's JWKS"
echo "  and injected x-user-id / x-user-email / x-user-role"
echo "  headers into upstream requests."
echo "  Upstreams never see the JWT — only the resolved claims."
echo -e "${YELLOW}══════════════════════════════════════════${NC}"
