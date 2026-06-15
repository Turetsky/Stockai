const SUPABASE_URL = window.SUPABASE_URL;

// ── Tab switching ──
document.querySelectorAll('.tab-btn').forEach(btn => {
    btn.addEventListener('click', () => {
        document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
        document.querySelectorAll('.tab-panel').forEach(p => p.classList.remove('active'));
        btn.classList.add('active');
        document.getElementById('tab-' + btn.dataset.tab).classList.add('active');
    });
});

// ── Theme presets ──
const PRESETS = [
    { name: 'Midnight Violet',   start: '#8b7bff', end: '#667eea', accent: '#8b7bff', bg: '#07070e', card: '#0d0d18', text: '#ecedf6',
      sidebarBg: '#0d0d18', sidebarHeader: '#07070e', sidebarText: '#9a9bb4', sidebarTitle: '#ecedf6' },
    { name: 'Default Purple',    start: '#667eea', end: '#764ba2', accent: '#667eea', bg: '#f0f1f8', card: '#ffffff', text: '#1a1a1a',
      sidebarBg: '#1e293b', sidebarHeader: '#0f172a', sidebarText: '#94a3b8', sidebarTitle: '#f1f5f9' },
    { name: 'Dark Mode',         start: '#1e293b', end: '#334155', accent: '#60a5fa', bg: '#0f172a', card: '#1e293b', text: '#f1f5f9',
      sidebarBg: '#0f172a', sidebarHeader: '#020617', sidebarText: '#94a3b8', sidebarTitle: '#e2e8f0' },
    { name: 'Professional Blue', start: '#1e3a8a', end: '#1d4ed8', accent: '#3b82f6', bg: '#eff6ff', card: '#ffffff', text: '#1e3a8a',
      sidebarBg: '#1e3a8a', sidebarHeader: '#172554', sidebarText: '#93c5fd', sidebarTitle: '#eff6ff' },
    { name: 'Forest Green',      start: '#166534', end: '#15803d', accent: '#22c55e', bg: '#f0fdf4', card: '#ffffff', text: '#14532d',
      sidebarBg: '#14532d', sidebarHeader: '#052e16', sidebarText: '#86efac', sidebarTitle: '#f0fdf4' },
    { name: 'Sunset Orange',     start: '#c2410c', end: '#ea580c', accent: '#f97316', bg: '#fff7ed', card: '#ffffff', text: '#431407',
      sidebarBg: '#7c2d12', sidebarHeader: '#431407', sidebarText: '#fdba74', sidebarTitle: '#fff7ed' },
    { name: 'Rose Pink',         start: '#be123c', end: '#e11d48', accent: '#f43f5e', bg: '#fff1f2', card: '#ffffff', text: '#4c0519',
      sidebarBg: '#881337', sidebarHeader: '#4c0519', sidebarText: '#fda4af', sidebarTitle: '#fff1f2' },
];

const COLOR_FIELDS = [
    { key: 'primary_color_start',  label: 'Header Gradient Start', css: '--clr-start',           def: '#667eea' },
    { key: 'primary_color_end',    label: 'Header Gradient End',   css: '--clr-end',             def: '#764ba2' },
    { key: 'header_text_color',    label: 'Header Text Color',     css: '--clr-header-text',     def: '#ffffff' },
    { key: 'accent_color',         label: 'Accent / Buttons',      css: '--clr-accent',          def: '#667eea' },
    { key: 'bg_color',             label: 'Page Background',       css: '--clr-bg',              def: '#f5f5f5' },
    { key: 'card_color',           label: 'Card Background',       css: '--clr-card',            def: '#ffffff' },
    { key: 'text_primary_color',   label: 'Primary Text',          css: '--clr-text-primary',    def: '#1a1a1a' },
    { key: 'text_secondary_color', label: 'Secondary Text',        css: '--clr-text-secondary',  def: '#666666' },
    { key: 'item_card_bg',         label: 'Item Card Background',  css: '--clr-item-card',       def: '#ffffff' },
    { key: 'stats_bar_bg',         label: 'Stats Bar Background',  css: '--clr-stats-bar',       def: '#ffffff' },
    { key: 'low_stock_color',      label: 'Low Stock Warning',     css: '--clr-low-stock',       def: '#ef4444' },
    { key: 'btn_add_bg',           label: 'Add Button',            css: '--clr-btn-add',         def: '#22c55e' },
    { key: 'btn_edit_bg',          label: 'Edit Button',           css: '--clr-btn-edit',        def: '#fbbf24' },
    { key: 'btn_del_bg',           label: 'Delete Button',         css: '--clr-btn-del',         def: '#ef4444' },
    { key: 'sidebar_bg',           label: 'Sidebar Background',    css: '--clr-sidebar-bg',      def: '#1e293b' },
    { key: 'sidebar_header',       label: 'Sidebar Header/Footer', css: '--clr-sidebar-header',  def: '#0f172a' },
    { key: 'sidebar_text',         label: 'Sidebar Nav Text',      css: '--clr-sidebar-text',    def: '#94a3b8' },
    { key: 'sidebar_title',        label: 'Sidebar Title & Names', css: '--clr-sidebar-title',   def: '#f1f5f9' },
];

