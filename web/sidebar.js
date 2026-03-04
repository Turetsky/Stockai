/**
 * Sidebar Navigation Component
 * Shared IIFE that injects sidebar + auth guard into every page
 */
(async function initializeSidebar() {
  // ============================================================================
  // 1. APPLY THEME FROM LOCALSTORAGE (before rendering)
  // ============================================================================
  try {
    const theme = JSON.parse(localStorage.getItem('inv_theme') || '{}');
    const root = document.documentElement;
    const colorMap = {
      primary_color_start: '--clr-start',
      primary_color_end: '--clr-end',
      accent_color: '--clr-accent',
      bg_color: '--clr-bg',
      card_color: '--clr-card',
      card_radius: '--card-radius',
      header_text_color: '--clr-header-text',
      text_primary_color: '--clr-text-primary',
      text_secondary_color: '--clr-text-secondary',
      item_card_bg: '--clr-item-card',
      stats_bar_bg: '--clr-stats-bar',
      low_stock_color: '--clr-low-stock',
      btn_add_bg: '--clr-btn-add',
      btn_edit_bg: '--clr-btn-edit',
      btn_del_bg: '--clr-btn-del',
      dashboard_card_min_width: '--dash-card-min',
      sidebar_bg:     '--clr-sidebar-bg',
      sidebar_header: '--clr-sidebar-header',
      sidebar_text:   '--clr-sidebar-text',
      sidebar_title:  '--clr-sidebar-title'
    };
    for (const [key, cssVar] of Object.entries(colorMap)) {
      if (theme[key]) {
        root.style.setProperty(cssVar, theme[key]);
      }
    }
    // Extract leading emoji as logo; strip it from the title to avoid doubling
    // e.g. app_name "📦 Inventory Manager" → logo "📦", title "Inventory Manager"
    const rawName = theme.app_name || 'Inventory Manager';
    const emojiMatch = rawName.match(/^(\p{Emoji_Presentation}|\p{Extended_Pictographic})/u);
    window.appLogo = emojiMatch ? emojiMatch[0] : '';
    window.appName = rawName.replace(/^(\p{Emoji_Presentation}|\p{Extended_Pictographic})\s*/u, '').trim() || rawName;
  } catch (e) {
    window.appLogo = '';
    window.appName = 'Inventory Manager';
  }

  // ============================================================================
  // 2. INITIALIZE SUPABASE CLIENT
  // ============================================================================
  if (!window.supabase) {
    console.error('Supabase library not loaded. Ensure <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js"></script> is included.');
    return;
  }

  const SUPABASE_URL = 'https://masngvxdbxqrrreszjxv.supabase.co';
  const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1hc25ndnhkYnhxcnJyZXN6anh2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA3Njc5MzIsImV4cCI6MjA4NjM0MzkzMn0.QmHFsyeMUkwE7cW6N88k2eSk2BpyXit2UxVlqXxl4zE';

  if (!window.db) {
    window.db = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  }

  // ============================================================================
  // 3. AUTH GUARD
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

  // Keep window.currentSession up to date when Supabase auto-refreshes the token.
  // Without this, access_token goes stale after ~1 hour and JWT enforcement rejects it.
  window.db.auth.onAuthStateChange((event, newSession) => {
    if (newSession) {
      window.currentSession = newSession;
      window.currentUser    = newSession.user;
    }
  });

  // ============================================================================
  // 4. LOAD USER PROFILE
  // ============================================================================
  let profile = null;
  try {
    const { data, error } = await window.db
      .from('profiles')
      .select('*')
      .eq('id', user.id)
      .single();
    if (error) throw error;
    profile = data;
    window.currentProfile = profile;
  } catch (e) {
    console.warn('Profile load failed:', e);
    window.currentProfile = {
      id: user.id,
      display_name: user.email?.split('@')[0] || 'User',
      email: user.email
    };
  }

  // ============================================================================
  // 5. LOAD CATEGORIES (table_definitions)
  // ============================================================================
  let categories = [];
  try {
    const { data, error } = await window.db
      .from('table_definitions')
      .select('*')
      .eq('user_id', user.id)
      .order('display_name');
    if (error) throw error;
    categories = data || [];
  } catch (e) {
    console.warn('Categories load failed:', e);
    categories = [];
  }

  // ============================================================================
  // 6. INJECT STYLES
  // ============================================================================
  const styleElement = document.createElement('style');
  styleElement.textContent = `
    /* Sidebar theme defaults (overridden by user theme) */
    :root {
      --clr-sidebar-bg:     #1e293b;
      --clr-sidebar-header: #0f172a;
      --clr-sidebar-text:   #94a3b8;
      --clr-sidebar-title:  #f1f5f9;
      --font-base:          15px;
    }

    /* Scale the entire page with the user's chosen font size */
    html { font-size: var(--font-base); }

    /* Body fade-in on load */
    body {
      opacity: 0;
      transition: opacity 0.15s ease-in-out;
      margin: 0;
      padding: 0;
    }

    body.loaded {
      opacity: 1;
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

    .sidebar-title {
      font-size: 1.07rem;
      font-weight: 600;
      color: var(--clr-sidebar-title);
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
  `;
  document.head.appendChild(styleElement);

  // ============================================================================
  // 7. HELPER FUNCTIONS
  // ============================================================================

  /**
   * Get initials from a name
   */
  function getInitials(name) {
    if (!name) return '?';
    return name
      .split(' ')
      .map(word => word[0])
      .join('')
      .toUpperCase()
      .slice(0, 2);
  }

  /**
   * Get the current page name
   */
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
    return 'Inventory Manager';
  }

  /**
   * Determine if a nav item should be active
   */
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

  /**
   * Build the sidebar HTML
   */
  function buildSidebar() {
    // Create sidebar element
    const sidebar = document.createElement('aside');
    sidebar.className = 'sidebar';
    sidebar.id = 'sidebar';

    // Header
    const header = document.createElement('div');
    header.className = 'sidebar-header';
    // Build header: single logo icon (if any) + text title – never both
    const titleText = window.appName || 'Inventory Manager';
    const logoEmoji = window.appLogo || '';
    header.innerHTML = logoEmoji
      ? `<div class="sidebar-logo">${logoEmoji}</div><div class="sidebar-title">${titleText}</div>`
      : `<div class="sidebar-title">${titleText}</div>`;
    sidebar.appendChild(header);

    // Navigation
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

    // Categories divider and section
    if (categories.length > 0) {
      const divider1 = document.createElement('div');
      divider1.className = 'nav-divider';
      nav.appendChild(divider1);

      const categorySection = document.createElement('div');
      categorySection.className = 'nav-section';
      categorySection.textContent = 'Categories';
      nav.appendChild(categorySection);

      // Category links
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

    // Settings divider and link
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

    sidebar.appendChild(nav);

    // Footer with user info
    const footer = document.createElement('div');
    footer.className = 'sidebar-footer';
    const displayName = window.currentProfile?.display_name || user.email?.split('@')[0] || 'User';
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
  // 8. INJECT SIDEBAR INTO DOM
  // ============================================================================

  const sidebar = buildSidebar();
  const topbar = buildMobileTopbar();
  const overlay = buildOverlay();

  document.body.prepend(overlay);
  document.body.prepend(sidebar);
  document.body.prepend(topbar);

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
  // 9. GLOBAL FUNCTIONS
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
    try {
      const { data, error } = await window.db
        .from('table_definitions')
        .select('*')
        .eq('user_id', window.currentUser?.id)
        .order('display_name');
      if (error) throw error;
      categories = data || [];

      // Rebuild nav only
      const sidebar = document.getElementById('sidebar');
      if (sidebar) {
        const oldNav = sidebar.querySelector('.sidebar-nav');
        if (oldNav) oldNav.remove();

        const nav = document.createElement('nav');
        nav.className = 'sidebar-nav';

        // Dashboard
        const dashboardLink = document.createElement('a');
        dashboardLink.className = 'nav-item' + (isNavItemActive('index.html') ? ' active' : '');
        dashboardLink.href = 'index.html';
        dashboardLink.innerHTML = `
          <span class="nav-icon">📊</span>
          <span>Dashboard</span>
        `;
        nav.appendChild(dashboardLink);

        // Categories
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

        const header = sidebar.querySelector('.sidebar-header');
        header.parentNode.insertBefore(nav, header.nextSibling);
      }
    } catch (e) {
      console.error('Failed to refresh categories:', e);
    }
  };

  // ============================================================================
  // 10. SHOW PAGE (auth complete)
  // ============================================================================
  document.body.classList.add('loaded');
  document.body.style.opacity = '1'; // override inline style="opacity:0" (inline > class specificity)

  // ============================================================================
  // 11. DISPATCH READY EVENT
  // ============================================================================
  window.dispatchEvent(new CustomEvent('sidebar-ready'));
})();
