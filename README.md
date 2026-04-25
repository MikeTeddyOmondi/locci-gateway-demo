# locci-gateway-demo

Local proof-of-concept: **OpenAuth** as IDP + **KrakenD** as API Gateway protecting upstream microservices.

## Architecture

```
Browser / curl
     │
     │  1. Login (PKCE)
     ▼
OpenAuth (localhost:3001)
     │  issues ES256 JWT
     │
     │  2. Bearer token on every request
     ▼
KrakenD (localhost:8080)          ← validates JWT via OpenAuth JWKS
     │                               injects x-user-id / x-user-email / x-user-role
     ├──► users service (localhost:3002)
     └──► products service (localhost:3003)
              │
              └── trusts injected headers, never sees the JWT
```

**Key principle:** Upstreams never validate JWTs themselves. KrakenD is the single validation point. Resolved claims arrive as HTTP headers — simple, fast, no JWT library needed in each service.

## Quick Start

```bash
# Start the stack
docker compose up --build

# In another terminal — get a token (opens browser)
chmod +x scripts/get-token.sh
./scripts/get-token.sh user     # login as user@locci.dev
./scripts/get-token.sh admin    # login as admin@locci.dev

# Export the token
export TOKEN='<paste token here>'

# Hit the gateway
curl http://localhost:8080/users    -H "Authorization: Bearer $TOKEN" | jq .
curl http://localhost:8080/products -H "Authorization: Bearer $TOKEN" | jq .
curl http://localhost:8080/me       -H "Authorization: Bearer $TOKEN" | jq .

# Verify unauthenticated requests are rejected by KrakenD
curl http://localhost:8080/users    # → 401
curl http://localhost:8080/products # → 401

# Verify role enforcement (as regular user)
curl -X POST http://localhost:8080/products \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"Test","price":1.99}' | jq .
# → 403 Forbidden (role: user, need: admin)
```

## Services

| Service | Port | Description |
|---------|------|-------------|
| OpenAuth | 3001 | Auth server — issues ES256 JWTs |
| KrakenD | 8080 | API Gateway — validates JWTs, proxies to upstreams |
| users | 3002 | Stub microservice — user CRUD |
| products | 3003 | Stub microservice — product CRUD (admin write) |

## Demo Users

| Email | Password | Role |
|-------|----------|------|
| admin@locci.dev | admin123 | admin |
| user@locci.dev | user123 | user |

## How KrakenD validates JWTs

In `krakend/krakend.json`, every protected endpoint has:

```json
"extra_config": {
  "auth/validator": {
    "alg": "ES256",
    "jwk_url": "http://openauth:3001/.well-known/jwks.json",
    "issuer": "http://localhost:3001",
    "cache": true,
    "propagate_claims": [
      ["sub",              "x-user-id"],
      ["properties/email", "x-user-email"],
      ["properties/role",  "x-user-role"]
    ]
  }
}
```

- `jwk_url` — KrakenD fetches and caches OpenAuth's public keys
- `issuer` — KrakenD rejects tokens from any other issuer
- `propagate_claims` — JWT claims are mapped to request headers for upstreams
- `cache: true` — JWKS cached for 900s, no round-trip per request

## Applying This to Production (thanos)

1. Replace `http://localhost:3001` issuer with `https://auth.locci.cloud`
2. Replace `http://openauth:3001` jwk_url with `https://auth.locci.cloud/.well-known/jwks.json`
3. Remove `disable_jwk_security: true` (only needed for HTTP in local dev)
4. Add your real Locci microservices as backends in `krakend.json`
5. Add KrakenD to your existing `docker-compose.yml` on thanos alongside your Cloudflare Tunnel

## Response Aggregation Demo

`GET /me` demonstrates KrakenD's killer feature — merging responses from multiple upstreams into one:

```json
{
  "user": {
    "service": "users",
    "data": { "id": "usr_user_001", "email": "user@locci.dev" }
  },
  "favourites": {
    "service": "products",
    "data": [{ "id": "prod_002", "name": "Locci Storage" }]
  }
}
```

One request from the client, two upstream calls, one merged response. No BFF needed.

# Troubleshooting

Kill dangling server port

```bash
lsof -ti :9999 | xargs kill -9
```
