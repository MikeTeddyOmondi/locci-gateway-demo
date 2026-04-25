// services/users/index.mjs
// ─── Users stub microservice ──────────────────────────────────────────────────
// Does NOT validate JWTs itself — that's KrakenD's job.
// Simply trusts the headers KrakenD injects after validation:
//   x-user-id    → JWT `sub` claim
//   x-user-email → JWT `properties.email` claim
//   x-user-role  → JWT `properties.role` claim

import http from "node:http";

const PORT = parseInt(process.env.PORT ?? "3002", 10);
const SERVICE = process.env.SERVICE_NAME ?? "users";

const USERS = [
  {
    id: "usr_admin_001",
    email: "admin@locci.cloud",
    role: "admin",
    name: "Admin User",
  },
  {
    id: "usr_user_001",
    email: "contact@miketeddyomondi.dev",
    role: "user",
    name: "Regular User",
  },
];

function json(res, body, status = 200) {
  const payload = JSON.stringify(body, null, 2);
  res.writeHead(status, { "Content-Type": "application/json" });
  res.end(payload);
}

function getCaller(req) {
  return {
    id: req.headers["x-user-id"] ?? "unknown",
    email: req.headers["x-user-email"] ?? "unknown",
    role: req.headers["x-user-role"] ?? "unknown",
  };
}

const server = http.createServer((req, res) => {
  const method = req.method ?? "GET";
  const pathname = (req.url ?? "/").split("?")[0];

  console.log(
    `[${SERVICE}] ${method} ${pathname} — caller: ${req.headers["x-user-id"] ?? "no-auth"}`,
  );

  // Health
  if (method === "GET" && pathname === "/health") {
    return json(res, { status: "ok", service: SERVICE });
  }

  // GET /users — list all
  if (method === "GET" && pathname === "/users") {
    const caller = getCaller(req);
    return json(res, {
      service: SERVICE,
      caller,
      data: USERS,
      note: "JWT validated by KrakenD — this service trusts injected headers",
    });
  }

  // GET /users/me — return the calling user
  if (method === "GET" && pathname === "/users/me") {
    const caller = getCaller(req);
    const user = USERS.find((u) => u.id === caller.id);
    return json(res, {
      service: SERVICE,
      caller,
      data: user ?? null,
    });
  }

  // GET /users/:id
  const match = pathname.match(/^\/users\/(.+)$/);
  if (method === "GET" && match) {
    const caller = getCaller(req);
    const user = USERS.find((u) => u.id === match[1]);
    if (!user) return json(res, { error: "not_found" }, 404);
    return json(res, { service: SERVICE, caller, data: user });
  }

  // Temporary route to inspect headers during development
  if (method === "GET" && pathname === "/debug-headers") {
    const caller = getCaller(req);
    return json(res, { headers: req.headers, caller });
  }

  json(res, { error: "not_found", path: pathname }, 404);
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`[${SERVICE}] Listening on http://0.0.0.0:${PORT}`);
});
