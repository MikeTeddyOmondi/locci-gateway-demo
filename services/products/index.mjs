// services/products/index.mjs
// ─── Products stub microservice ───────────────────────────────────────────────
// Demonstrates role-based access: POST /products requires role=admin
// Role is enforced here using the x-user-role header injected by KrakenD.

import http from "node:http";

const PORT = parseInt(process.env.PORT ?? "3003", 10);
const SERVICE = process.env.SERVICE_NAME ?? "products";

const PRODUCTS = [
  { id: "prod_001", name: "Locci Functions", price: 9.99, category: "compute" },
  { id: "prod_002", name: "Locci Storage", price: 4.99, category: "storage" },
  { id: "prod_003", name: "Locci Academy", price: 19.99, category: "education" },
];

const FAVOURITES = {
  usr_admin_001: ["prod_001", "prod_003"],
  usr_user_001: ["prod_002"],
};

function json(res, body, status = 200) {
  const payload = JSON.stringify(body, null, 2);
  res.writeHead(status, { "Content-Type": "application/json" });
  res.end(payload);
}

async function readBody(req) {
  return new Promise((resolve) => {
    const chunks = [];
    req.on("data", (c) => chunks.push(c));
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf-8")));
  });
}

function getCaller(req) {
  return {
    id: req.headers["x-user-id"] ?? "unknown",
    email: req.headers["x-user-email"] ?? "unknown",
    role: req.headers["x-user-role"] ?? "unknown",
  };
}

const server = http.createServer(async (req, res) => {
  const method = req.method ?? "GET";
  const pathname = (req.url ?? "/").split("?")[0];

  console.log(`[${SERVICE}] ${method} ${pathname} — caller: ${req.headers["x-user-id"] ?? "no-auth"}`);

  // Health
  if (method === "GET" && pathname === "/health") {
    return json(res, { status: "ok", service: SERVICE });
  }

  // GET /products — list all (any authenticated user)
  if (method === "GET" && pathname === "/products") {
    const caller = getCaller(req);
    return json(res, {
      service: SERVICE,
      caller,
      data: PRODUCTS,
      note: "JWT validated by KrakenD — role check for writes happens here",
    });
  }

  // GET /products/favourites — return caller's favourites
  if (method === "GET" && pathname === "/products/favourites") {
    const caller = getCaller(req);
    const ids = FAVOURITES[caller.id] ?? [];
    const favs = PRODUCTS.filter((p) => ids.includes(p.id));
    return json(res, { service: SERVICE, caller, data: favs });
  }

  // POST /products — admin only (role enforced here)
  if (method === "POST" && pathname === "/products") {
    const caller = getCaller(req);

    if (caller.role !== "admin") {
      return json(res, {
        error: "forbidden",
        error_description: "Only admins can create products",
        your_role: caller.role,
      }, 403);
    }

    const raw = await readBody(req);
    let body = {};
    try { body = JSON.parse(raw); } catch { /* ignore */ }

    const newProduct = {
      id: `prod_${Date.now()}`,
      name: body.name ?? "Unnamed",
      price: body.price ?? 0,
      category: body.category ?? "misc",
      created_by: caller.email,
    };

    PRODUCTS.push(newProduct);
    return json(res, { service: SERVICE, caller, data: newProduct }, 201);
  }

  json(res, { error: "not_found", path: pathname }, 404);
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`[${SERVICE}] Listening on http://0.0.0.0:${PORT}`);
});
