const SUPABASE_URL = window.SUPABASE_URL;

let allTables = [];
let currentSort = 'name_asc';
let currentFilter = '';

// Boot the dashboard once auth is ready. We use the window.authReady PROMISE
// (not the 'auth-ready' event) because this is an external script: its fetch can
// race the event, and a promise .then() still fires even if auth resolved first.
async function bootDashboard() {
    const profile = window.currentProfile;
    document.getElementById('welcomeText').textContent = `Welcome back, ${profile?.display_name || 'User'}`;
    await loadInventoryCards();
}
if (window.authReady?.then) window.authReady.then(bootDashboard);
else window.addEventListener('auth-ready', bootDashboard);

// Fetch all categories for this user from Supabase and render them as cards
async function loadInventoryCards() {
    try {
        const db = window.db;
        if (!db) {
            console.error('Database not initialized');
            renderEmptyState('Unable to load categories');
            return;
        }

        const { data, error } = await db
            .from('table_definitions')
            .select('*')
            .eq('user_id', window.currentUser?.id)
            .order('display_name');

        if (error) {
            console.error('Error fetching categories:', error);
            renderEmptyState('Error loading categories');
            return;
        }

        allTables = (data || []).map(table => ({
            ...table,
            _count: 0,
            _qty: 0
        }));

        await loadCounts();
        applySortAndFilter();
    } catch (err) {
        console.error('Failed to load inventory cards:', err);
        renderEmptyState('Error loading categories');
    }
}

// For each category, count total items and sum quantities so the card can show them
async function loadCounts() {
    const db = window.db;

    for (const table of allTables) {
        try {
            const { data, error } = await db
                .from(table.table_name)
                .select('*');

            if (!error && data) {
                table._count = data.length;

                // Add up quantity/qty field across all items in this category
                table._qty = data.reduce((sum, item) => {
                    const val = item.quantity ?? item.qty ?? 0;
                    return sum + (typeof val === 'number' ? val : 0);
                }, 0);
            }
        } catch (err) {
            console.error(`Error loading counts for ${table.table_name}:`, err);
        }
    }
}

// Filter by search text then sort, then re-render the cards
function applySortAndFilter() {
    let filtered = allTables;

    // Apply filter
    if (currentFilter) {
        const q = currentFilter.toLowerCase();
        filtered = filtered.filter(t =>
            t.display_name.toLowerCase().includes(q)
        );
    }

    // Apply sort
    const sorted = sortTables([...filtered]);
    renderCards(sorted);
}

// Return a sorted copy of the categories array based on the user's chosen sort button
function sortTables(tables) {
    const t = [...tables];

    switch (currentSort) {
        case 'name_asc':
            t.sort((a, b) => a.display_name.localeCompare(b.display_name));
            break;
        case 'name_desc':
            t.sort((a, b) => b.display_name.localeCompare(a.display_name));
            break;
        case 'count_desc':
            t.sort((a, b) => b._count - a._count);
            break;
        case 'qty_desc':
            t.sort((a, b) => b._qty - a._qty);
            break;
        default:
            t.sort((a, b) => a.display_name.localeCompare(b.display_name));
    }

    return t;
}

// Build HTML for each category card and inject it into the grid
function renderCards(tables) {
    const grid = document.getElementById('inventoryGrid');

    if (!tables || tables.length === 0) {
        renderEmptyState(currentFilter ? 'No categories found' : 'No categories yet');
        return;
    }

    grid.innerHTML = tables.map(table => `
        <div class="inventory-card" onclick="navigateToCategory('${table.table_name}')">
            <span class="card-icon">${table.icon || '📦'}</span>
            <span class="card-title">${escapeHtml(table.display_name)}</span>
            <span class="card-desc">${table.fields?.length || 0} fields</span>
            <div class="card-stats">
                <div class="stat-item">
                    <div class="stat-label">Items</div>
                    <div class="stat-value">${table._count}</div>
                </div>
                <div class="stat-item">
                    <div class="stat-label">Quantity</div>
                    <div class="stat-value">${table._qty > 0 ? table._qty : '—'}</div>
                </div>
            </div>
        </div>
    `).join('');
}

// Show a centered message when there are no categories or search has no results
function renderEmptyState(message) {
    const grid = document.getElementById('inventoryGrid');
    grid.innerHTML = `<div class="empty-state">${escapeHtml(message)}</div>`;
}

// Called on every keystroke in the search box — re-filters and re-renders cards
function filterCards(query) {
    currentFilter = query;
    applySortAndFilter();
}