let currentTheme = {};

// CSS var lookup map for all theme keys
const CSS_MAP = Object.fromEntries(COLOR_FIELDS.map(f => [f.key, f.css]));

function loadCurrentTheme() {
    try { currentTheme = JSON.parse(localStorage.getItem('inv_theme') || '{}'); }
    catch(e) { currentTheme = {}; }
}

// Pull theme from Supabase ui_settings and merge (AI-set values win over localStorage)
async function syncThemeFromSupabase() {
    try {
        const db = window.db;
        const userId = window.currentUser?.id;
        if (!db || !userId) return;
        const { data } = await db.from('ui_settings').select('key,value').eq('user_id', userId);
        if (!data || !data.length) return;

        data.forEach(row => { currentTheme[row.key] = row.value; });

        // Apply CSS vars
        const root = document.documentElement;
        data.forEach(row => {
            if (CSS_MAP[row.key]) root.style.setProperty(CSS_MAP[row.key], row.value);
        });

        // Persist merged result to localStorage
        localStorage.setItem('inv_theme', JSON.stringify(currentTheme));
        buildColorPickers();
    } catch(e) { console.warn('Supabase theme sync failed:', e.message); }
}

function buildPresetsGrid() {
    const grid = document.getElementById('presetsGrid');
    grid.innerHTML = PRESETS.map((p, i) => `
        <div class="preset-card" onclick="applyPreset(${i})">
            <div class="preset-swatch" style="background:linear-gradient(135deg, ${p.start}, ${p.end})"></div>
            <div class="preset-name">${p.name}</div>
        </div>
    `).join('');
}

function buildColorPickers() {
    const container = document.getElementById('colorPickers');
    container.innerHTML = COLOR_FIELDS.map(f => `
        <div class="color-row">
            <label>${f.label}</label>
            <input type="color" id="clr_${f.key}" value="${currentTheme[f.key] || f.def}" onchange="previewColor('${f.key}', '${f.css}', this.value)">
        </div>
    `).join('');
}

function previewColor(key, cssVar, value) {
    document.documentElement.style.setProperty(cssVar, value);
    currentTheme[key] = value;
    saveTheme();
}

function applyPreset(index) {
    const p = PRESETS[index];
    Object.assign(currentTheme, {
        primary_color_start: p.start, primary_color_end: p.end,
        accent_color: p.accent, bg_color: p.bg,
        card_color: p.card, text_primary_color: p.text,
        sidebar_bg: p.sidebarBg, sidebar_header: p.sidebarHeader,
        sidebar_text: p.sidebarText, sidebar_title: p.sidebarTitle
    });
    const root = document.documentElement;
    root.style.setProperty('--clr-start', p.start);
    root.style.setProperty('--clr-end', p.end);
    root.style.setProperty('--clr-accent', p.accent);
    root.style.setProperty('--clr-bg', p.bg);
    root.style.setProperty('--clr-card', p.card);
    root.style.setProperty('--clr-text-primary', p.text);
    // Apply sidebar colors so the sidebar updates live
    root.style.setProperty('--clr-sidebar-bg',     p.sidebarBg);
    root.style.setProperty('--clr-sidebar-header', p.sidebarHeader);
    root.style.setProperty('--clr-sidebar-text',   p.sidebarText);
    root.style.setProperty('--clr-sidebar-title',  p.sidebarTitle);
    buildColorPickers();
    saveTheme();
}

async function saveTheme() {
    // 1. Save to localStorage (instant apply on page load)
    localStorage.setItem('inv_theme', JSON.stringify(currentTheme));

    // 2. Sync to Supabase so AI reads/writes stay consistent
    try {
        const db = window.db;
        const userId = window.currentUser?.id;
        if (db && userId) {
            for (const [key, value] of Object.entries(currentTheme)) {
                await db.from('ui_settings')
                    .upsert({ key, value, user_id: userId, updated_at: new Date().toISOString() },
                            { onConflict: 'key,user_id' });
            }
        }
    } catch(e) { console.warn('Could not sync theme to Supabase:', e.message); }

    showMsg('themeMsg', 'Theme saved! Changes apply instantly across all pages.', 'success');
}

