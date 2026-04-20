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

Note: `flutter_app/` at the repo root is a stale copy — `app/` is the active Flutter project.

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

`sidebar.js` runs as an IIFE and exposes `window.db` (Supabase client), `window.currentSession`, `window.currentUser`, `window.currentProfile`, and `window.refreshSidebarCategories()`. It dispatches a `sidebar-ready` CustomEvent when complete — pages that need auth data should wait for this event.

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

The Edge Function also supports a **direct tool call mode** — send `{ tool_call: { name, input } }` in the request body to invoke a single tool without going through the Claude loop. Used by the Flutter app for `delete_category` and `deleteAccount`.

Ownership is double-checked in every tool call. `run_sql` is restricted to admin (service role key) and requires a `user_id` filter in the SQL.

### Flutter App (`app/`)

| File | Role |
|------|------|
| `app/lib/main.dart` | App entry — Supabase init, global `themeNotifier` (`ValueNotifier<ThemeSettings>`), `loadThemeFromSupabase()` |
| `app/lib/screens/chat_screen.dart` | Primary screen — AI chat, drawer with category list, voice input (STT), TTS, stop button |
| `app/lib/screens/category_screen.dart` | Item CRUD + CSV export for a single category |
| `app/lib/screens/settings_screen.dart` | Appearance (theme presets + color pickers) + Profile (password change, delete account) |
| `app/lib/screens/login_screen.dart` | Email/password auth + signup |
| `app/lib/services/api_service.dart` | HTTP calls to the Edge Function — always calls `refreshSession()` first |
| `app/lib/services/supabase_service.dart` | Direct Supabase SDK queries (categories, items, ui_settings) |
| `app/lib/models/theme_settings.dart` | `ThemeSettings` model + 6 built-in presets |

Theme changes from the AI flow through `themeNotifier` (set in `loadThemeFromSupabase()`) which rebuilds the `MaterialApp` via `ValueListenableBuilder`.

### Theme System

- **Web**: CSS custom properties on `document.documentElement`, sourced from `localStorage` key `inv_theme` (set inline in `<head>` to prevent FOUC). `sidebar.js` re-applies as fallback.
- **Flutter**: `theme_color` (hex seed) + `theme_mode` ("light"/"dark"/"system") drive `ColorScheme.fromSeed`; optional `bg_color`, `card_color`, `accent_color` override specific surface roles.
- `ui_settings` rows store values as jsonb. When read back as a string, values may be wrapped in extra JSON quotes — `SupabaseService._parseValue()` strips them.
- Settings page has 6 presets + custom color pickers.

## Critical Patterns

**Token freshness** — always call `refreshSession()` (not `getSession()`) before Edge Function calls. `getSession()` returns a cached, potentially stale JWT; with JWT enforcement ON on the Edge Function, stale tokens cause 401 errors.

**user_id on INSERT** — always stamp `user_id` explicitly even when RLS is active, to prevent silent nulls.

**Edge Function deployment** — done via Supabase Dashboard (not CLI). Requires `ANTHROPIC_API_KEY` secret and JWT enforcement set to ON.

**`backend/inventory-setup-v4.sql` is the single source of truth** for the DB. All older SQL files are retired.

**AI model** — `claude-haiku-4-5-20251001` in `smart-api-v4.ts`. Do NOT change to sonnet or haiku-4-6 (causes 404).

## Supabase Config Location

Supabase URL and anon key are hardcoded in `web/sidebar.js`, `web/ai-assistant-v4.js`, and `app/lib/main.dart` (also `app/lib/services/api_service.dart` for the Edge Function URL) — update all when changing projects.

## Shorthand / Abbreviations

- **mp** = Mousepad (the text editor app on this WSL/Ubuntu device — e.g. "open X in mp" means launch it with `mousepad`)

## Chrome DevTools MCP (WSL2)

Working — config and fix details are in memory (`project_chrome_devtools.md`).
