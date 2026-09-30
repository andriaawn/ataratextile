# Atandra Textile Commerce

Commerce foundation for Atandra Textile Supply, preserving the original landing page while adding a database-backed catalog, variants, inventory, cart, checkout, orders, samples, and an admin overview.

**Live:** https://txt.invesbot.my.id

## Project docs

| File | Isi |
|---|---|
| [`AGENTS.md`](AGENTS.md) | Aturan kerja untuk agent AI — **baca ini dulu** |
| [`HANDOFF.md`](HANDOFF.md) | Kondisi terkini, infrastruktur, pitfalls |
| [`plans/ROADMAP.md`](plans/ROADMAP.md) | Apa yang sudah selesai & apa yang tersisa |
| [`BACKLOG.md`](BACKLOG.md) | Ide yang ditunda + alasan + trigger |
| [`docs/architecture.md`](docs/architecture.md) | Arsitektur sistem, model data, alur order, keamanan |
| [`docs/api.md`](docs/api.md) | Referensi 34 endpoint API |
| [`docs/cms-architecture.md`](docs/cms-architecture.md) | Model CMS: 7 modul, layar per modul |
| [`docs/design-system.md`](docs/design-system.md) | Kontrak desain admin (warna, tipografi, komponen) |

**Alur kerja:** plan → approve → implement → test → log → commit. Plan di [`plans/`](plans/), catatan kerja di `logs/` (lokal saja, tidak di-commit).

## Local development

Install dependencies:

```bash
npm install
```

Run the API/database:

```bash
npm run api
```

Optional admin seed on first API start:

Copy `.env.example` to `.env`, then fill in real values. The API loads `.env` automatically.

```bash
# .env  (mode 600 — never commit)
PORT=8787
NODE_ENV=development
ALLOWED_ORIGINS=http://localhost:5173
ADMIN_EMAIL=admin@example.com
ADMIN_PASSWORD=<random, min 12 chars — openssl rand -base64 24>
ADMIN_INVITE_KEY=<random, min 16 chars>
DEV_PAYMENT_KEY=<random, min 12 chars>

npm run api
```

> ⚠️ **In production, a weak or common `ADMIN_PASSWORD` makes the server refuse to start
> (fail-fast).** Never use the example values above for a real deployment.

Run the Vite storefront in a second terminal:

```bash
npm run dev
```

Open `http://localhost:5173/` for the landing page. The storefront is available at `/shop.html`, product details at `/product.html?slug=...`, checkout at `/checkout.html`, and the operational overview at `/admin.html`.

The API runs at `http://localhost:8787` and uses a local SQLite database at `data/atandra.sqlite`. The database is generated and ignored by Git.

## API surface

- `GET /api/products` catalog search
- `GET /api/products/:slug` product, variants, stock, and pricing tiers
- `POST /api/orders` validate cart, reserve inventory, and create pending payment
- `POST /api/orders/:id/mock-payment` development payment confirmation
- `GET /api/orders/:id` order detail
- `POST /api/samples` sample request
- `GET /api/admin/dashboard` operational metrics
- `GET /api/admin/orders` recent orders
- `GET /api/admin/products` product management catalog
- `POST/PATCH/DELETE /api/admin/products` create, update, and archive products
- `GET/POST/PATCH /api/admin/categories` category management
- `GET/POST /api/admin/colors` color management
- `GET/POST /api/admin/products/:id/variants` variant management
- `PATCH /api/admin/variants/:id` update variant pricing
- `PATCH /api/admin/inventory/:variantId` adjust stock and low-stock threshold
- `PUT /api/admin/products/:id/pricing` replace quantity pricing tiers
- `PATCH /api/admin/orders/:id` update fulfillment status and tracking number
- `GET/PATCH /api/account/profile` customer profile
- `GET/POST/PATCH/DELETE /api/account/addresses` customer address book
- `GET /api/account/orders` private customer order history
- `GET /api/account/orders/:id` private order detail and tracking
- `POST /api/account/orders/:id/reorder` available reorder items

## Phase 1 security

- Customer registration, login, logout, and session lookup are available at `/api/auth/*`.
- Admin registration is available at `/api/auth/admin-register`, but requires `ADMIN_INVITE_KEY` from the API environment.
- Sessions use HttpOnly cookies and expire after seven days.
- Admin endpoints require a logged-in user with the `admin` role.
- CORS accepts only `ALLOWED_ORIGINS` (default: `http://localhost:5173`).
- A small per-IP request limit protects the API from accidental bursts.
- The development payment shortcut requires `x-dev-payment-key` and is disabled when `NODE_ENV=production`.
- The API server serves only built files and `public/`; it does not expose the repository root or `server/` source.

Set multiple allowed frontend origins with a comma-separated value:

```powershell
$env:ALLOWED_ORIGINS="http://localhost:5173,https://your-domain.example"
```

Payment and shipping are provider abstractions. The current local provider is manual/mock so no payment is falsely marked paid from a browser response. Midtrans or Xendit should be connected through verified server-side webhook code and environment secrets before production launch. Admin authentication, customer authentication, coupon CRUD, review moderation, and production notification providers remain the next implementation phase.

## Phase 2 admin

Open `http://localhost:5173/admin-products.html` after logging in as an admin. The workspace supports product creation, soft archive, category and color creation, variant creation, price updates, inventory adjustment, and quantity pricing tiers. Product deletion never removes historical records; it changes the product status to `archived`.

## Phase 3 customer account

- `http://localhost:5173/account.html` - customer login, registration, profile, and addresses.
- `http://localhost:5173/account-orders.html` - authenticated order history.
- `http://localhost:5173/account-order.html?id=AT-...` - authenticated order detail, shipment status, and reorder action.

Customer order queries are scoped by the authenticated customer ID, so one customer cannot read another customer's orders.
