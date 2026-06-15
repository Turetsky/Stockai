/**
 * sidebar.js
 * Builds and injects the navigation UI on every page.
 * Owns two components that share state:
 *   - The desktop sidebar (left rail with categories + profile).
 *   - The mobile topbar (56px header with hamburger that reveals the sidebar).
 * Depends on auth.js — awaits `window.authReady` before rendering.
 */
(async function initializeSidebar() {

  // ============================================================================
  // 1. APPLY THEME FROM LOCALSTORAGE (before rendering)
  // ============================================================================
  // theme-init.js (loaded in <head>) already applied the saved theme and exposes
  // window.applyThemeVars + window.THEME_CSS_MAP. Re-apply here as a fallback in
  // case the page didn't include theme-init.js.
  try {
    if (window.applyThemeVars) {
      window.applyThemeVars(JSON.parse(localStorage.getItem('inv_theme') || '{}'));
    }
  } catch (e) { /* ignore malformed localStorage */ }

  // ============================================================================
  // 2. WAIT FOR AUTH
  // auth.js exposes `window.authReady` as a Promise that only resolves on
  // success — if auth failed, it stays pending and this line never returns.
  // ============================================================================
  await window.authReady;
  const user = window.currentUser;

  // Guest / unauthenticated (e.g. the public about.html). There is no user to
  // render a sidebar for, so just reveal the page and stop — no sidebar, no
  // AI widget (it waits on 'sidebar-ready', which we intentionally don't fire).
  if (!user) {
    document.body.classList.add('loaded');
    return;
  }

  // ============================================================================
  // 3. LOAD CATEGORIES (table_definitions)
  // ============================================================================
  let categories = [];
  await loadCategories();

  // ============================================================================
  // 4. ADD SIDEBAR STYLES
  // ============================================================================
  const styleElement = document.createElement('style');
  styleElement.textContent = `
    /* Sidebar theme defaults (overridden by user theme) */
    :root {
      --clr-sidebar-bg:     #1e293b;
      --clr-sidebar-header: #0f172a;
      --clr-sidebar-text:   #94a3b8;
      --clr-sidebar-title:  #f1f5f9;
    }

    /* Sidebar Container */
    .sidebar {
      position: fixed;
      left: 0;
      top: 0;
      bottom: 0;
      width: 260px;
      background: var(--clr-sidebar-bg);
      color: var(--clr-sidebar-text);
      display: flex;
      flex-direction: column;
      z-index: 1000;
      box-shadow: 2px 0 8px rgba(0, 0, 0, 0.3);
      transition: transform 0.3s ease-in-out;
    }

    /* Sidebar Header */
    .sidebar-header {
      background: var(--clr-sidebar-header);
      padding: 20px;
      display: flex;
      align-items: center;
      gap: 12px;
      border-bottom: 1px solid rgba(255, 255, 255, 0.06);
    }

    .sidebar-logo {
      font-size: 28px;
      flex-shrink: 0;
    }

    .sidebar-title-group {
      display: flex;
      flex-direction: column;
      gap: 2px;
      min-width: 0;
    }

    .sidebar-title {
      font-size: 1.07rem;
      font-weight: 600;
      color: var(--clr-sidebar-title);
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }

    .sidebar-slogan {
      font-size: 0.7rem;
      color: rgba(255, 255, 255, 0.45);
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }

    /* Sidebar Navigation */
    .sidebar-nav {
      flex: 1;
      overflow-y: auto;
      padding: 12px 0;
    }

    .nav-item {
      display: flex;
      align-items: center;
      gap: 12px;
      padding: 10px 20px;
      color: var(--clr-sidebar-text);
      text-decoration: none;
      cursor: pointer;
      transition: all 0.2s ease-in-out;
      font-size: 0.93rem;
      border-left: 3px solid transparent;
      position: relative;
    }

    .nav-item:hover {
      background: rgba(255, 255, 255, 0.08);
      color: var(--clr-sidebar-title);
    }

    .nav-item.active {
      background: rgba(255, 255, 255, 0.12);
      color: var(--clr-sidebar-title);
      border-left-color: var(--clr-accent);
      font-weight: 500;
    }

    .nav-icon {
      font-size: 1.2rem;
      flex-shrink: 0;
      width: 20px;
      text-align: center;
    }

    .nav-divider {
      height: 1px;
      background: rgba(255, 255, 255, 0.08);
      margin: 12px 0;
    }

    .nav-section {
      font-size: 0.73rem;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0.5px;
      color: var(--clr-sidebar-text);
      opacity: 0.65;
      padding: 12px 20px 8px 20px;
    }

    /* Sidebar Footer */
    .sidebar-footer {
      background: var(--clr-sidebar-header);
      border-top: 1px solid rgba(255, 255, 255, 0.06);
      padding: 16px 20px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 12px;
    }

    .sidebar-user {
      display: flex;
      align-items: center;
      gap: 10px;
      flex: 1;
      min-width: 0;
    }

    .user-avatar {
      width: 36px;
      height: 36px;
      border-radius: 50%;
      background: var(--clr-accent);
      color: white;
      display: flex;
      align-items: center;
      justify-content: center;
      font-weight: 600;
      font-size: 0.8rem;
      flex-shrink: 0;
    }

    .user-details {
      display: flex;
      flex-direction: column;
      gap: 2px;
      min-width: 0;
    }

    .user-name {
      font-size: 0.87rem;
      font-weight: 500;
      color: var(--clr-sidebar-title);
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }

    .user-email {
      font-size: 0.73rem;
      color: var(--clr-sidebar-text);
      opacity: 0.75;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }

    .sidebar-logout-btn {
      width: 36px;
      height: 36px;
      border-radius: 6px;
      background: rgba(255, 255, 255, 0.08);
      border: none;
      color: var(--clr-sidebar-text);
      font-size: 1.2rem;
      cursor: pointer;
      display: flex;
      align-items: center;
      justify-content: center;
      transition: all 0.2s ease-in-out;
      flex-shrink: 0;
    }

    .sidebar-logout-btn:hover {
      background: rgba(255, 255, 255, 0.15);
      color: var(--clr-sidebar-title);
    }

    /* Main Content */
    .main-content {
      margin-left: 260px;
      transition: margin-left 0.3s ease-in-out;
      min-height: 100vh;
    }

    /* Mobile Topbar */
    .mobile-topbar {
      display: none;
      position: fixed;
      top: 0;
      left: 0;
      right: 0;
      height: 56px;
      background: var(--clr-sidebar-bg);
      border-bottom: 1px solid rgba(255, 255, 255, 0.06);
      align-items: center;
      gap: 12px;
      padding: 0 16px;
      z-index: 999;
      box-shadow: 0 2px 8px rgba(0, 0, 0, 0.2);
    }

    .hamburger-btn {
      width: 40px;
      height: 40px;
      border-radius: 6px;
      background: rgba(255, 255, 255, 0.08);
      border: none;
      color: var(--clr-sidebar-title);
      font-size: 1.33rem;
      cursor: pointer;
      display: flex;
      align-items: center;
      justify-content: center;
      transition: all 0.2s ease-in-out;
      flex-shrink: 0;
    }

    .hamburger-btn:active {
      background: rgba(255, 255, 255, 0.15);
    }

    .mobile-title {
      font-size: 1.07rem;
      font-weight: 600;
      color: var(--clr-sidebar-title);
      flex: 1;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }

    /* Sidebar Overlay */
    .sidebar-overlay {
      display: none;
      position: fixed;
      top: 0;
      left: 0;
      right: 0;
      bottom: 0;
      background: rgba(0, 0, 0, 0.5);
      z-index: 999;
      transition: opacity 0.3s ease-in-out;
    }

    .sidebar-overlay.open {
      display: block;
    }

    /* Mobile Responsive */
    @media (max-width: 768px) {
      .sidebar {
        transform: translateX(-100%);
      }

      .sidebar.open {
        transform: translateX(0);
      }

      .main-content {
        margin-left: 0;
        margin-top: 56px;
      }

      .mobile-topbar {
        display: flex;
      }
    }

    /* Scrollbar Styling */
    .sidebar-nav::-webkit-scrollbar {
      width: 6px;
    }

    .sidebar-nav::-webkit-scrollbar-track {
      background: transparent;
    }

    .sidebar-nav::-webkit-scrollbar-thumb {
      background: rgba(255, 255, 255, 0.1);
      border-radius: 3px;
    }

    .sidebar-nav::-webkit-scrollbar-thumb:hover {
      background: rgba(255, 255, 255, 0.15);
    }

    /* ── Feedback modal ─────────────────────────────────── */
    .feedback-modal-backdrop {
      position: fixed;
      inset: 0;
      background: rgba(0,0,0,0.5);
      z-index: 9999;
      display: flex;
      align-items: flex-end;
      justify-content: flex-start;
      padding: 0 0 80px 16px;
      opacity: 0;
      pointer-events: none;
      transition: opacity 0.2s ease;
    }
    .feedback-modal-backdrop.open {
      opacity: 1;
      pointer-events: all;
    }
    .feedback-modal {
      background: #1e293b;
      border: 1px solid rgba(255,255,255,0.1);
      border-radius: 12px;
      width: 320px;
      box-shadow: 0 8px 32px rgba(0,0,0,0.4);
      display: flex;
      flex-direction: column;
      overflow: hidden;
      transform: translateY(12px);
      transition: transform 0.2s ease;
    }
    .feedback-modal-backdrop.open .feedback-modal {
      transform: translateY(0);
    }
    .feedback-modal-header {
      background: #0f172a;
      padding: 12px 16px;
      display: flex;
      align-items: center;
      justify-content: space-between;
    }
    .feedback-modal-title {
      color: #f1f5f9;
      font-size: 14px;
      font-weight: 600;
    }
    .feedback-modal-close {
      background: none;
      border: none;
      color: #94a3b8;
      cursor: pointer;
      font-size: 16px;
      line-height: 1;
      padding: 0;
    }
    .feedback-modal-close:hover { color: #f1f5f9; }
    .feedback-modal-body {
      padding: 14px 16px;
      display: flex;
      flex-direction: column;
      gap: 10px;
    }
    .feedback-modal-textarea {
      background: #0f172a;
      border: 1px solid rgba(255,255,255,0.1);
      border-radius: 8px;
      color: #f1f5f9;
      font-size: 13px;
      padding: 10px 12px;
      resize: none;
      min-height: 100px;
      font-family: inherit;
      outline: none;
    }
    .feedback-modal-textarea:focus {
      border-color: rgba(255,255,255,0.25);
    }
    .feedback-modal-submit {
      background: #3b82f6;
      border: none;
      border-radius: 8px;
      color: #fff;
      cursor: pointer;
      font-size: 13px;
      font-weight: 600;
      padding: 9px 16px;
      transition: background 0.15s ease;
    }
    .feedback-modal-submit:hover:not(:disabled) { background: #2563eb; }
    .feedback-modal-submit:disabled {
      opacity: 0.6;
      cursor: not-allowed;
    }
    .feedback-modal-status {
      font-size: 12px;
      color: #94a3b8;
      min-height: 16px;
      text-align: center;
    }
  `;
  document.head.appendChild(styleElement);

  // ============================================================================
  // 5. HELPER FUNCTIONS
  // ============================================================================

  /** Fetches this user's categories and writes them into the shared `categories` variable. */
  async function loadCategories() {
    try {
      const { data, error } = await window.db
        .from('table_definitions')
        .select('*')
        .eq('user_id', window.currentUser?.id)
        .order('display_name');
      if (error) throw error;
      categories = data || [];
    } catch (e) {
      console.warn('Categories load failed:', e);
      categories = [];
    }
  }

  /** Returns up to 2 uppercase initials from a name (used for the avatar circle). */
  function getInitials(name) {
    if (!name) return '?';
    return name
      .split(' ')
      .map(word => word[0])
      .join('')
      .toUpperCase()
      .slice(0, 2);
  }

  /** Returns a human-readable title for the current page (used by the mobile topbar). */
  function getCurrentPageName() {
    const path = window.location.pathname;
    const searchParams = new URLSearchParams(window.location.search);

    if (path.includes('index.html')) return 'Dashboard';
    if (path.includes('inventory.html')) {
      const tableName = searchParams.get('table');
      if (tableName) {
        const category = categories.find(c => c.table_name === tableName);
        return category?.display_name || 'Inventory';
      }
      return 'Inventory';
    }
    if (path.includes('settings.html')) return 'Settings';
    return 'StockAI';
  }

  /** Returns true if this link matches the current URL, so the sidebar can highlight it. */
  function isNavItemActive(href) {
    const path = window.location.pathname;
    const searchParams = new URLSearchParams(window.location.search);

    if (href === 'index.html') {
      return path.includes('index.html');
    }

    if (href.includes('inventory.html')) {
      if (!path.includes('inventory.html')) return false;
      const hrefTable = new URLSearchParams(href.split('?')[1]).get('table');
      const currentTable = searchParams.get('table');
      return hrefTable === currentTable;
    }

    if (href === 'settings.html') {
      return path.includes('settings.html');
    }

    return false;
  }

  // ============================================================================
  // 6. BUILDERS
  // ============================================================================

  /** Builds and returns the <nav> element (Dashboard, categories, Settings, Feedback, About). */
  function buildNav() {
    const nav = document.createElement('nav');
    nav.className = 'sidebar-nav';

    // Dashboard link
    const dashboardLink = document.createElement('a');
    dashboardLink.className = 'nav-item' + (isNavItemActive('index.html') ? ' active' : '');
    dashboardLink.href = 'index.html';
    dashboardLink.innerHTML = `
      <span class="nav-icon">📊</span>
      <span>Dashboard</span>
    `;
    nav.appendChild(dashboardLink);

    // Categories divider + section label + links
    if (categories.length > 0) {
      const divider1 = document.createElement('div');
      divider1.className = 'nav-divider';
      nav.appendChild(divider1);

      const categorySection = document.createElement('div');
      categorySection.className = 'nav-section';
      categorySection.textContent = 'Categories';
      nav.appendChild(categorySection);

      categories.forEach(category => {
        const link = document.createElement('a');
        const href = `inventory.html?table=${encodeURIComponent(category.table_name)}`;
        link.className = 'nav-item' + (isNavItemActive(href) ? ' active' : '');
        link.href = href;
        link.innerHTML = `
          <span class="nav-icon">${category.icon || '📋'}</span>
          <span>${category.display_name}</span>
        `;
        nav.appendChild(link);
      });
    }

    // Settings
    const divider2 = document.createElement('div');
    divider2.className = 'nav-divider';
    nav.appendChild(divider2);

    const settingsLink = document.createElement('a');
    settingsLink.className = 'nav-item' + (isNavItemActive('settings.html') ? ' active' : '');
    settingsLink.href = 'settings.html';
    settingsLink.innerHTML = `
      <span class="nav-icon">⚙️</span>
      <span>Settings</span>
    `;
    nav.appendChild(settingsLink);

    // Feedback button
    const contactDivider = document.createElement('div');
    contactDivider.className = 'nav-divider';
    nav.appendChild(contactDivider);

    const contactLink = document.createElement('button');
    contactLink.className = 'nav-item';
    contactLink.style.cssText = 'width:100%;background:none;border:none;cursor:pointer;text-align:left;';
    contactLink.addEventListener('click', () => openFeedbackModal());
    const contactIcon = document.createElement('span');
    contactIcon.className = 'nav-icon';
    contactIcon.textContent = '\u2709\uFE0F';
    const contactText = document.createElement('span');
    contactText.textContent = 'Send Feedback';
    contactLink.appendChild(contactIcon);
    contactLink.appendChild(contactText);
    nav.appendChild(contactLink);

    // About link
    const aboutLink = document.createElement('a');
    aboutLink.className = 'nav-item';
    aboutLink.href = 'about.html';
    aboutLink.style.cssText = 'text-decoration:none;';
    aboutLink.innerHTML = '<span class="nav-icon">ℹ️</span><span>About</span>';
    nav.appendChild(aboutLink);

    return nav;
  }

  /** Builds and returns the sidebar <aside> element (header, nav, categories, profile footer). */
  function buildSidebar() {
    // Create sidebar element
    const sidebar = document.createElement('aside');
    sidebar.className = 'sidebar';
    sidebar.id = 'sidebar';

    // Header
    const header = document.createElement('div');
    header.className = 'sidebar-header';
    const logoSvg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" fill="none" stroke="currentColor" stroke-width="4" stroke-linejoin="round" stroke-linecap="round" style="width:28px;height:28px;flex-shrink:0"><polygon points="50,10 90,30 90,70 50,90 10,70 10,30"/><polyline points="10,30 50,50 90,30"/><line x1="50" y1="50" x2="50" y2="90"/></svg>`;
    header.innerHTML = `
      <div class="sidebar-logo">${logoSvg}</div>
      <div class="sidebar-title-group">
        <div class="sidebar-title">StockAI</div>
        <div class="sidebar-slogan">The database that builds itself.</div>
      </div>`;
    sidebar.appendChild(header);

    // Nav (shared with refreshSidebarCategories)
    sidebar.appendChild(buildNav());

    // Footer with user info
    const footer = document.createElement('div');
    footer.className = 'sidebar-footer';
    const displayName = window.currentProfile?.display_name || window.displayNameFrom(user.email);
    const userEmail = user.email || '';
    const initials = getInitials(displayName);
    footer.innerHTML = `
      <div class="sidebar-user">
        <div class="user-avatar">${initials}</div>
        <div class="user-details">
          <div class="user-name">${displayName}</div>
          <div class="user-email">${userEmail}</div>
        </div>
      </div>
      <button class="sidebar-logout-btn" title="Sign out" onclick="sidebarLogout()">⏻</button>
    `;
    sidebar.appendChild(footer);

    return sidebar;
  }

  /**
   * Build mobile topbar
   */
  function buildMobileTopbar() {
    const topbar = document.createElement('div');
    topbar.className = 'mobile-topbar';
    topbar.id = 'mobileTopbar';
    topbar.innerHTML = `
      <button class="hamburger-btn" onclick="toggleSidebar()">☰</button>
      <span class="mobile-title">${getCurrentPageName()}</span>
    `;
    return topbar;
  }

  /**
   * Build sidebar overlay
   */
  function buildOverlay() {
    const overlay = document.createElement('div');
    overlay.className = 'sidebar-overlay';
    overlay.id = 'sidebarOverlay';
    overlay.onclick = function() {
      toggleSidebar();
    };
    return overlay;
  }

  // ============================================================================
  // 7. GLOBAL FUNCTIONS
  // ============================================================================

  /**
   * Toggle sidebar on mobile
   */
  window.toggleSidebar = function() {
    const sidebar = document.getElementById('sidebar');
    const overlay = document.getElementById('sidebarOverlay');
    if (sidebar) sidebar.classList.toggle('open');
    if (overlay) overlay.classList.toggle('open');
  };

  /**
   * Logout handler
   */
  window.sidebarLogout = async function() {
    try {
      await window.db.auth.signOut();
      localStorage.removeItem('inv_theme');
      window.location.href = 'landing.html';
    } catch (e) {
      console.error('Logout failed:', e);
      window.location.href = 'landing.html';
    }
  };

  /**
   * Refresh categories and rebuild sidebar navigation
   */
  window.refreshSidebarCategories = async function() {
    await loadCategories();

    const sidebar = document.getElementById('sidebar');
    if (sidebar) {
      const oldNav = sidebar.querySelector('.sidebar-nav');
      if (oldNav) oldNav.remove();

      const header = sidebar.querySelector('.sidebar-header');
      header.parentNode.insertBefore(buildNav(), header.nextSibling);
    }
  };

  // Any page can fire `data-changed` to trigger a sidebar nav refresh.
  window.addEventListener('data-changed', () => window.refreshSidebarCategories());

  // ============================================================================
  // 8. FEEDBACK MODAL FUNCTIONS
  // ============================================================================

  function openFeedbackModal() {
    const backdrop = document.getElementById('feedbackModalBackdrop');
    const textarea = document.getElementById('feedbackTextarea');
    const status = document.getElementById('feedbackStatus');
    if (!backdrop) return;
    if (status) status.textContent = '';
    if (textarea) { textarea.value = ''; textarea.focus(); }
    backdrop.classList.add('open');
  }

  function closeFeedbackModal() {
    const backdrop = document.getElementById('feedbackModalBackdrop');
    if (backdrop) backdrop.classList.remove('open');
  }

  async function submitFeedback() {
    const textarea = document.getElementById('feedbackTextarea');
    const status = document.getElementById('feedbackStatus');
    const submitBtn = document.querySelector('.feedback-modal-submit');
    const message = textarea?.value?.trim();
    if (!message) {
      if (status) status.textContent = 'Please enter a message.';
      return;
    }

    if (submitBtn) submitBtn.disabled = true;
    if (status) status.textContent = 'Sending…';

    try {
      // Always get a fresh token before calling the edge function
      let accessToken = window.currentSession?.access_token;
      try {
        const { data } = await window.db.auth.refreshSession();
        if (data?.session?.access_token) accessToken = data.session.access_token;
      } catch (_) {}
      if (!accessToken) throw new Error('Not authenticated');

      const response = await fetch(
        window.SUPABASE_URL + '/functions/v1/smart-api',
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${accessToken}`,
          },
          body: JSON.stringify({
            tool_call: {
              name: 'send_feedback',
              input: {
                message,
                user_email: window.currentUser?.email || '',
              },
            },
          }),
        }
      );

      const data = await response.json();
      if (!response.ok || data.result?.startsWith('❌')) {
        throw new Error(data.result || data.error || 'Send failed');
      }

      // Send email via Web3Forms (client-side, no server needed)
      fetch('https://api.web3forms.com/submit', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          access_key: 'dd653064-1a32-4524-b218-08a1b972c011',
          subject: 'StockAI Feedback from ' + (window.currentUser?.email || 'unknown'),
          from_name: window.currentUser?.email || 'StockAI User',
          email: window.currentUser?.email || 'noreply@example.com',
          message,
        }),
      }).catch(() => {}); // fire-and-forget

      if (status) status.textContent = '✓ Sent! Thank you.';
      if (textarea) textarea.value = '';
      setTimeout(closeFeedbackModal, 1500);
    } catch (err) {
      if (status) status.textContent = 'Failed to send. Please try again.';
      console.error('Feedback error:', err);
    } finally {
      if (submitBtn) submitBtn.disabled = false;
    }
  }

  // ============================================================================
  // 9. ADD SIDEBAR TO PAGE
  // ============================================================================

  const sidebar = buildSidebar();
  const topbar = buildMobileTopbar();
  const overlay = buildOverlay();

  document.body.prepend(overlay);
  document.body.prepend(sidebar);
  document.body.prepend(topbar);

  // Inject feedback modal
  const feedbackBackdrop = document.createElement('div');
  feedbackBackdrop.className = 'feedback-modal-backdrop';
  feedbackBackdrop.id = 'feedbackModalBackdrop';
  feedbackBackdrop.addEventListener('click', (e) => {
    if (e.target === feedbackBackdrop) closeFeedbackModal();
  });

  const feedbackModal = document.createElement('div');
  feedbackModal.className = 'feedback-modal';

  const feedbackHeader = document.createElement('div');
  feedbackHeader.className = 'feedback-modal-header';
  const feedbackTitle = document.createElement('span');
  feedbackTitle.className = 'feedback-modal-title';
  feedbackTitle.textContent = 'Send Feedback';
  const feedbackClose = document.createElement('button');
  feedbackClose.className = 'feedback-modal-close';
  feedbackClose.textContent = '✕';
  feedbackClose.addEventListener('click', closeFeedbackModal);
  feedbackHeader.appendChild(feedbackTitle);
  feedbackHeader.appendChild(feedbackClose);

  const feedbackBody = document.createElement('div');
  feedbackBody.className = 'feedback-modal-body';

  const feedbackTextarea = document.createElement('textarea');
  feedbackTextarea.className = 'feedback-modal-textarea';
  feedbackTextarea.placeholder = 'Share a bug, idea, or anything on your mind…';
  feedbackTextarea.id = 'feedbackTextarea';

  const feedbackStatus = document.createElement('div');
  feedbackStatus.className = 'feedback-modal-status';
  feedbackStatus.id = 'feedbackStatus';

  const feedbackSubmit = document.createElement('button');
  feedbackSubmit.className = 'feedback-modal-submit';
  feedbackSubmit.textContent = 'Send';
  feedbackSubmit.addEventListener('click', submitFeedback);

  feedbackBody.appendChild(feedbackTextarea);
  feedbackBody.appendChild(feedbackStatus);
  feedbackBody.appendChild(feedbackSubmit);

  feedbackModal.appendChild(feedbackHeader);
  feedbackModal.appendChild(feedbackBody);
  feedbackBackdrop.appendChild(feedbackModal);
  document.body.appendChild(feedbackBackdrop);

  // Wrap main content if not already wrapped
  let mainContent = document.getElementById('mainContent');
  if (!mainContent) {
    mainContent = document.createElement('main');
    mainContent.className = 'main-content';
    mainContent.id = 'mainContent';
    while (document.body.firstChild && document.body.firstChild !== topbar && document.body.firstChild !== sidebar && document.body.firstChild !== overlay) {
      mainContent.appendChild(document.body.firstChild);
    }
    document.body.appendChild(mainContent);
  } else {
    mainContent.classList.add('main-content');
  }

  // ============================================================================
  // 10. SHOW PAGE
  // ============================================================================
  document.body.classList.add('loaded');

  // ============================================================================
  // 11. SIGNAL SIDEBAR IS READY
  // ============================================================================
  window.dispatchEvent(new CustomEvent('sidebar-ready'));
})();
