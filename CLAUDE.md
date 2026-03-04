# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AI-powered inventory management system (v4.0) with custom user-defined categories, multi-user data isolation, and a Claude AI assistant that can perform all CRUD operations via natural language.

## Directory Structure

```
new/
├── web/              ← Static HTML/JS frontend
├── backend/          ← Supabase Edge Function + SQL schema
├── app/              ← Mobile app (Flutter/Dart)
├── docs/             ← PROJECT_RECAP.txt, notes_sort.txt
├── scripts/          ← distribute.bat (Firebase App Distribution)
├── netlify.toml      ← Netlify config (publish = "web")
└── CLAUDE.md
```

## Running the Project

**Web frontend** — no build step required:
```bash
cd web
python -m http.server 8000   # or: npx http-server
```
Access at `http://localhost:8000`.

**Flutter mobile app**:
```bash
cd app
flutter pub get
flutter run
flutter test
flutter analyze   # lint Dart code
```

## Architecture

### Frontend (`web/`)

| File | Role |
|------|------|
| `web/landing.html` | Login/signup (Supabase Auth) |
| `web/index.html` | Dashboard — category cards |
| `web/inventory.html` | Item CRUD — React via Babel CDN |
| `web/settings.html` | Profile & theme customization |
| `web/sidebar.js` | **Shared across all pages** — Supabase client init, auth guard, `onAuthStateChange`, theme loader, category nav |
| `web/ai-assistant-v4.js` | Floating chat widget — calls `refreshSession()` for a fresh JWT before every API call |

### Backend (`backend/`)

| File | Role |
|------|------|
| `backend/smart-api-v4.ts` | Supabase Edge Function (Deno) — validates JWT, runs Claude tool-use loop (13 tools), enforces ownership |
| `backend/inventory-setup-v4.sql` | **Authoritative DB schema** — tables, RLS policies, triggers, helper functions, seed data |

### Database (Supabase / PostgreSQL)

- `profiles` — linked to `auth.users` via trigger on signup
- `table_definitions` — user-created categories
- `field_definitions` — schema for each category
- `ui_settings` — per-user theme/layout preferences (key/value jsonb)
- Dynamic item tables (e.g. `toners`, `monitors`) — one table per category, created at runtime

Every table has `user_id uuid NOT NULL`. RLS policies scope all data to `auth.uid() = user_id`.

### AI Integration

`backend/smart-api-v4.ts` runs a tool-use loop (up to 8 iterations) with Claude `claude-haiku-4-5-20251001`. The 13 tools cover: `list_categories`, `get_items`, `get_fields`, `create_category`, `rename_category`, `delete_category`, `add_field`, `upsert_item`, `delete_item`, `run_sql`, `get_ui_settings`, `set_ui_setting`, `set_layout`.

Ownership is double-checked in every tool call. `run_sql` is restricted to admin (service role key).

### Theme System

- CSS custom properties on `document.documentElement`
- Applied by an inline `<script>` in `<head>` reading `localStorage` key `inv_theme` — prevents FOUC
- `web/sidebar.js` re-applies as fallback
- Settings page has 6 presets + custom color pickers

## Critical Patterns

**Token freshness** — always call `refreshSession()` (not `getSession()`) before Edge Function calls. `getSession()` returns a cached, potentially stale JWT; with JWT enforcement ON on the Edge Function, stale tokens cause 401 errors.

**user_id on INSERT** — always stamp `user_id` explicitly even when RLS is active, to prevent silent nulls.

**Edge Function deployment** — done via Supabase Dashboard (not CLI). Requires `ANTHROPIC_API_KEY` secret and JWT enforcement set to ON.

**`backend/inventory-setup-v4.sql` is the single source of truth** for the DB. All older SQL files are retired.

**AI model** — `claude-haiku-4-5-20251001` in `smart-api-v4.ts`. Do NOT change to sonnet or haiku-4-6 (causes 404).

## Supabase Config Location

Supabase URL and anon key are hardcoded in `web/sidebar.js` and `web/ai-assistant-v4.js` — update both when changing projects.
