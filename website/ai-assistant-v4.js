/**
 * ai-assistant-v4.js
 * Floating AI chat widget — the sparkle button + chat panel in the bottom-right.
 *
 * Builds itself once sidebar.js fires `sidebar-ready`. Sends every message to
 * the Supabase Edge Function with a freshly refreshed JWT, prepends the running
 * conversation + current-page context, and renders the reply. If the backend
 * says `refresh: true` or `navigate: <url>`, the client reacts accordingly.
 */
(function () {
  'use strict';

  // ============================================================================
  // 1. SETUP + STATE
  // ============================================================================
  const AI_ENDPOINT = window.SUPABASE_URL + '/functions/v1/smart-api';

  let chatHistory = [];
  let isOpen      = false;

  // ============================================================================
  // 2. AUTH HELPERS
  // ============================================================================

  function isAuthenticated() {
    return window.currentSession && window.currentSession.access_token;
  }

  /**
   * Returns Authorization headers with a guaranteed-fresh JWT.
   * Calls refreshSession() first (getSession() returns cached, possibly
   * expired tokens — the Edge Function's JWT enforcement rejects those).
   * Falls back to getSession() and then the cached session if refresh fails.
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

  // ============================================================================
  // 3. CONTEXT HELPERS
  // ============================================================================

  function getContext() {
    const params    = new URLSearchParams(window.location.search);
    const tableName = params.get('table');
    return {
      page:      tableName ? 'inventory' : 'dashboard',
      tableName: tableName || null,
    };
  }

  // ============================================================================
  // 4. REFRESH HOOKS
  // ============================================================================

  function triggerRefresh() {
    // App-wide signal: any page listening for 'data-changed' will refresh itself.
    window.dispatchEvent(new CustomEvent('data-changed'));
  }

  // ============================================================================
  // 5. WIDGET CREATION
  // ============================================================================

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
        <button id="ai-chat-close" title="Close"><span class="close-x">✕</span><span class="close-chevron">⌄</span></button>
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

  // ============================================================================
  // 6. MESSAGE RENDERING
  // ============================================================================

  function addMessage(text, role) {
    const container = document.getElementById('ai-chat-messages');
    const el        = document.createElement('div');
    el.className    = role === 'user' ? 'user-msg' : 'ai-msg';
    if (role === 'user') {
      el.textContent = text;
    } else {
      // Strip markdown bold/italic markers so raw ** don't appear
      const clean = text
        .replace(/\*\*(.+?)\*\*/g, '$1')  // **bold** → bold
        .replace(/\*(.+?)\*/g, '$1')       // *italic* → italic
        .replace(/`(.+?)`/g, '$1');        // `code` → code
      el.textContent = clean;
    }
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

  // ============================================================================
  // 7. SEND MESSAGE
  // ============================================================================

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

      const reply = data.message || '(No response)';
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

  // ============================================================================
  // 8. STYLES
  // ============================================================================

  function injectStyles() {
    const css = `
      #ai-chat-btn {
        position: fixed;
        bottom: 24px;
        right: 24px;
        width: 48px;
        height: 48px;
        background: linear-gradient(135deg, var(--clr-start, #667eea), var(--clr-end, #764ba2));
        border: none;
        border-radius: 50%;
        font-size: 20px;
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
        width: 370px;
        height: 540px;
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
        color: var(--clr-text-primary, var(--clr-text, #333));
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

      .close-chevron { display: none; font-size: 20px; line-height: 1; }
      .close-x       { display: inline; }

      @media (max-width: 639px) {
        #ai-chat-btn {
          bottom: 72px;
          right: 14px;
          width: 44px;
          height: 44px;
          font-size: 18px;
        }
        #ai-chat-panel {
          top: 0 !important;
          left: 0 !important;
          right: 0 !important;
          bottom: 0 !important;
          width: 100% !important;
          height: 100% !important;
          border-radius: 0;
          max-width: none;
        }
        #ai-chat-header {
          padding-top: max(16px, env(safe-area-inset-top, 16px));
        }
        .close-x       { display: none; }
        .close-chevron { display: inline; }
        #ai-chat-close {
          width: 36px;
          height: 36px;
          font-size: 22px;
        }
      }
    `;
    const style       = document.createElement('style');
    style.textContent = css;
    document.head.appendChild(style);
  }

  // ============================================================================
  // 9. INIT
  // ============================================================================

  // sidebar.js fires 'sidebar-ready' once auth succeeded and the sidebar is
  // mounted. By then the DOM is ready and window.currentSession exists, so
  // we can create the widget directly — no DOMContentLoaded dance needed.
  window.addEventListener('sidebar-ready', () => {
    if (isAuthenticated()) createWidget();
  });

  // Public hook so other UI (e.g. the dashboard AI command bar) can drive the
  // assistant: opens the panel and, if text is given, sends it as a message.
  window.askStockAI = function (text) {
    if (!isAuthenticated()) { alert('Please log in to use the AI Assistant.'); return; }
    const panel = document.getElementById('ai-chat-panel');
    if (!panel) return;
    if (!isOpen) toggleChat();
    const input = document.getElementById('ai-chat-input');
    if (input && typeof text === 'string') input.value = text;
    if (text && text.trim()) sendMessage();
    else if (input) setTimeout(() => input.focus(), 120);
  };
})();
