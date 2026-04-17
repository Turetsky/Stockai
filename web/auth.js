/**
 * auth.js
 * Handles Supabase client setup and authentication guard.
 * Must be loaded before sidebar.js on every page.
 * Fires 'auth-ready' when complete so sidebar.js can proceed.
 */
(async function initializeAuth() {

  // ============================================================================
  // 1. INITIALIZE SUPABASE CLIENT
  // ============================================================================
  if (!window.supabase) {
    console.error('Supabase library not loaded.');
    return;
  }

  const SUPABASE_URL = window.SUPABASE_URL || 'https://masngvxdbxqrrreszjxv.supabase.co';
  const SUPABASE_ANON_KEY = window.SUPABASE_ANON_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1hc25ndnhkYnhxcnJyZXN6anh2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA3Njc5MzIsImV4cCI6MjA4NjM0MzkzMn0.QmHFsyeMUkwE7cW6N88k2eSk2BpyXit2UxVlqXxl4zE';

  if (!window.db) {
    window.db = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  }

  // ============================================================================
  // 2. AUTH GUARD
  // ============================================================================
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
    return;
  }

  window.currentSession = session;
  window.currentUser = user;

  // ============================================================================
  // 3. KEEP SESSION FRESH
  // Keep window.currentSession up to date when Supabase auto-refreshes the token.
  // Without this, access_token goes stale after ~1 hour and requests get rejected.
  // ============================================================================
  window.db.auth.onAuthStateChange((event, newSession) => {
    if (newSession) {
      window.currentSession = newSession;
      window.currentUser    = newSession.user;
    }
  });

  // ============================================================================
  // 4. SIGNAL THAT AUTH IS COMPLETE
  // sidebar.js listens for this before building the UI.
  // ============================================================================
  window.authReady = true;
  window.dispatchEvent(new CustomEvent('auth-ready'));

})();
