# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AI-powered inventory management system (v4.0) with custom user-defined categories, multi-user data isolation, and a Claude AI assistant that can perform all CRUD operations via natural language.

## Directory Structure

```
inventory/
├── website/             ← Static HTML/JS frontend (was `web/`)
├── supabase/functions/  ← Edge Function source — `smart-api/index.ts` (deploy path)
├── backend/             ← SQL schema only (`inventory-setup-v4.sql`)
├── stockai/             ← Mobile app (Flutter/Dart, was `app/`)
├── docs/                ← PROJECT_RECAP.txt, notes_sort.txt, user files/ (screenshots)
├── scripts/             ← distribute.bat (Firebase App Distribution)
├── legacy/              ← Predecessor static HTML pages (was `old-version/`)
├── netlify-version/     ← Parallel TanStack Start build from Netlify Agent Runner
├── netlify.toml         ← Netlify config (publish = "website")
└── CLAUDE.md
```

## Running the Project

**Web frontend** — no build step required:
```bash
cd website
python -m http.server 8000   # or: npx http-server
```
Access at `http://localhost:8000`.

**Flutter mobile app**:
```bash
cd stockai
flutter pub get
flutter run
flutter test
flutter analyze   # lint Dart code
```

## Architecture

### Frontend (`website/`)

Pages are markup-only; styling lives in per-page CSS (`index.css`, `inventory.css`, `settings.css`, `about.css`, `landing.css`, plus shared `global.css`) and behavior in per-page JS — inline `<style>`/`<script>` blocks were extracted.

| File | Role |
|------|------|
| `website/landing.html` + `landing.js` | Login/signup/forgot-password/recovery (Supabase Auth) |
| `website/index.html` + `index.js` | Dashboard — category cards |
| `website/inventory.html` + `inventory-app.js` | Item CRUD — React/JSX via Babel CDN (`<script type="text/babel" src=...>`) |
| `website/settings.html` + `settings.js` | Profile & theme customization |
| `website/about.html` | Marketing/info page (guest-accessible) |
| `website/config.js` | **Single source** of `window.SUPABASE_URL` / `window.SUPABASE_ANON_KEY` |
| `website/auth.js` | Auth logic split out of sidebar.js — session guard, redirects to landing.html if logged out; exposes `window.authReady` promise + `auth-ready` event |
| `website/sidebar.js` | **Shared nav** — Supabase client init, category nav, theme loader |
| `website/theme-init.js` | Shared FOUC theme bootstrap — `window.THEME_CSS_MAP` + `window.applyThemeVars()` (was duplicated inline across pages) |
| `website/ai-assistant-v4.js` | Floating chat widget — calls `refreshSession()` for a fresh JWT before every API call |