// Wire up sort buttons and restore the user's last chosen sort from localStorage
document.addEventListener('DOMContentLoaded', () => {
    const sortButtons = document.querySelectorAll('.sort-btn');
    sortButtons.forEach(btn => {
        btn.addEventListener('click', (e) => {
            sortButtons.forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            currentSort = btn.dataset.sort;
            localStorage.setItem('dashSort', currentSort);
            applySortAndFilter();
        });
    });

    // Load saved sort preference
    const savedSort = localStorage.getItem('dashSort');
    if (savedSort) {
        currentSort = savedSort;
        const btn = document.querySelector(`[data-sort="${savedSort}"]`);
        if (btn) {
            document.querySelectorAll('.sort-btn').forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
        }
    }
});

// Navigate to inventory.html passing the table name so it knows which category to load
function navigateToCategory(tableName) {
    window.location.href = 'inventory.html?table=' + encodeURIComponent(tableName);
}

// Show/hide the "Create New Category" popup modal
function showAddCategoryModal() {
    document.getElementById('addCatModal').style.display = 'flex';
    document.getElementById('catError').style.display = 'none';
}

function hideAddCategoryModal() {
    document.getElementById('addCatModal').style.display = 'none';
    document.getElementById('addCatForm').reset();
    document.getElementById('catIcon').value = '📦';
    document.getElementById('catError').style.display = 'none';

    // Reset fields to default
    const fieldsList = document.getElementById('fieldsList');
    fieldsList.innerHTML = `
        <div class="field-row">
            <input type="text" value="Name" class="field-name" required>
            <select class="field-type"><option value="text">Text</option><option value="number">Number</option><option value="date">Date</option></select>
            <button type="button" class="remove-field-btn" onclick="this.closest('.field-row').remove()">✕</button>
        </div>
        <div class="field-row">
            <input type="text" value="Quantity" class="field-name" required>
            <select class="field-type"><option value="text">Text</option><option value="number" selected>Number</option><option value="date">Date</option></select>
            <button type="button" class="remove-field-btn" onclick="this.closest('.field-row').remove()">✕</button>
        </div>
    `;
}

// Append a blank field row when user clicks "+ Add Field" in the category creation form
function addFieldRow() {
    const fieldsList = document.getElementById('fieldsList');
    const newRow = document.createElement('div');
    newRow.className = 'field-row';
    newRow.innerHTML = `
        <input type="text" value="" class="field-name" placeholder="Field name" required>
        <select class="field-type"><option value="text">Text</option><option value="number">Number</option><option value="date">Date</option></select>
        <button type="button" class="remove-field-btn" onclick="this.closest('.field-row').remove()">✕</button>
    `;
    fieldsList.appendChild(newRow);
}

// Submit the new category form — calls the Edge Function which creates the DB table
async function createCategory(event) {
    event.preventDefault();

    const catName = document.getElementById('catName').value.trim();
    const catIcon = document.getElementById('catIcon').value.trim() || '📦';
    const errorEl = document.getElementById('catError');

    if (!catName) {
        errorEl.textContent = 'Category name is required';
        errorEl.style.display = 'block';
        return;
    }

    // Collect fields
    const fieldRows = document.querySelectorAll('.field-row');
    const fieldsArray = [];
    for (const row of fieldRows) {
        const name = row.querySelector('.field-name').value.trim();
        const type = row.querySelector('.field-type').value;
        if (name) {
            fieldsArray.push({ name, type });
        }
    }

    if (fieldsArray.length === 0) {
        errorEl.textContent = 'At least one field is required';
        errorEl.style.display = 'block';
        return;
    }

    // Build a unique table name: prefix with user id slice so two users can have same category name
    const userId = window.currentSession?.user?.id || 'unknown';
    const sanitized = catName
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, '_')
        .replace(/^_|_$/g, '');
    const tableName = `p_${userId.substring(0, 8)}_${sanitized}`;

    // Disable the button while the request is in-flight so user can't double-submit
    const createBtn = document.getElementById('createCatBtn');
    const originalText = createBtn.textContent;
    createBtn.disabled = true;
    createBtn.textContent = 'Creating…';

    try {
        // Always refresh the JWT — a cached token may be expired and the Edge Function will reject it
        const { data: sessionData } = await window.db.auth.getSession();
        const token = sessionData?.session?.access_token || window.currentSession?.access_token;
        if (!token) throw new Error('Not authenticated');
        const response = await fetch(SUPABASE_URL + '/functions/v1/smart-api', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer ' + token
            },
            body: JSON.stringify({
                tool_call: {
                    name: 'create_category',
                    input: {
                        table_name: tableName,
                        display_name: catName,
                        icon: catIcon,
                        fields: fieldsArray
                    }
                }
            })
        });

        const result = await response.json();

        if (!response.ok || result.error) {
            throw new Error(result.error?.message || 'Failed to create category');
        }

        // Category created — close the modal, refresh cards, and tell the sidebar to update its nav list
        hideAddCategoryModal();
        await loadInventoryCards();
        window.dispatchEvent(new CustomEvent('data-changed'));

    } catch (err) {
        console.error('Error creating category:', err);
        errorEl.textContent = err.message || 'Failed to create category. Please try again.';
        errorEl.style.display = 'block';
    } finally {
        createBtn.disabled = false;
        createBtn.textContent = originalText;
    }
}

