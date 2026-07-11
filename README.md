# Faithly Fair

Faithly Fair is a responsive bouquet-first storefront built with React, TypeScript, Vite, Tailwind CSS, and Supabase. It includes a polished floral shopping experience, guest checkout, COD and UPI payment flows, private payment-proof handling, customer order history, and a hidden admin studio.

## Highlights

- Bouquet-first Home and Shop experience with a secondary gift-hamper collection
- Separate Home, Shop, Cart, Checkout, Order Confirmation, and My Orders pages
- Responsive mobile navigation, motion, spacing, and product-card interactions
- Guest checkout with customer name, mobile, required email, and full Indian delivery address
- COD and exact-amount UPI QR payment using `8920925990@fam`
- Private payment-proof upload and manual payment verification
- Email one-time-code login to view orders linked to the checkout email
- Prefilled WhatsApp support links for `+91 89209 25880`
- Supabase RLS, storage policies, order snapshots, stock checks, and admin roles
- Hidden admin studio at `/admin1199`

## Quick start

```bash
npm install
npm run dev
```

The local server supports LAN testing. When it is running, use the Network URL Vite prints in the terminal on a mobile device connected to the same Wi-Fi.

For production validation:

```bash
npm run lint
npm run build
```

## Routes

| Route | Purpose |
| --- | --- |
| `/` | Brand homepage and bouquet highlights |
| `/shop` | Bouquet and gift-hamper collections |
| `/cart` | Full cart and order summary |
| `/checkout` | Guest delivery and payment checkout |
| `/orders` | Email-code login and customer order history |
| `/admin1199` | Private admin studio |

## Supabase setup

Copy `.env.example` to `.env.local`, then provide the public Supabase URL and anon key:

```env
VITE_SUPABASE_URL=https://YOUR_PROJECT.supabase.co
VITE_SUPABASE_ANON_KEY=YOUR_PUBLIC_ANON_KEY
```

Run the SQL files in `supabase/migrations/` in numerical order. For an existing project, use all later migrations after the base migration.

The database stores each order’s customer name, email, mobile number, address, ordered items, payment method, payment state, order state, total, and creation time. Product price and name are copied into order items so historic orders never change after catalog edits.

For customer order login, enable Supabase Email Auth and configure its email template to include `{{ .Token }}`. Full configuration steps, storage bucket details, Resend email setup, and admin creation are in [SETUP.md](./SETUP.md).

## Business defaults

- UPI ID: `8920925990@fam`
- Order email: `Fairyfaithly@gmail.com`
- WhatsApp: `+91 89209 25880`

UPI screenshots are supporting evidence only. Payment remains manually verified by an admin before an order is marked paid.

## Security notes

- Keep Supabase service-role and Resend keys server-side only.
- Never commit `.env.local` files.
- RLS protects orders, admin operations, and private payment proofs.
- The `/admin1199` path is intentionally not linked publicly; access also requires an allowlisted Supabase admin account.