`sidebar.js` runs as an IIFE and exposes `window.db` (Supabase client), `window.currentSession`, `window.currentUser`, `window.currentProfile`, and `window.refreshSidebarCategories()`. It dispatches a `sidebar-ready` CustomEvent when complete — pages that need auth data should wait for that (or `auth.js`'s `auth-ready`).

### Backend (`supabase/functions/`, `backend/`)

| File | Role |
|------|------|
| `supabase/functions/smart-api/index.ts` | **The Edge Function** (Deno) — validates JWT, runs Claude tool-use loop (16 tools), enforces ownership. This is the canonical source AND the `supabase functions deploy` path (deployed as **v49**). |
| `backend/inventory-setup-v4.sql` | **Authoritative DB schema** — tables, RLS policies, triggers, helper functions, seed data |

`smart-api` is the **only** deployed Edge Function. Legacy functions `ai-chat`, `table-structure`, and `gemini-extension` were deleted (superseded by smart-api; `ai-chat` ran service-role arbitrary SQL, `table-structure` was an open JWT-off endpoint).

### Database (Supabase / PostgreSQL)

- `profiles` — linked to `auth.users` via trigger on signup
- `table_definitions` — user-created categories
- `field_definitions` — schema for each category
- `ui_settings` — per-user theme/layout preferences (key/value jsonb)
- Dynamic item tables (e.g. `toners`, `monitors`) — one table per category, created at runtime

Every table has `user_id uuid NOT NULL`. RLS policies scope all data to `auth.uid() = user_id`.

### AI Integration

`supabase/functions/smart-api/index.ts` runs a tool-use loop (up to 8 iterations) with Claude `claude-haiku-4-5-20251001`. **16 tools total**: 14 exposed to Claude — `list_categories`, `get_items`, `get_fields`, `create_category`, `rename_category`, `delete_category`, `add_field`, `remove_field`, `rename_field`, `upsert_item`, `delete_item`, `get_ui_settings`, `set_ui_setting`, `set_layout` — plus 2 implemented but NOT in the tool array Claude sees: `run_sql` (intentionally hidden) and `send_feedback` (reachable only via direct tool_call).

The Edge Function also supports a **direct tool call mode** — send `{ tool_call: { name, input } }` in the request body to invoke a single tool without going through the Claude loop. Used by the Flutter app for `create_category`, `add_field`, `remove_field`, `rename_field`, and `delete_category`. (Account deletion is a separate Postgres RPC `delete_user_account`, not a tool_call.)

Ownership is double-checked in every tool call. `run_sql` is restricted to admin (service role key) and requires a `user_id` filter in the SQL.

### Flutter App (`stockai/`)

| File | Role |
|------|------|
| `stockai/lib/main.dart` | App entry — Supabase init, global `themeNotifier` (`ValueNotifier<ThemeSettings>`), `loadThemeFromSupabase()` |
| `stockai/lib/screens/chat_screen.dart` | Primary screen — AI chat, drawer with category list, voice input (STT), TTS, stop button |
| `stockai/lib/screens/category_screen.dart` | Item CRUD + CSV export for a single category |
| `stockai/lib/screens/settings_screen.dart` | Appearance (theme presets + color pickers) + Profile (password change, delete account) |
| `stockai/lib/screens/login_screen.dart` | Email/password auth + signup |
| `stockai/lib/services/api_service.dart` | HTTP calls to the Edge Function — always calls `refreshSession()` first |
| `stockai/lib/services/supabase_service.dart` | Direct Supabase SDK queries (categories, items, ui_settings) |
| `stockai/lib/models/theme_settings.dart` | `ThemeSettings` model + 6 built-in presets |

The three large screens are split via Dart `part`/`part of` (all `_private` classes stay in scope, no reference changes): `settings_screen.dart` → `screens/settings/{theme_tab, profile_tab, data_tab}.dart`; `category_screen.dart` → `screens/category/{manage_category_sheet, item_form}.dart`; `chat_screen.dart` → `screens/chat/category_sheets.dart`.

Theme changes from the AI flow through `themeNotifier` (set in `loadThemeFromSupabase()`) which rebuilds the `MaterialApp` via `ValueListenableBuilder`.

### Theme System

- **Web**: CSS custom properties on `document.documentElement`, sourced from `localStorage` key `inv_theme`. Shared `theme-init.js` (loaded early) applies them to prevent FOUC via `window.applyThemeVars()` / `window.THEME_CSS_MAP`; `sidebar.js` re-applies as fallback.
- **Flutter**: `theme_color` (hex seed) + `theme_mode` ("light"/"dark"/"system") drive `ColorScheme.fromSeed`; optional `bg_color`, `card_color`, `accent_color` override specific surface roles.
- `ui_settings` rows store values as jsonb. When read back as a string, values may be wrapped in extra JSON quotes — `SupabaseService._parseValue()` strips them.
- Settings page has 6 presets + custom color pickers.

## Critical Patterns

**Token freshness** — always call `refreshSession()` (not `getSession()`) before Edge Function calls. `getSession()` returns a cached, potentially stale JWT; with JWT enforcement ON on the Edge Function, stale tokens cause 401 errors.

**user_id on INSERT** — always stamp `user_id` explicitly even when RLS is active, to prevent silent nulls.

**Edge Function deployment** — `supabase functions deploy smart-api` (CLI) works and keeps JWT enforcement ON by default; the Supabase Dashboard is also valid. Deploys from `supabase/functions/smart-api/index.ts`. Requires secrets `ANTHROPIC_API_KEY` and `SUPABASE_SERVICE_ROLE_KEY` (the anon key is auto-injected). Keep JWT enforcement ON — do not pass `--no-verify-jwt`.

**`backend/inventory-setup-v4.sql` is the single source of truth** for the DB. All older SQL files are retired.

**AI model** — `claude-haiku-4-5-20251001` in `supabase/functions/smart-api/index.ts`. Do NOT change to sonnet or haiku-4-6 (causes 404).

## Supabase Config Location

- **Web**: Supabase URL + anon key live ONLY in `website/config.js` (`window.SUPABASE_URL` / `window.SUPABASE_ANON_KEY`); every other web file reads from those globals.
- **Flutter**: hardcoded in `stockai/lib/main.dart` (also `stockai/lib/services/api_service.dart` for the Edge Function URL).

Update these when changing projects. (Note: an ElevenLabs TTS API key is currently hardcoded in `stockai/lib/services/api_service.dart` — a real secret that should be rotated/proxied.)

## Shorthand / Abbreviations

- **mp** = Mousepad (the text editor app on this WSL/Ubuntu device — e.g. "open X in mp" means launch it with `mousepad`)

## Chrome DevTools MCP (WSL2)

Working — config and fix details are in memory (`project_chrome_devtools.md`).