async function resetTheme() {
    currentTheme = {};
    localStorage.removeItem('inv_theme');

    const root = document.documentElement;
    COLOR_FIELDS.forEach(f => root.style.setProperty(f.css, f.def));

    // Clear from Supabase
    try {
        const db = window.db;
        const userId = window.currentUser?.id;
        if (db && userId) {
            const keys = COLOR_FIELDS.map(f => f.key);
            for (const key of keys) {
                await db.from('ui_settings').delete().eq('key', key).eq('user_id', userId);
            }
        }
    } catch(e) { console.warn('Could not clear theme from Supabase:', e.message); }

    buildColorPickers();
    showMsg('themeMsg', 'Theme reset to defaults.', 'success');
}

// ── Profile ──
function loadProfile() {
    const profile = window.currentProfile;
    const user = window.currentUser;
    if (profile) {
        document.getElementById('profileName').value = profile.display_name || '';
    }
    if (user) {
        document.getElementById('profileEmail').value = user.email || '';
    }
}

async function saveProfile() {
    const name = document.getElementById('profileName').value.trim();
    if (!name) {
        showMsg('profileMsg', 'Name cannot be empty.', 'error');
        return;
    }

    const btn = document.getElementById('saveProfileBtn');
    btn.disabled = true;
    btn.textContent = 'Saving...';

    try {
        const { error } = await window.db
            .from('profiles')
            .update({ display_name: name })
            .eq('id', window.currentUser.id);

        if (error) throw error;

        window.currentProfile.display_name = name;
        showMsg('profileMsg', 'Profile updated!', 'success');
    } catch(err) {
        showMsg('profileMsg', err.message, 'error');
    } finally {
        btn.disabled = false;
        btn.textContent = 'Save Changes';
    }
}

async function changePassword() {
    const newPw = document.getElementById('newPassword').value;
    const confirmPw = document.getElementById('confirmPassword').value;

    if (!newPw || newPw.length < 6) {
        showMsg('passwordMsg', 'Password must be at least 6 characters.', 'error');
        return;
    }
    if (newPw !== confirmPw) {
        showMsg('passwordMsg', 'Passwords do not match.', 'error');
        return;
    }

    try {
        const { error } = await window.db.auth.updateUser({ password: newPw });
        if (error) throw error;
        document.getElementById('newPassword').value = '';
        document.getElementById('confirmPassword').value = '';
        showMsg('passwordMsg', 'Password updated successfully!', 'success');
    } catch(err) {
        showMsg('passwordMsg', err.message, 'error');
    }
}

// ── Categories ──
async function loadCategories() {
    try {
        const { data, error } = await window.db
            .from('table_definitions')
            .select('*')
            .eq('user_id', window.currentUser?.id)
            .order('display_name');

        if (error) throw error;

        const container = document.getElementById('categoriesList');
        if (!data || data.length === 0) {
            container.innerHTML = '<div class="empty-msg">No categories yet. Create one from the Dashboard.</div>';
            // Clear import select
            const sel = document.getElementById('importTableSelect');
            sel.innerHTML = '<option value="">Select category…</option>';
            return;
        }

        container.innerHTML = data.map(cat => `
            <div class="cat-item" id="cat-${cat.table_name}">
                <span class="cat-icon">${cat.icon || '📦'}</span>
                <div class="cat-info">
                    <div class="cat-name">${escapeHtml(cat.display_name)}</div>
                    <div class="cat-table">${cat.table_name}</div>
                </div>
                <div class="cat-actions">
                    <button class="cat-edit" onclick="window.location.href='inventory.html?table=${encodeURIComponent(cat.table_name)}'">Open</button>
                    <button class="cat-export" onclick="exportCategory('${cat.table_name}', '${escapeHtml(cat.display_name)}')">Export</button>
                    <button class="cat-del" onclick="deleteCategory('${cat.table_name}', '${escapeHtml(cat.display_name)}')">Delete</button>
                </div>
            </div>
        `).join('');

        // Populate import dropdown
        const sel = document.getElementById('importTableSelect');
        sel.innerHTML = '<option value="">Select category…</option>' +
            data.map(cat => `<option value="${cat.table_name}">${escapeHtml(cat.display_name)}</option>`).join('');
    } catch(err) {
        console.error('Error loading categories:', err);
    }
}