// Sanitize user-supplied text before inserting into innerHTML to prevent XSS
function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

// Download every category's items as separate CSV files (one file per category)
async function exportAllCategories() {
    const btn = document.getElementById('exportAllBtn');
    btn.disabled = true;
    btn.textContent = '⏳ Exporting…';

    try {
        const db = window.db;

        // Get all categories for this user
        const { data: categories, error: catErr } = await db
            .from('table_definitions')
            .select('*')
            .eq('user_id', window.currentUser?.id)
            .order('display_name');
        if (catErr) throw catErr;
        if (!categories || categories.length === 0) {
            alert('No categories found to export.');
            return;
        }

        const escape = (val) => {
            const str = val == null ? '' : String(val);
            if (str.includes(',') || str.includes('"') || str.includes('\n')) {
                return '"' + str.replace(/"/g, '""') + '"';
            }
            return str;
        };

        let exported = 0;

        for (const cat of categories) {
            // Get field definitions for this table
            const { data: fields } = await db
                .from('field_definitions')
                .select('*')
                .eq('table_name', cat.table_name)
                .order('sort_order');

            if (!fields || fields.length === 0) continue;

            // Get all items for this table
            const { data: items, error: itemErr } = await db
                .from(cat.table_name)
                .select('*')
                .order('created_at', { ascending: false });

            if (itemErr) { console.warn('Skipping', cat.table_name, itemErr.message); continue; }

            const fieldNames   = fields.map(f => f.field_name);
            const displayNames = fields.map(f => f.display_name);

            const csvRows = [
                '#fields:' + fieldNames.join(','),            // hidden mapping row so re-import knows which column is which
                displayNames.map(escape).join(','),           // human-readable column headers
                ...(items || []).map(item =>
                    fieldNames.map(n => escape(item[n])).join(',')
                ),
            ];

            const csv  = '\uFEFF' + csvRows.join('\n');       // BOM prefix so Excel/Sheets opens it as UTF-8
            const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
            const url  = URL.createObjectURL(blob);
            const a    = document.createElement('a');
            a.href     = url;
            a.download = `${cat.display_name.replace(/\s+/g, '_')}_${new Date().toISOString().slice(0,10)}.csv`;
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            URL.revokeObjectURL(url);
            exported++;

            // Brief pause between files — browsers block rapid simultaneous downloads
            await new Promise(r => setTimeout(r, 400));
        }

        btn.textContent = `✅ Exported ${exported}`;
        setTimeout(() => { btn.textContent = '⬇ Export All'; btn.disabled = false; }, 2500);
        return;
    } catch (err) {
        alert('Export error: ' + err.message);
    }

    btn.textContent = '⬇ Export All';
    btn.disabled = false;
}

// Expose reload function and listen for the app-wide data-changed event
window.loadInventoryCards = loadInventoryCards;
window.addEventListener('data-changed', loadInventoryCards);

// ── AI command hero wiring ──
// Routes the dashboard's command bar + suggestion chips into the AI assistant
// (window.askStockAI is exposed by ai-assistant-v4.js).
(function wireAIHero() {
    const form = document.getElementById('aiDashForm');
    if (form) {
        form.addEventListener('submit', (e) => {
            e.preventDefault();
            const inp = document.getElementById('aiDashInput');
            const v = (inp?.value || '').trim();
            if (!v) { window.askStockAI?.(''); return; }
            window.askStockAI?.(v);
            if (inp) inp.value = '';
        });
    }
    // chips that send a command immediately
    document.querySelectorAll('.ai-hero-chips [data-ai]').forEach((btn) =>
        btn.addEventListener('click', () => window.askStockAI?.(btn.getAttribute('data-ai')))
    );
    // chips that just open the chat and pre-fill (user finishes the sentence)
    document.querySelectorAll('.ai-hero-chips [data-ai-prefill]').forEach((btn) =>
        btn.addEventListener('click', () => {
            window.askStockAI?.('');
            const chatInput = document.getElementById('ai-chat-input');
            if (chatInput) { chatInput.value = btn.getAttribute('data-ai-prefill'); chatInput.focus(); }
        })
    );
})();
