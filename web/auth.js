/**
 * auth.js
 * Sets up the Supabase client, checks the session, loads the user profile,
 * and signals "auth ready" to the rest of the page.
 *
 * Load order: after config.js + the Supabase library, before any script
 * that awaits `window.authReady` or listens for the 'auth-ready' event
 * (sidebar.js, ai-assistant-v4.js, each HTML's inline script, etc.).
 *
 * `window.authReady` is a Promise that resolves ONLY on a successful auth.
 * If there's no session, we redirect to landing.html and the promise stays
 * pending forever (the page is unloading anyway, so hanging consumers
 * never actually hang).
 */

/** "user@gmail.com" → "user". Shared by sidebar.js and the catch block below. */
window.displayNameFrom = (email) => email?.split('@')[0] || 'User';

window.authReady = new Promise((resolve) => {
  (async function initializeAuth() {

    // ========================================================================
    // 1. INITIALIZE SUPABASE CLIENT
    // ========================================================================
    if (!window.supabase) {
      console.error('Supabase library not loaded.');
      return;
    }

    window.db = window.supabase.createClient(window.SUPABASE_URL, window.SUPABASE_ANON_KEY);

    // ========================================================================
    // 2. AUTH GUARD
    // ========================================================================
    let session = null;
    let user = null;

    try {
      const { data, error } = await window.db.auth.getSession();
      if (error) throw error;
      session = data.session;
      user = data.session?.user;
    } catch (e) {
      console.error('Auth check failed:', e);
    }

    if (!session || !user) {
      window.location.href = 'landing.html';
      return;   // never resolve — page is redirecting
    }

    window.currentSession = session;
    window.currentUser = user;

    // ========================================================================
    // 3. LOAD USER PROFILE
    // ========================================================================
    try {
      const { data, error } = await window.db
        .from('profiles')
        .select('*')
        .eq('id', user.id)
        .single();
      if (error) throw error;
      window.currentProfile = data;
    } catch (e) {
      window.currentProfile = {
        id: user.id,
        display_name: window.displayNameFrom(user.email),
        email: user.email
      };
    }

    // ========================================================================
    // 4. KEEP SESSION FRESH
    // Keep window.currentSession up to date when Supabase auto-refreshes the
    // token. Without this, access_token goes stale after ~1 hour and requests
    // get rejected.
    // ========================================================================
    window.db.auth.onAuthStateChange((event, newSession) => {
      if (newSession) {
        window.currentSession = newSession;
        window.currentUser    = newSession.user;
      }
    });

    // ========================================================================
    // 5. SIGNAL THAT AUTH IS COMPLETE
    // Pages can either `await window.authReady` or listen for the 'auth-ready' event.
    // ========================================================================
    resolve();
    window.dispatchEvent(new CustomEvent('auth-ready'));
  })();
});