// ── Export CSV ──
async function exportCategory(tableName, displayName) {
    try {
        const userId = window.currentUser?.id;

        // Get field definitions (column order)
        const { data: fields, error: fErr } = await window.db
            .from('field_definitions')
            .select('field_name, display_name')
            .eq('table_name', tableName)
            .eq('user_id', userId)
            .order('sort_order');
        if (fErr) throw fErr;
        if (!fields || fields.length === 0) {
            alert('No fields found for this category.');
            return;
        }

        // Get all items
        const { data: items, error: iErr } = await window.db
            .from(tableName)
            .select('*')
            .eq('user_id', userId);
        if (iErr) throw iErr;

        // Build CSV
        const csvQuote = v => {
            const s = v == null ? '' : String(v);
            return s.includes(',') || s.includes('\n') || s.includes('"')
                ? '"' + s.replace(/"/g, '""') + '"' : s;
        };
        const header = fields.map(f => csvQuote(f.display_name)).join(',');
        const rows = (items || []).map(item =>
            fields.map(f => csvQuote(item[f.field_name])).join(',')
        );
        const csv = [header, ...rows].join('\n');

        // Trigger download
        const blob = new Blob([csv], { type: 'text/csv' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = displayName.replace(/[^a-z0-9]/gi, '_') + '_export.csv';
        a.click();
        URL.revokeObjectURL(url);
    } catch(err) {
        alert('Export failed: ' + err.message);
    }
}

// ── Import CSV ──
function parseCSVLine(line) {
    const result = [];
    let current = '', inQuotes = false;
    for (let i = 0; i < line.length; i++) {
        if (line[i] === '"') {
            if (inQuotes && line[i + 1] === '"') { current += '"'; i++; }
            else { inQuotes = !inQuotes; }
        } else if (line[i] === ',' && !inQuotes) {
            result.push(current.trim());
            current = '';
        } else {
            current += line[i];
        }
    }
    result.push(current.trim());
    return result;
}

async function importCategoryData() {
    const tableName = document.getElementById('importTableSelect').value;
    const fileInput = document.getElementById('importFileInput');
    if (!tableName) { showMsg('dataMsg', 'Select a category first.', 'error'); return; }
    if (!fileInput.files[0]) { showMsg('dataMsg', 'Select a CSV file.', 'error'); return; }

    try {
        const text = await fileInput.files[0].text();
        const lines = text.trim().split('\n').filter(l => l.trim());
        if (lines.length < 2) {
            showMsg('dataMsg', 'CSV must have a header row and at least one data row.', 'error');
            return;
        }

        const headers = parseCSVLine(lines[0]);
        const userId = window.currentUser?.id;

        // Get field definitions to map display_name → field_name
        const { data: fields } = await window.db
            .from('field_definitions')
            .select('field_name, display_name')
            .eq('table_name', tableName)
            .eq('user_id', userId);

        const fieldMap = {};
        (fields || []).forEach(f => {
            fieldMap[f.display_name.toLowerCase()] = f.field_name;
        });

        // Parse data rows
        const rows = [];
        for (let i = 1; i < lines.length; i++) {
            const values = parseCSVLine(lines[i]);
            if (values.every(v => !v)) continue;
            const row = { user_id: userId };
            headers.forEach((h, idx) => {
                const fn = fieldMap[h.toLowerCase()];
                if (fn) row[fn] = values[idx] || null;
            });
            rows.push(row);
        }

        if (rows.length === 0) {
            showMsg('dataMsg', 'No valid rows to import.', 'error');
            return;
        }

        const { error } = await window.db.from(tableName).insert(rows);
        if (error) throw error;

        fileInput.value = '';
        showMsg('dataMsg', `Imported ${rows.length} item${rows.length === 1 ? '' : 's'} successfully!`, 'success');
    } catch(err) {
        showMsg('dataMsg', 'Import failed: ' + err.message, 'error');
    }
}

async function deleteCategory(tableName, displayName) {
    if (!confirm(`Are you sure you want to delete "${displayName}" and ALL its items? This cannot be undone.`)) return;

    try {
        const session = window.currentSession;
        const response = await fetch(SUPABASE_URL + '/functions/v1/smart-api', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer ' + session.access_token
            },
            body: JSON.stringify({
                tool_call: {
                    name: 'delete_category',
                    input: { table_name: tableName }
                }
            })
        });

        const result = await response.json();
        if (!response.ok || result.error) throw new Error(result.error?.message || 'Delete failed');

        const el = document.getElementById('cat-' + tableName);
        if (el) el.remove();

        window.dispatchEvent(new CustomEvent('data-changed'));
    } catch(err) {
        alert('Error deleting category: ' + err.message);
    }
}

// ── Helpers ──
function showMsg(id, text, type) {
    const el = document.getElementById(id);
    el.textContent = text;
    el.className = 'msg ' + type;
    setTimeout(() => { el.className = 'msg'; }, 4000);
}

function escapeHtml(text) {
    const d = document.createElement('div');
    d.textContent = text;
    return d.innerHTML;
}

// ── Init ──
// Use the window.authReady PROMISE (not the 'auth-ready' event): as an external
// script our fetch can race the event, but a promise .then() fires regardless.
async function initSettings() {
    loadProfile();
    loadCurrentTheme();
    buildPresetsGrid();
    buildColorPickers();
    await syncThemeFromSupabase(); // merge AI-set values from Supabase
    loadCategories(); // populates Data tab + import dropdown
    document.body.classList.add('loaded');
}
if (window.authReady?.then) window.authReady.then(initSettings);
else window.addEventListener('auth-ready', initSettings);
