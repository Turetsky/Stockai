/**
 * tts  —  ElevenLabs Text-to-Speech proxy  (Edge Function)
 *
 * ┌─────────────────────────────────────────────────────────┐
 * │  JWT ENFORCEMENT: ON                                     │
 * └─────────────────────────────────────────────────────────┘
 *
 * Why this exists:
 *   The ElevenLabs API key must NEVER ship inside the mobile app. The old
 *   build-time `--dart-define=ELEVENLABS_API_KEY` keeps the key out of source
 *   control, but it is still baked into the distributed APK and extractable.
 *   This proxy moves the key fully server-side: the app sends only its user
 *   JWT, this function validates it, then calls ElevenLabs with the secret and
 *   streams the audio back. The key lives ONLY as a Supabase secret.
 *
 * Security model:
 *   - JWT enforcement ON (do NOT deploy with --no-verify-jwt).
 *   - We additionally validate the token with auth.getUser() (anon key) so an
 *     expired/invalid JWT is rejected with 401 before we spend any TTS quota.
 *   - The ElevenLabs key is read from Deno.env (Supabase secret), never echoed.
 *
 * Request body (POST, application/json):
 *   {
 *     "text":             string  (required),
 *     "voice_id":         string  (optional, default Sarah),
 *     "model_id":         string  (optional, default eleven_flash_v2_5),
 *     "stability":        number  (optional, default 0.5),
 *     "similarity_boost": number  (optional, default 0.75)
 *   }
 *
 * Response:
 *   200  audio/mpeg  (streamed MP3 bytes, passed straight through)
 *   400  { error }   missing/empty text
 *   401  { error }   missing/invalid JWT
 *   402  { error }   ElevenLabs paid-plan required (free tier can't use voice)
 *   5xx  { error }   misconfig / upstream failure
 *
 * HOW TO DEPLOY (do NOT deploy without team-lead sign-off):
 *   1. Set the secret (one time):
 *        supabase secrets set ELEVENLABS_API_KEY=<key>
 *   2. Deploy (JWT stays ON — no --no-verify-jwt):
 *        supabase functions deploy tts
 *
 * App migration (separate change, NOT in this commit):
 *   stockai/lib/services/api_service.dart `synthesizeSpeech()` should POST to
 *   `<edgeFunctionUrl base>/tts` with a fresh JWT (refreshSession) instead of
 *   calling api.elevenlabs.io directly, and drop the `_elevenLabsApiKey`
 *   --dart-define entirely.
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const DEFAULT_VOICE_ID = 'EXAVITQu4vr4xnSDxMaL'; // Sarah — premade
const DEFAULT_MODEL_ID = 'eleven_flash_v2_5';

const json = (payload: unknown, status: number) =>
  new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

Deno.serve(async (req) => {
  // CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed. Use POST.' }, 405);
  }

  try {
    /* ── Token extraction ─────────────────────────────────── */
    const authHeader = req.headers.get('Authorization') ?? '';
    const token = authHeader.startsWith('Bearer ')
      ? authHeader.slice(7).trim()
      : authHeader.trim();

    if (!token) {
      return json({ error: 'Missing Authorization header. Please log in again.' }, 401);
    }

    /* ── Token validation (anon key) ──────────────────────── */
    const userDb = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      {
        global: { headers: { Authorization: `Bearer ${token}` } },
        auth: { persistSession: false },
      },
    );

    const { data: { user }, error: authErr } = await userDb.auth.getUser(token);
    if (authErr || !user) {
      const detail = authErr?.message ?? 'Token invalid or expired.';
      return json(
        { error: `Unauthorized: ${detail}. Please refresh your session and try again.` },
        401,
      );
    }

    /* ── Input ────────────────────────────────────────────── */
    const body = await req.json().catch(() => ({}));
    const text = (body.text ?? '').toString().trim();
    if (!text) {
      return json({ error: 'Missing "text" to synthesize.' }, 400);
    }

    const voiceId = (body.voice_id ?? DEFAULT_VOICE_ID).toString();
    const modelId = (body.model_id ?? DEFAULT_MODEL_ID).toString();
    const stability = typeof body.stability === 'number' ? body.stability : 0.5;
    const similarityBoost =
      typeof body.similarity_boost === 'number' ? body.similarity_boost : 0.75;

    /* ── Secret ───────────────────────────────────────────── */
    const apiKey = Deno.env.get('ELEVENLABS_API_KEY');
    if (!apiKey) {
      return json({ error: 'TTS not configured (ELEVENLABS_API_KEY missing).' }, 500);
    }

    /* ── Upstream call (stream through) ───────────────────── */
    const upstream = await fetch(
      `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}/stream`,
      {
        method: 'POST',
        headers: {
          'xi-api-key': apiKey,
          'Content-Type': 'application/json',
          'Accept': 'audio/mpeg',
        },
        body: JSON.stringify({
          text,
          model_id: modelId,
          voice_settings: { stability, similarity_boost: similarityBoost },
        }),
      },
    );

    if (!upstream.ok) {
      // Free-tier plans can't use library voices via the API → 402.
      // Surface a clear, friendly message instead of a raw dump.
      if (upstream.status === 402) {
        return json(
          {
            error:
              "Voice playback needs a paid ElevenLabs plan — the free tier can't use this voice.",
          },
          402,
        );
      }
      const detail = await upstream.text().catch(() => '');
      return json({ error: `TTS error ${upstream.status}: ${detail}` }, 502);
    }

    // Pass the audio stream straight back to the client (low memory).
    return new Response(upstream.body, {
      status: 200,
      headers: {
        ...corsHeaders,
        'Content-Type': 'audio/mpeg',
        'Cache-Control': 'no-store',
      },
    });
  } catch (err) {
    return json({ error: `Unexpected error: ${(err as Error)?.message ?? err}` }, 500);
  }
});
