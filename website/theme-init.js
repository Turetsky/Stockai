/**
 * theme-init.js
 * Runs synchronously in <head> BEFORE the page renders, to apply the user's
 * saved theme colors instantly and avoid a flash of default colors (FOUC).
 *
 * Reads the `inv_theme` object from localStorage and maps each saved key to
 * its matching CSS custom property on <html>. THEME_CSS_MAP is the single
 * source of truth for theme-key → CSS-variable and is exposed on window so
 * sidebar.js (and anything else) can reuse it instead of re-declaring it.
 */
(function () {
  var THEME_CSS_MAP = {
    primary_color_start:      '--clr-start',
    primary_color_end:        '--clr-end',
    accent_color:             '--clr-accent',
    bg_color:                 '--clr-bg',
    card_color:               '--clr-card',
    card_radius:              '--card-radius',
    font_size_base:           '--font-base',
    header_text_color:        '--clr-header-text',
    text_primary_color:       '--clr-text-primary',
    text_secondary_color:     '--clr-text-secondary',
    item_card_bg:             '--clr-item-card',
    stats_bar_bg:             '--clr-stats-bar',
    low_stock_color:          '--clr-low-stock',
    btn_add_bg:               '--clr-btn-add',
    btn_edit_bg:              '--clr-btn-edit',
    btn_del_bg:               '--clr-btn-del',
    dashboard_card_min_width: '--dash-card-min',
    sidebar_bg:               '--clr-sidebar-bg',
    sidebar_header:           '--clr-sidebar-header',
    sidebar_text:             '--clr-sidebar-text',
    sidebar_title:            '--clr-sidebar-title'
  };

  window.THEME_CSS_MAP = THEME_CSS_MAP;

  /** Apply a theme object's values to the documentElement's CSS variables. */
  window.applyThemeVars = function (theme) {
    if (!theme) return;
    var root = document.documentElement;
    for (var key in THEME_CSS_MAP) {
      if (theme[key]) root.style.setProperty(THEME_CSS_MAP[key], theme[key]);
    }
  };

  try {
    window.applyThemeVars(JSON.parse(localStorage.getItem('inv_theme') || '{}'));
  } catch (e) { /* ignore malformed localStorage */ }
})();
