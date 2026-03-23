# StockAI — Inventory Manager v4.0

AI-powered inventory management system with a web app and Flutter mobile app. Users can create custom categories, manage items, and interact with an AI assistant that handles all operations through natural language.

## Features

- Custom user-defined categories with dynamic fields
- Full item CRUD via natural language AI chat
- Multi-user with data isolation (Row Level Security)
- Theme customization (colors, presets, dark/light mode)
- Web dashboard + Android mobile app

## Stack

| Layer | Tech |
|-------|------|
| Frontend | HTML, CSS, JavaScript (React via CDN) |
| Mobile | Flutter (Dart) — Android |
| Backend | Supabase Edge Function (Deno/TypeScript) |
| Database | Supabase (PostgreSQL) |
| AI | Claude claude-haiku-4-5-20251001 (Anthropic) |
| Hosting | Netlify (web), Firebase App Distribution (APK) |

## Project Structure

```
├── web/              # Static frontend
│   ├── landing.html  # Login / signup
│   ├── index.html    # Dashboard
│   ├── inventory.html# Item management
│   ├── settings.html # Profile & theme
│   ├── sidebar.js    # Shared auth, nav, Supabase client
│   └── ai-assistant-v4.js  # Floating AI chat widget
├── backend/
│   ├── smart-api-v4.ts       # Supabase Edge Function — AI tool-use loop
│   └── inventory-setup-v4.sql# Database schema (single source of truth)
├── app/              # Flutter mobile app
│   ├── lib/
│   │   ├── main.dart
│   │   ├── models/
│   │   ├── screens/
│   │   └── services/
│   └── android/
├── docs/             # Project notes and recap
├── scripts/
│   └── distribute.bat# Firebase App Distribution deploy
└── netlify.toml      # Netlify config
```

## Setup

### Web

No build step required. Supabase URL and anon key are configured in `web/sidebar.js` and `web/ai-assistant-v4.js`.

```bash
cd web
npx http-server
# or
python -m http.server 8000
```

Deploy to Netlify:
```bash
netlify deploy --prod
```

### Backend (Edge Function)

Deploy via the Supabase Dashboard. The function requires two secrets:
- `ANTHROPIC_API_KEY`
- JWT enforcement set to **ON**

### Mobile (Flutter)

```bash
cd app
flutter pub get
flutter run
```

Build and distribute APK:
```bash
scripts/distribute.bat
```

> **Note:** `google-services.json` is excluded from this repo. Add your own from the Firebase console to `app/android/app/`.

## Database

Run `backend/inventory-setup-v4.sql` in the Supabase SQL editor to set up all tables, RLS policies, triggers, and functions. This is the single source of truth for the schema.
