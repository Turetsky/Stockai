/**
 * AI Assistant — Floating Chat Widget  (v4.0)
 *
 * Changes from v3:
 *  - Uses supabase.auth.refreshSession() instead of getSession()
 *    to guarantee a fresh, non-stale JWT on every request.
 *    This is the fix for "invalid JWT" errors when JWT enforcement is ON.
 *  - Falls back gracefully to cached session if refresh fails (offline, etc.)
 *  - Panel dimensions driven by CSS custom properties (setAIPanelSize still works)
 *  - Everything else (context, history, refresh hooks) unchanged.
 */
(function () {
  'use strict';

  const AI_ENDPOINT = 'https://masngvxdbxqrrreszjxv.supabase.co/functions/v1/smart-api';

  const AI_PANEL_SIZES = {
    small:  { width: '300px', height: '420px' },
    medium: { width: '370px', height: '540px' },
    large:  { width: '480px', height: '660px' },
  };

  let chatHistory = [];
  let isOpen      = false;

  /* ── Auth helpers ─────────────────────────────────────────── */

  function isAuthenticated() {
    return window.currentSession && window.currentSession.access_token;
  }

  /**
   * Get Authorization headers with a guaranteed-fresh JWT.
   *
   * KEY CHANGE vs v3:
   *   We call refreshSession() instead of getSession().
   *   getSession() returns the cached token even if it's about to expire.
   *   refreshSession() always exchanges for a new token when possible,
   *   which is what Supabase JWT enforcement requires.
   */
  async function getAuthHeaders() {
    if (window.db) {
      try {
        // refreshSession() forces a token refresh. This is the correct call
        // when JWT enforcement is ON, because the gateway validates expiry strictly.
        const { data, error } = await window.db.auth.refreshSession();

        if (!error && data?.session?.access_token) {
          // Keep cached session in sync
          window.currentSession = data.session;
          return {
            'Content-Type':  'application/json',
            'Authorization': `Bearer ${data.session.access_token}`,
          };
        }
      } catch (refreshErr) {
        console.warn('refreshSession() failed, falling back to cached token:', refreshErr);
      }

      // Fallback: try getSession() if refresh failed (e.g. network issue)
      try {
        const { data } = await window.db.auth.getSession();
        if (data?.session?.access_token) {
          window.currentSession = data.session;
          return {
            'Content-Type':  'application/json',
            'Authorization': `Bearer ${data.session.access_token}`,
          };
        }
      } catch (sessionErr) {
        console.warn('getSession() also failed:', sessionErr);
      }
    }

    // Last resort: use cached window.currentSession
    if (isAuthenticated()) {
      return {
        'Content-Type':  'application/json',
        'Authorization': `Bearer ${window.currentSession.access_token}`,
      };
    }

    // No token available
    return { 'Content-Type': 'application/json' };
  }

  /* ── Context helpers ──────────────────────────────────────── */

  function getContext() {
    const params    = new URLSearchParams(window.location.search);
    const tableName = params.get('table');
    return {
      page:      tableName ? 'inventory' : 'dashboard',
      tableName: tableName || null,
    };
  }

  /* ── Refresh hooks ────────────────────────────────────────── */

  function triggerRefresh() {
    window.dispatchEvent(new CustomEvent('ai-refresh'));
    if (typeof window.loadInventoryCards === 'function') {
      setTimeout(window.loadInventoryCards, 500);
    }
    if (typeof window.fetchItemsGlobal === 'function') {
      setTimeout(window.fetchItemsGlobal, 500);
    }
  }

  /* ── Widget creation ──────────────────────────────────────── */

  function createWidget() {
    if (!isAuthenticated()) return;

    injectStyles();

    // Floating button
    const btn    = document.createElement('button');
    btn.id       = 'ai-chat-btn';
    btn.title    = 'AI Assistant';
    btn.innerHTML = '✨';
    btn.addEventListener('click', toggleChat);
    document.body.appendChild(btn);

    // Chat panel
    const panel  = document.createElement('div');
    panel.id     = 'ai-chat-panel';
    panel.innerHTML = `
      <div id="ai-chat-header">
        <span style="font-size:20px">🤖</span>
        <h3>AI Assistant</h3>
        <button id="ai-chat-close" title="Close">✕</button>
      </div>
      <div id="ai-chat-messages">
        <div class="ai-msg">Hi! I can help you manage inventory and customize the app. Try asking:
• "Create a new category called Cables"
• "Show low-stock items in the toners tab"
• "Sort the dashboard alphabetically"
• "Make the theme dark blue"
• "Change the item card background to light gray"
• "Move the search bar to its own row"
• "Make the inventory cards more compact"
• "Make the AI chat window bigger"
• "Sort items by quantity by default"
What would you like to do?</div>
      </div>
      <div id="ai-chat-input-area">
        <textarea id="ai-chat-input" rows="1" placeholder="Ask me anything…"></textarea>
        <button id="ai-send-btn" title="Send">➤</button>
      </div>
    `;
    document.body.appendChild(panel);

    document.getElementById('ai-chat-close').addEventListener('click', toggleChat);
    document.getElementById('ai-send-btn').addEventListener('click', sendMessage);
    document.getElementById('ai-chat-input').addEventListener('keydown', function (e) {
      if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); sendMessage(); }
    });
    document.getElementById('ai-chat-input').addEventListener('input', function () {
      this.style.height = 'auto';
      this.style.height = Math.min(this.scrollHeight, 120) + 'px';
    });
  }

  function toggleChat() {
    if (!isAuthenticated()) {
      alert('Please log in to use the AI Assistant.');
      return;
    }
    isOpen = !isOpen;
    const panel = document.getElementById('ai-chat-panel');
    panel.classList.toggle('open', isOpen);
    if (isOpen) setTimeout(() => document.getElementById('ai-chat-input').focus(), 100);
  }

  /* ── Message rendering ────────────────────────────────────── */

  function addMessage(text, role) {
    const container = document.getElementById('ai-chat-messages');
    const el        = document.createElement('div');
    el.className    = role === 'user' ? 'user-msg' : 'ai-msg';
    el.textContent  = text;
    container.appendChild(el);
    container.scrollTop = container.scrollHeight;
  }

  function showTyping() {
    const container = document.getElementById('ai-chat-messages');
    const el        = document.createElement('div');
    el.id           = 'ai-typing';
    el.className    = 'typing-indicator';
    el.innerHTML    = '<span></span><span></span><span></span>';
    container.appendChild(el);
    container.scrollTop = container.scrollHeight;
  }

  function hideTyping() {
    const el = document.getElementById('ai-typing');
    if (el) el.remove();
  }

  /* ── Send message ─────────────────────────────────────────── */

  async function sendMessage() {
    const input   = document.getElementById('ai-chat-input');
    const sendBtn = document.getElementById('ai-send-btn');
    const text    = input.value.trim();
    if (!text) return;

    input.value        = '';
    input.style.height = 'auto';
    sendBtn.disabled   = true;

    addMessage(text, 'user');
    chatHistory.push({ role: 'user', content: text });
    showTyping();

    try {
      const ctx = getContext();

      // Build message with conversation history prepended
      let fullMessage = text;
      if (chatHistory.length > 1) {
        const historyLines = chatHistory.slice(0, -1).map(m =>
          (m.role === 'user' ? 'User: ' : 'Assistant: ') + m.content
        ).join('\n');
        fullMessage = `[Previous conversation:\n${historyLines}\n]\n\nUser: ${text}`;
      }
      if (ctx.tableName) {
        fullMessage = `[Context: viewing inventory table "${ctx.tableName}"]\n` + fullMessage;
      }

      const headers = await getAuthHeaders();

      // If we couldn't get a token, bail early with a helpful message
      if (!headers['Authorization']) {
        hideTyping();
        addMessage('⚠️ Your session has expired. Please refresh the page and log in again.', 'ai');
        sendBtn.disabled = false;
        return;
      }

      const response = await fetch(AI_ENDPOINT, {
        method:  'POST',
        headers,
        body:    JSON.stringify({
          message:   fullMessage,
          inventory: [],
          context:   ctx,
        }),
      });

      if (!response.ok) {
        let errMsg = response.statusText;
        try {
          const e = await response.json();
          errMsg = e.error || e.message || errMsg;
        } catch { /* ignore parse error */ }

        // Surface auth errors clearly
        if (response.status === 401) {
          throw new Error('Session expired. Please refresh the page and log in again.');
        }
        throw new Error(errMsg);
      }

      const data = await response.json();
      hideTyping();

      let reply = '(No response)';
      if (data && Array.isArray(data.content) && data.content.length > 0) {
        reply = data.content.find(b => b.type === 'text')?.text || reply;
      } else if (data && typeof data.message === 'string') {
        reply = data.message;
      } else if (data && typeof data.text === 'string') {
        reply = data.text;
      }

      addMessage(reply, 'ai');
      chatHistory.push({ role: 'assistant', content: reply });

      if (data.refresh)  triggerRefresh();
      if (data.navigate) setTimeout(() => (window.location.href = data.navigate), 800);

    } catch (err) {
      hideTyping();
      addMessage('⚠️ ' + err.message, 'ai');
    }

    sendBtn.disabled = false;
    input.focus();
  }

  /* ── Public API ───────────────────────────────────────────── */

  window.setAIPanelSize = function (size) {
    const dims = AI_PANEL_SIZES[size] || AI_PANEL_SIZES.medium;
    document.documentElement.style.setProperty('--ai-panel-width',  dims.width);
    document.documentElement.style.setProperty('--ai-panel-height', dims.height);
  };

  /* ── Styles ───────────────────────────────────────────────── */

  function injectStyles() {
    const css = `
      :root {
        --ai-panel-width:  370px;
        --ai-panel-height: 540px;
      }

      #ai-chat-btn {
        position: fixed;
        bottom: 24px;
        right: 24px;
        width: 58px;
        height: 58px;
        background: linear-gradient(135deg, var(--clr-start, #667eea), var(--clr-end, #764ba2));
        border: none;
        border-radius: 50%;
        font-size: 24px;
        color: white;
        cursor: pointer;
        box-shadow: 0 4px 18px color-mix(in srgb, var(--clr-accent, #667eea) 55%, transparent);
        z-index: 9999;
        transition: transform 0.2s, box-shadow 0.2s;
        display: flex;
        align-items: center;
        justify-content: center;
      }
      #ai-chat-btn:hover {
        transform: scale(1.1);
        box-shadow: 0 6px 24px color-mix(in srgb, var(--clr-accent, #667eea) 70%, transparent);
      }

      #ai-chat-panel {
        position: fixed;
        bottom: 96px;
        right: 24px;
        width: var(--ai-panel-width, 370px);
        height: var(--ai-panel-height, 540px);
        background: var(--clr-card, #fff);
        border-radius: 18px;
        box-shadow: 0 10px 50px rgba(0,0,0,0.22);
        display: none;
        flex-direction: column;
        z-index: 9998;
        overflow: hidden;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
        animation: ai-slide-in 0.25s ease;
        transition: width 0.3s ease, height 0.3s ease;
      }
      #ai-chat-panel.open { display: flex; }
      @keyframes ai-slide-in {
        from { opacity: 0; transform: translateY(20px) scale(0.97); }
        to   { opacity: 1; transform: translateY(0) scale(1); }
      }

      #ai-chat-header {
        background: linear-gradient(135deg, var(--clr-start, #667eea), var(--clr-end, #764ba2));
        color: white;
        padding: 16px 18px;
        display: flex;
        align-items: center;
        gap: 10px;
        flex-shrink: 0;
      }
      #ai-chat-header h3 { margin: 0; font-size: 15px; flex: 1; font-weight: 700; }
      #ai-chat-close {
        background: rgba(255,255,255,0.2);
        border: none;
        color: white;
        font-size: 16px;
        width: 28px;
        height: 28px;
        border-radius: 50%;
        cursor: pointer;
        display: flex;
        align-items: center;
        justify-content: center;
        transition: background 0.2s;
      }
      #ai-chat-close:hover { background: rgba(255,255,255,0.35); }

      #ai-chat-messages {
        flex: 1;
        overflow-y: auto;
        padding: 16px;
        display: flex;
        flex-direction: column;
        gap: 10px;
        background: var(--clr-bg, #f8f8fc);
      }
      #ai-chat-messages::-webkit-scrollbar       { width: 5px; }
      #ai-chat-messages::-webkit-scrollbar-thumb { background: rgba(0,0,0,0.15); border-radius: 4px; }

      .ai-msg, .user-msg {
        max-width: 86%;
        padding: 11px 15px;
        border-radius: 14px;
        font-size: 13.5px;
        line-height: 1.55;
        white-space: pre-wrap;
        word-break: break-word;
      }
      .ai-msg {
        background: var(--clr-card, #fff);
        color: var(--clr-text, #333);
        align-self: flex-start;
        border-bottom-left-radius: 4px;
        box-shadow: 0 1px 4px rgba(0,0,0,0.08);
      }
      .user-msg {
        background: linear-gradient(135deg, var(--clr-start, #667eea), var(--clr-end, #764ba2));
        color: white;
        align-self: flex-end;
        border-bottom-right-radius: 4px;
      }

      .typing-indicator {
        display: flex;
        gap: 5px;
        align-items: center;
        padding: 12px 16px;
        background: var(--clr-card, #fff);
        border-radius: 14px;
        border-bottom-left-radius: 4px;
        align-self: flex-start;
        box-shadow: 0 1px 4px rgba(0,0,0,0.08);
      }
      .typing-indicator span {
        display: block;
        width: 7px;
        height: 7px;
        background: #bbb;
        border-radius: 50%;
        animation: ai-bounce 1.3s infinite;
      }
      .typing-indicator span:nth-child(2) { animation-delay: 0.18s; }
      .typing-indicator span:nth-child(3) { animation-delay: 0.36s; }
      @keyframes ai-bounce {
        0%, 60%, 100% { transform: translateY(0);   opacity: 0.4; }
        30%            { transform: translateY(-7px); opacity: 1;   }
      }

      #ai-chat-input-area {
        padding: 12px 14px;
        border-top: 1px solid rgba(0,0,0,0.1);
        display: flex;
        gap: 8px;
        align-items: flex-end;
        background: var(--clr-card, white);
        flex-shrink: 0;
      }
      #ai-chat-input {
        flex: 1;
        padding: 10px 14px;
        border: 2px solid rgba(0,0,0,0.12);
        border-radius: 10px;
        font-size: 13.5px;
        font-family: inherit;
        outline: none;
        resize: none;
        max-height: 120px;
        overflow-y: auto;
        transition: border-color 0.2s;
        line-height: 1.4;
      }
      #ai-chat-input:focus { border-color: var(--clr-accent, #667eea); }
      #ai-send-btn {
        width: 40px;
        height: 40px;
        background: linear-gradient(135deg, var(--clr-start, #667eea), var(--clr-end, #764ba2));
        color: white;
        border: none;
        border-radius: 10px;
        cursor: pointer;
        font-size: 16px;
        display: flex;
        align-items: center;
        justify-content: center;
        flex-shrink: 0;
        transition: opacity 0.2s, transform 0.2s;
      }
      #ai-send-btn:hover    { transform: scale(1.05); }
      #ai-send-btn:disabled { opacity: 0.45; cursor: not-allowed; transform: none; }
    `;
    const style       = document.createElement('style');
    style.textContent = css;
    document.head.appendChild(style);
  }

  /* ── Init ─────────────────────────────────────────────────── */

  function initWidget() {
    if (!isAuthenticated()) return;
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', createWidget);
    } else {
      createWidget();
    }
  }

  window.addEventListener('sidebar-ready', initWidget);

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initWidget);
  } else {
    initWidget();
  }
})();
