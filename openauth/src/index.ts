// openauth/src/index.ts
// ─── OpenAuth server — local demo ─────────────────────────────────────────────
//
// Uses CodeProvider (email OTP flow) — simplest provider for local demo.
// The "code" is just logged to stdout since there's no email server.
// Copy the code from the container logs and paste it in the UI.
//
// Demo users are looked up by email in the success() callback.
// Two pre-seeded users: admin@locci.dev, user@locci.dev

import { serve } from "@hono/node-server";
import { issuer } from "@openauthjs/openauth";
import { MemoryStorage } from "@openauthjs/openauth/storage/memory";
import { CodeProvider } from "@openauthjs/openauth/provider/code";
import { CodeUI } from "@openauthjs/openauth/ui/code";
import { subjects } from "./subjects.js";

const port = parseInt(process.env.PORT ?? "3001", 10);

// ── Demo users ────────────────────────────────────────────────────────────────
const DEMO_USERS: Record<string, { id: string; email: string; role: string }> =
  {
    "admin@locci.cloud": {
      id: "usr_admin_001",
      email: "admin@locci.cloud",
      role: "admin",
    },
    "contact@miketeddyomondi.dev": {
      id: "usr_user_001",
      email: "contact@miketeddyomondi.dev",
      role: "user",
    },
  };

// ── Pre-registered clients ────────────────────────────────────────────────────
const ALLOWED_CLIENTS = new Set([
  "locci-mcp-public",
  "locci-web",
  "krakend-gateway",
]);

const app = issuer({
  storage: MemoryStorage(),
  subjects,

  // Allow any registered client, any localhost redirect URI
  allow: async ({ clientID, redirectURI }) => {
    if (!ALLOWED_CLIENTS.has(clientID)) return false;
    // Allow any localhost/127.0.0.1 redirect for local dev
    const isLocal =
      redirectURI.startsWith("http://localhost") ||
      redirectURI.startsWith("http://127.0.0.1");
    return isLocal;
  },

  providers: {
    code: CodeProvider(
      CodeUI({
        sendCode: async (claims, code) => {
          // No email server in local demo — just log it
          console.log(`\n┌─────────────────────────────────────┐`);
          console.log(`│  LOGIN CODE for ${claims.email.padEnd(20)} │`);
          console.log(`│  Code: ${code.padEnd(29)} │`);
          console.log(`└─────────────────────────────────────┘\n`);
        },
      }),
    ),
  },

  async success(ctx, value) {
    if (value.provider === "code") {
      const email = value.claims.email as string;
      const user = DEMO_USERS[email];

      if (!user) {
        // Unknown email — create a guest user on the fly
        console.log(
          `[openauth] Unknown user ${email} — creating guest subject`,
        );
        return ctx.subject("user", {
          id: `usr_guest_${Date.now()}`,
          email,
          role: "user",
        });
      }

      console.log(`[openauth] Login success: ${email} (role: ${user.role})`);
      return ctx.subject("user", {
        id: user.id,
        email: user.email,
        role: user.role,
      });
    }

    throw new Error(`Unknown provider: ${value.provider}`);
  },
});

serve({ fetch: app.fetch, port }, () => {
  console.log(`
╔══════════════════════════════════════════════════════════════╗
║           Locci OpenAuth — Local Demo                        ║
╠══════════════════════════════════════════════════════════════╣
║  Port     : ${String(port).padEnd(47)}  ║
╠══════════════════════════════════════════════════════════════╣
║  How to login:                                               ║
║    1. Go to http://localhost:3001/authorize?...              ║
║    2. Enter admin@locci.dev or user@locci.dev                ║
║    3. Check THIS terminal for the login code                 ║
║    4. Paste code in the UI                                   ║
╠══════════════════════════════════════════════════════════════╣
║  Demo users:                                                 ║
║    admin@locci.dev  (role: admin)                            ║
║    user@locci.dev   (role: user)                             ║
╠══════════════════════════════════════════════════════════════╣
║  Endpoints:                                                  ║
║    GET  /.well-known/oauth-authorization-server              ║
║    GET  /.well-known/jwks.json                               ║
║    GET  /authorize                                           ║
║    POST /token                                               ║
╚══════════════════════════════════════════════════════════════╝
`);
});
