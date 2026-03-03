# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AI-powered inventory management system (v4.0) with custom user-defined categories, multi-user data isolation, and a Claude AI assistant that can perform all CRUD operations via natural language.

## Running the Project

**Web frontend** — no build step required:
```bash
python -m http.server 8000   # or: npx http-server
```
Access at `http://localhost:8000`.

**Flutter mobile app**:
```bash
cd flutter_app
flutter pub get
flutter run
flutter test
flutter analyze   # lint Dart code
```

## Architecture

### Frontend (Static HTML/JS/CSS)

| File | Role |
|------|------|
| `landing.html` | Login/signup (Supabase Auth) |
| `index.html` | Dashboard — category cards |
| `inventory.html` | Item CRUD — React via Babel CDN |
| `settings.html` | Profile & theme customization |
| `sidebar.js` | **Shared across all pages** — Supabase client init, auth guard, `onAuthStateChange`, theme loader, category nav |
| `ai-assistant-v4.js` | Floating chat widget — calls `refreshSession()` for a fresh JWT before every API call |
| `login.html` | DEPRECATED — uses hardcoded credentials, do not use |

### Backend

| File | Role |
|------|------|
| `smart-api-v4.ts` | Supabase Edge Function (Deno) — validates JWT, runs Claude Sonnet 4 tool-use loop (13 tools), enforces ownership |
| `inventory-setup-v4.sql` | **Authoritative DB schema** — tables, RLS policies, triggers, helper functions, seed data |

### Database (Supabase / PostgreSQL)

- `profiles` — linked to `auth.users` via trigger on signup
- `table_definitions` — user-created categories
- `field_definitions` — schema for each category
- `ui_settings` — per-user theme/layout preferences (key/value jsonb)
- Dynamic item tables (e.g. `toners`, `monitors`) — one table per category, created at runtime

Every table has `user_id uuid NOT NULL`. RLS policies scope all data to `auth.uid() = user_id`.

### AI Integration

`smart-api-v4.ts` runs a tool-use loop (up to 8 iterations) with Claude `claude-sonnet-4-20250514`. The 13 tools cover: `list_categories`, `get_items`, `get_fields`, `create_category`, `rename_category`, `delete_category`, `add_field`, `upsert_item`, `delete_item`, `run_sql`, `get_ui_settings`, `set_ui_setting`, `set_layout`.

Ownership is double-checked in every tool call. `run_sql` is restricted to admin (service role key).

### Theme System

- CSS custom properties on `document.documentElement`
- Applied by an inline `<script>` in `<head>` reading `localStorage` key `inv_theme` — prevents FOUC
- `sidebar.js` re-applies as fallback
- Settings page has 6 presets + custom color pickers

## Critical Patterns

**Token freshness** — always call `refreshSession()` (not `getSession()`) before Edge Function calls. `getSession()` returns a cached, potentially stale JWT; with JWT enforcement ON on the Edge Function, stale tokens cause 401 errors.

**user_id on INSERT** — always stamp `user_id` explicitly even when RLS is active, to prevent silent nulls.

**Edge Function deployment** — done via Supabase Dashboard (not CLI). Requires `ANTHROPIC_API_KEY` secret and JWT enforcement set to ON.

**`inventory-setup-v4.sql` is the single source of truth** for the DB. All older SQL files (`migration-fix-isolation.sql`, etc.) are retired.

## Supabase Config Location

Supabase URL and anon key are hardcoded in `sidebar.js` and `ai-assistant-v4.js` — update both when changing projects.
