# StockAI — Session Log (overnight 2026-06-14 → 2026-06-15, CDT)

Team session (manager + site / app / ai / flutter agents). Started from "the
project needs a redo"; ended with web + backend + app all shipped.

## Shipped & live
- **Web** (autobase.netlify.app): full reorg + Midnight Violet redesign, theme-dynamic
  screens + atmospheric blooms (derive from `ui_settings.primary_color_start/end`),
  1.08 zoom, dashboard real field counts (#17), guest-accessible about page,
  green-flash fix, glow-only logo.
- **Backend** (smart-api **v50**, JWT ON): SSE streaming + plain-text output (#24);
  3 ghost edge functions deleted (ai-chat / table-structure / gemini-extension);
  account-deletion fixed — `cleanup_user_data()` corrected AND the missing
  `on_auth_user_deleted` BEFORE-DELETE trigger created (verified in prod).
- **App** (Firebase App Distribution, release 1.1.2(4), commit **bdc232e**, tester
  Yjturetsky@gmail.com): Midnight Violet restyle, drawer "+ New Category",
  live AI streaming (smooth — jank fixed #31), offline-resilient auth (#30:
  no more logout on network blip + friendly offline message on chat & login),
  theme-dynamic look (#26), working TTS (Eric voice @1.1x + curated picker),
  AppBar theming fix (#15).
  Latest install: appdistribution.firebase.google.com/testerapps/1:494810929579:android:798b5dc63ed5efba231aee/releases/6e8e0aviqb630

## Security incident (resolved)
- ElevenLabs API key was hardcoded in `api_service.dart` → leaked on public GitHub
  (GitGuardian). Removed from source (reads `String.fromEnvironment('ELEVENLABS_API_KEY')`),
  **revoked + deleted** the leaked key in the ElevenLabs dashboard, issued a new key.
  Now lives ONLY in gitignored `stockai/secrets.json` (build-time
  `--dart-define-from-file=secrets.json`). Added a **pre-commit secret scanner**
  (`scripts/git-hooks/pre-commit`, installed at `.git/hooks/pre-commit`).
- Supabase account password was reset (admin API) — **the user holds the new value**
  (NOT recorded here on purpose).

## Deploy mechanics (IMPORTANT — push does NOT auto-deploy)
- **Web**: `netlify deploy --prod --dir=website` (site a8646de0-…, project autobase).
  `website/config.js` is build-generated / gitignored.
- **Backend**: `supabase functions deploy smart-api` (project masngvxdbxqrrreszjxv, JWT ON).
- **App**: `flutter build apk --dart-define-from-file=secrets.json` (release) → Firebase
  App Distribution (`scripts/distribute.bat` or `firebase appdistribution:distribute`,
  project stockai-75833731-f9741).

## Carryovers (next session)
- **#37 (WIP, UNCOMMITTED)**: Settings voice change not picked up until restart.
  flutter's in-progress fix is in `stockai/lib/screens/chat_screen.dart` (refactor to
  `_loadTtsSettings()` re-read) — looked mid-edit (possible recursive call); FINISH +
  `flutter analyze` + test before committing.
- **#35**: byte-identical per-preset theme parity — adopt web's 7 preset surface sets in
  the app (site has the values). Kept 2-stop gradient (locked).
- Web custom "link end to start" mode for app↔web custom-color parity (site, optional).
- In-Settings voice picker preview/audition (flutter, optional).
- TTS edge-function proxy: `supabase/functions/tts/index.ts` drafted (cbe8d36) — to
  finish: `supabase secrets set ELEVENLABS_API_KEY`, `supabase functions deploy tts`,
  point app `synthesizeSpeech()` at `/tts` and drop the build-time key.
- Guest pages (landing.css/about.css) blooms still hardcoded violet (pre-auth; optional).
- #17/#26 default-voice etc. all verified except TTS *audio* by ear (user mic check).

## State at wrap
- Board: ~33/37 done; remainder = the carryovers above.
- Repo: master pushed; ONE uncommitted WIP file (chat_screen.dart, #37) left on disk.
- Everything else committed/pushed and deployed/distributed. Wrapped ~1 AM CDT.
