const { useState, useEffect } = React;

function InventoryApp() {
    // ============================================================================
    // 1. STATE
    // ============================================================================
    const [tableName,      setTableName]      = useState('');
    const [tableInfo,      setTableInfo]      = useState(null);
    const [fields,         setFields]         = useState([]);
    const [items,          setItems]          = useState([]);
    const [loading,        setLoading]        = useState(true);
    const [editingId,      setEditingId]      = useState(null);
    const [showAddForm,    setShowAddForm]    = useState(false);
    const [searchTerm,     setSearchTerm]     = useState('');
    const [formData,       setFormData]       = useState({});
    const [lowThreshold,   setLowThreshold]   = useState(10);
    const [sortField,      setSortField]      = useState('');
    const [sortDir,        setSortDir]        = useState('desc');
    const [statsPosition,  setStatsPosition]  = useState('bottom');
    const [ready,          setReady]          = useState(false);
    const [importLoading,  setImportLoading]  = useState(false);

    // ============================================================================
    // 2. WAIT FOR AUTH
    // auth.js fires `auth-ready` once the user session is confirmed.
    // We flip `ready` to true so the init effect below can run safely.
    // ============================================================================
    useEffect(() => {
        const handler = () => setReady(true);
        window.addEventListener('auth-ready', handler);
        // Safety: sidebar may have fired before this component mounted.
        if (window.currentSession) setReady(true);
        return () => window.removeEventListener('auth-ready', handler);
    }, []);

    // ============================================================================
    // 3. INIT — READ URL, LOAD THEME, RESTORE SORT PREF
    // Runs once auth is ready. Reads ?table= from the URL, hydrates theme
    // (localStorage first, then fresh from Supabase), and restores the user's
    // last-used sort for this category.
    // ============================================================================
    useEffect(() => {
        if (!ready) return;
        // Read which category table to show from the URL query param
        const table = new URLSearchParams(window.location.search).get('table');
        if (!table) { window.location.href = 'index.html'; return; }
        setTableName(table);

        // Load theme from localStorage first (instant, prevents FOUC)
        let theme = {};
        try {
            theme = JSON.parse(localStorage.getItem('inv_theme') || '{}');
            if (theme.low_stock_threshold) setLowThreshold(Number(theme.low_stock_threshold));
            if (theme.stats_position) setStatsPosition(theme.stats_position);
            const densityPad = { compact: '10px 14px', normal: '18px 20px', large: '26px 28px' };
            if (theme.item_card_density) document.documentElement.style.setProperty('--item-pad', densityPad[theme.item_card_density] || densityPad.normal);
        } catch(e) {}

        // Then pull fresh settings from Supabase in case AI changed them since last visit
        (async () => { try {
            const db = window.db;
            const userId = window.currentUser?.id;
            if (db && userId) {
                const { data: uiRows } = await db.from('ui_settings').select('key,value').eq('user_id', userId);
                if (uiRows && uiRows.length) {
                    const cssMap = {
                        primary_color_start:'--clr-start', primary_color_end:'--clr-end',
                        header_text_color:'--clr-header-text', accent_color:'--clr-accent',
                        bg_color:'--clr-bg', card_color:'--clr-card', card_radius:'--card-radius',
                        font_size_base:'--font-base', text_primary_color:'--clr-text-primary',
                        text_secondary_color:'--clr-text-secondary', item_card_bg:'--clr-item-card',
                        stats_bar_bg:'--clr-stats-bar', low_stock_color:'--clr-low-stock',
                        btn_add_bg:'--clr-btn-add', btn_edit_bg:'--clr-btn-edit', btn_del_bg:'--clr-btn-del',
                    };
                    const root = document.documentElement;
                    const merged = { ...theme };
                    uiRows.forEach(row => {
                        merged[row.key] = row.value;
                        if (cssMap[row.key]) root.style.setProperty(cssMap[row.key], row.value);
                    });
                    if (merged.low_stock_threshold) setLowThreshold(Number(merged.low_stock_threshold));
                    if (merged.stats_position) setStatsPosition(merged.stats_position);
                    const densityPad = { compact: '10px 14px', normal: '18px 20px', large: '26px 28px' };
                    if (merged.item_card_density) root.style.setProperty('--item-pad', densityPad[merged.item_card_density] || densityPad.normal);
                    localStorage.setItem('inv_theme', JSON.stringify(merged));
                }
            }
        } catch(e) { console.warn('Theme sync failed:', e.message); } })();

        // Restore the sort field/direction the user last used for this specific category
        const savedSort = localStorage.getItem(`sort_${table}`);
        if (savedSort) {
            try {
                const { field, dir } = JSON.parse(savedSort);
                setSortField(field || '');
                setSortDir(dir || 'desc');
            } catch {}
        }

        loadTableStructure(table);
    }, [ready]);

    // ============================================================================
    // 4. FETCH DATA — runs after we know the table + its fields
    // ============================================================================
    // Load items once the table structure is ready.
    useEffect(() => {
        if (tableName && fields.length > 0) fetchItems();
    }, [tableName, fields]);

    // Expose fetchItems globally so the AI assistant can trigger a reload
    // after it creates/updates/deletes items via the Edge Function.
    useEffect(() => {
        window.fetchItemsGlobal = fetchItems;
        window.addEventListener('data-changed', fetchItems);
        return () => window.removeEventListener('data-changed', fetchItems);
    }, [tableName, fields]);

    // ============================================================================
    // 5. LOAD TABLE STRUCTURE
    // Pulls the category metadata (display name, icon) and its field definitions
    // from Supabase, then seeds an empty form matching those fields.
    // ============================================================================
    const loadTableStructure = async (table) => {
        try {
            const db = window.db;

            // Fetch table definition directly (avoids edge-function CORS issues)
            const { data: tdData, error: tdErr } = await db
                .from('table_definitions')
                .select('*')
                .eq('table_name', table)
                .single();
            if (tdErr) throw tdErr;

            // Fetch field definitions
            const { data: fdData, error: fdErr } = await db
                .from('field_definitions')
                .select('*')
                .eq('table_name', table)
                .order('sort_order');
            if (fdErr) throw fdErr;

            setTableInfo(tdData);
            setFields(fdData || []);
            document.title = `${tdData.display_name} - StockAI`;
            const init = {};
            (fdData || []).forEach(f => { init[f.field_name] = f.field_type === 'number' ? 0 : ''; });
            setFormData(init);
        } catch (err) {
            console.error('Error loading table:', err.message);
        }
    };

    // ============================================================================
    // 6. FETCH ITEMS
    // ============================================================================
    // Fetch all items from this category's table, newest first.
    const fetchItems = async () => {
        setLoading(true);
        try {
            const db = window.db;
            const { data, error } = await db.from(tableName).select('*').order('created_at', { ascending: false });
            if (error) throw error;
            setItems(data || []);
        } catch (err) { console.error('Error loading items:', err.message); }
        setLoading(false);
    };

    // ============================================================================
    // 7. SORT HELPERS
    // ============================================================================
    // Persist the user's sort choice per-category so it survives page refreshes.
    const saveSortPref = (field, dir) => {
        if (tableName) localStorage.setItem(`sort_${tableName}`, JSON.stringify({ field, dir }));
    };
    const handleSortField = (newField) => {
        setSortField(newField);
        saveSortPref(newField, sortDir);
    };
    const handleSortDir = () => {
        const newDir = sortDir === 'asc' ? 'desc' : 'asc';
        setSortDir(newDir);
        saveSortPref(sortField, newDir);
    };

    // ============================================================================
    // 8. FORM HELPER + SAVE / EDIT / DELETE
    // ============================================================================
    // Return a fresh, empty form matching the current field types (0 for numbers, '' for text).
    const blankForm = () => {
        const init = {};
        fields.forEach(f => { init[f.field_name] = f.field_type === 'number' ? 0 : ''; });
        return init;
    };

    // Save the form — UPDATE if editingId is set, otherwise INSERT a new row.
    // We stamp user_id on INSERT so Supabase's row-level security accepts it.
    const handleSubmit = async (e) => {
        e.preventDefault();
        try {
            const db = window.db;
            if (editingId) {
                const { error } = await db.from(tableName).update(formData).eq('id', editingId);
                if (error) throw error;
            } else {
                const userId = window.currentUser?.id;
                const insertData = userId ? { ...formData, user_id: userId } : formData;
                const { error } = await db.from(tableName).insert([insertData]);
                if (error) throw error;
            }
            await fetchItems();
            setEditingId(null); setShowAddForm(false); setFormData(blankForm());
        } catch (err) { alert('Error saving: ' + err.message); }
    };

    // Pre-fill the form with an existing item's values and scroll up so it's visible.
    const startEdit = (item) => {
        const d = {};
        fields.forEach(f => { d[f.field_name] = item[f.field_name] ?? (f.field_type === 'number' ? 0 : ''); });
        setFormData(d); setEditingId(item.id); setShowAddForm(false);
        window.scrollTo({ top: 0, behavior: 'smooth' });
    };

    // Confirm, delete from Supabase, then drop it from the on-screen list.
    const handleDelete = async (id) => {
        if (!confirm('Delete this item?')) return;
        const db = window.db;
        const { error } = await db.from(tableName).delete().eq('id', id);
        if (error) { alert('Delete error: ' + error.message); return; }
        setItems(items.filter(i => i.id !== id));
    };

    // Reset and close the add/edit form.
    const cancelForm = () => { setEditingId(null); setShowAddForm(false); setFormData(blankForm()); };

    // ============================================================================
    // 9. CSV — PARSE / EXPORT / IMPORT
    // ============================================================================
    // Parse raw CSV text into a 2D array of cells.
    // Handles quoted fields that contain commas (e.g. "Smith, John").
    const parseCSV = (text) => {
        const rows = [];
        // Normalize line endings
        const lines = text.replace(/\r\n/g, '\n').replace(/\r/g, '\n').split('\n');
        for (const line of lines) {
            if (!line.trim()) continue;
            const cells = [];
            let cur = '';
            let inQuotes = false;
            for (let i = 0; i < line.length; i++) {
                const ch = line[i];
                if (ch === '"') {
                    if (inQuotes && line[i + 1] === '"') { cur += '"'; i++; }
                    else { inQuotes = !inQuotes; }
                } else if (ch === ',' && !inQuotes) {
                    cells.push(cur); cur = '';
                } else {
                    cur += ch;
                }
            }
            cells.push(cur);
            rows.push(cells);
        }
        return rows;
    };

    // Build a CSV string from current items and trigger a browser download.
    // Format: row 0 = hidden "#fields:" mapping row (for lossless re-import),
    //         row 1 = human display headers,
    //         row 2+ = data rows in the same column order.
    const exportCSV = () => {
        if (!fields.length) return;
        if (!items.length) { alert('No items to export.'); return; }

        // Use internal field_names (not display names) as the data key order so re-import can map columns reliably
        const fieldNames = fields.map(f => f.field_name);
        const displayNames = fields.map(f => f.display_name);

        const escape = (val) => {
            const str = val == null ? '' : String(val);
            if (str.includes(',') || str.includes('"') || str.includes('\n')) {
                return '"' + str.replace(/"/g, '""') + '"';
            }
            return str;
        };

        const csvRows = [
            // Row 1: display names (human-readable, for Google Sheets)
            displayNames.map(escape).join(','),
            // Row 2+: data using the same column order
            ...items.map(item => fieldNames.map(n => escape(item[n])).join(',')),
        ];

        // Prepend a hidden #fields: row so the importer knows the exact column-to-field mapping
        const mappingRow = '#fields:' + fieldNames.join(',');
        const finalCSV = [mappingRow, ...csvRows].join('\n');

        const blob = new Blob(['\uFEFF' + finalCSV], { type: 'text/csv;charset=utf-8;' });
        const url  = URL.createObjectURL(blob);
        const a    = document.createElement('a');
        a.href     = url;
        a.download = `${tableInfo.display_name.replace(/\s+/g, '_')}_${new Date().toISOString().slice(0,10)}.csv`;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);
    };

    // Read a CSV file chosen by the user and insert each row as a new item.
    // Supports two formats:
    //   - Our own export (has a "#fields:" mapping row) — uses that row for column-to-field mapping.
    //   - Plain CSV — matches headers against field_name OR display_name.
    const handleImport = async (e) => {
        const file = e.target.files[0];
        if (!file) return;
        e.target.value = ''; // reset so same file can be reloaded

        setImportLoading(true);
        try {
            const text = await file.text();
            const rows = parseCSV(text);
            if (rows.length < 2) {
                alert('CSV needs at least a header row and one data row.');
                setImportLoading(false);
                return;
            }

            // Detect whether this CSV came from our own exporter (has #fields: row) or is a plain external CSV
            let fieldNameRow = null;
            let headerRow    = null;
            let dataStartIdx = 0;

            if (rows[0][0] && rows[0][0].startsWith('#fields:')) {
                // Our own export format: row 0 = mapping row, row 1 = display headers, row 2+ = data
                // The #fields: row was exported as: #fields:field1,field2,field3
                // CSV parser splits by comma so: rows[0] = ['#fields:field1','field2','field3']
                // Reconstruct by joining all cells then stripping the prefix
                const fullMappingLine = rows[0].join(',');
                const mapping = fullMappingLine.replace('#fields:', '').split(',');
                fieldNameRow  = mapping;
                headerRow     = rows[1];
                dataStartIdx  = 2;
            } else {
                // Plain CSV: try to match headers to field_names or display_names
                headerRow    = rows[0];
                dataStartIdx = 1;
            }

            // Map each CSV column index to its matching field definition (by field_name or display_name)
            const colMap = {}; // colIndex → field definition
            const headers = fieldNameRow || headerRow;
            headers.forEach((col, idx) => {
                const colClean = col.trim().toLowerCase();
                const matched = fields.find(f =>
                    f.field_name.toLowerCase()   === colClean ||
                    f.display_name.toLowerCase() === colClean
                );
                if (matched) colMap[idx] = matched;
            });

            if (Object.keys(colMap).length === 0) {
                alert('No matching columns found.\n\nCSV headers should match field names like: ' +
                      fields.map(f => f.field_name).join(', '));
                setImportLoading(false);
                return;
            }

            const userId = window.currentUser?.id;
            let imported = 0;
            let skipped  = 0;
            let errors   = [];

            for (let i = dataStartIdx; i < rows.length; i++) {
                const row = rows[i];
                if (row.every(v => !v.trim())) continue; // skip blank rows

                const rowData = {};
                if (userId) rowData.user_id = userId;

                Object.entries(colMap).forEach(([idx, field]) => {
                    let val = (row[idx] ?? '').trim();
                    if (field.field_type === 'number') {
                        rowData[field.field_name] = val === '' ? 0 : Number(val);
                    } else if (field.field_type === 'date') {
                        rowData[field.field_name] = val || null;
                    } else {
                        rowData[field.field_name] = val;
                    }
                });

                const { error } = await window.db.from(tableName).insert([rowData]);
                if (error) { errors.push(`Row ${i}: ${error.message}`); skipped++; }
                else { imported++; }
            }

            await fetchItems();

            let msg = `✅ Import complete: ${imported} item${imported !== 1 ? 's' : ''} added.`;
            if (skipped > 0) msg += `\n⚠️ ${skipped} row${skipped !== 1 ? 's' : ''} failed.`;
            if (errors.length > 0 && errors.length <= 5) msg += '\n\nErrors:\n' + errors.join('\n');
            alert(msg);
        } catch (err) {
            alert('Import error: ' + err.message);
        }
        setImportLoading(false);
    };

    // ============================================================================
    // 10. FILTER + SORT (runs every render)
    // ============================================================================
    // Keep items where ANY field value contains the search term (case-insensitive).
    const filtered = items.filter(item =>
        !searchTerm || fields.some(f => {
            const v = item[f.field_name];
            return v && v.toString().toLowerCase().includes(searchTerm.toLowerCase());
        })
    );

    // Sort by the chosen field. Nulls go last. Numbers compared numerically; strings use localeCompare (numeric-aware).
    const displayItems = sortField
        ? [...filtered].sort((a, b) => {
            const aVal = a[sortField];
            const bVal = b[sortField];
            if (aVal == null && bVal == null) return 0;
            if (aVal == null) return sortDir === 'asc' ? 1  : -1;
            if (bVal == null) return sortDir === 'asc' ? -1 :  1;
            if (typeof aVal === 'number' && typeof bVal === 'number') {
                return sortDir === 'asc' ? aVal - bVal : bVal - aVal;
            }
            const cmp = String(aVal).localeCompare(String(bVal), undefined, { numeric: true });
            return sortDir === 'asc' ? cmp : -cmp;
        })
        : filtered;

    // ============================================================================
    // 11. RENDER HELPERS
    // ============================================================================
    if (!tableInfo) return <div className="center-msg">Loading...</div>;

    // "Toners" → "Toner" for button labels like "+ Add Toner".
    const singularName = tableInfo.display_name.replace(/s$/i, '');
    // Only show qty stats when this category has a quantity field.
    const hasQty = fields.find(f => f.field_name === 'quantity');

    // Total / Total Qty / Low Stock summary — placed top or bottom per user pref.
    const statsBlock = (
        <div className="stats-bar">
            <div className="stat-block">
                <div className="stat-label">Total Items</div>
                <div className="stat-num">{displayItems.length}</div>
            </div>
            {hasQty && <>
                <div className="stat-block">
                    <div className="stat-label">Total Qty</div>
                    <div className="stat-num green">
                        {displayItems.reduce((s, i) => s + (i.quantity || 0), 0)}
                    </div>
                </div>
                <div className="stat-block">
                    <div className="stat-label">Low Stock</div>
                    <div className="stat-num red">
                        {displayItems.filter(i => (i.quantity || 0) < lowThreshold).length}
                    </div>
                </div>
            </>}
        </div>
    );

    // ============================================================================
    // 12. RENDER
    // ============================================================================
    return (
        <div>
            {/* Page bar: category title + Export/Import CSV buttons */}
            <div className="page-bar">
                <h1 className="page-title">{tableInfo.icon || ''} {tableInfo.display_name}</h1>
                <div className="page-actions">
                    <button
                        className="btn-export"
                        onClick={exportCSV}
                        disabled={!items.length}
                        title="Download all items as a CSV file (opens in Google Sheets)"
                    >
                        ⬇ Export CSV
                    </button>
                    <label
                        className={`btn-import${importLoading ? ' loading' : ''}`}
                        title="Import items from a CSV file"
                        style={{ pointerEvents: importLoading ? 'none' : 'auto' }}
                    >
                        {importLoading ? '⏳ Importing…' : '⬆ Import CSV'}
                        <input
                            type="file"
                            accept=".csv,text/csv"
                            style={{ display: 'none' }}
                            onChange={handleImport}
                            disabled={importLoading}
                        />
                    </label>
                </div>
            </div>

            {/* Toolbar: search, sort field, sort direction, add/cancel */}
            <div className="toolbar">
                <input
                    type="text"
                    placeholder="Search..."
                    value={searchTerm}
                    onChange={e => setSearchTerm(e.target.value)}
                />

                <select
                    className="sort-select"
                    value={sortField}
                    onChange={e => handleSortField(e.target.value)}
                    title="Sort by field"
                >
                    <option value="">Sort: Default</option>
                    {fields.map(f => (
                        <option key={f.field_name} value={f.field_name}>{f.display_name}</option>
                    ))}
                </select>

                <button
                    className="btn-sort-dir"
                    onClick={handleSortDir}
                    title={sortDir === 'asc' ? 'Ascending' : 'Descending'}
                >
                    {sortDir === 'asc' ? '↑ Asc' : '↓ Desc'}
                </button>

                <button
                    className={`btn-add${showAddForm || editingId ? ' cancel' : ''}`}
                    onClick={() => {
                        if (showAddForm || editingId) { cancelForm(); }
                        else { setShowAddForm(true); setFormData(blankForm()); }
                    }}
                >
                    {showAddForm || editingId ? 'Cancel' : `+ Add ${singularName}`}
                </button>
            </div>

            {/* Add/Edit form — only rendered when adding or editing */}
            {(showAddForm || editingId) && (
                <div className="form-panel">
                    <h2>{editingId ? `Edit ${singularName}` : `New ${singularName}`}</h2>
                    <form onSubmit={handleSubmit}>
                        <div className="form-grid">
                            {fields.map(field => (
                                <div className="form-group" key={field.field_name}>
                                    <label>{field.display_name}{field.required ? ' *' : ''}</label>
                                    <input
                                        type={field.field_type === 'number' ? 'number' : field.field_type === 'date' ? 'date' : 'text'}
                                        required={field.required}
                                        value={formData[field.field_name] ?? ''}
                                        onChange={e => setFormData({
                                            ...formData,
                                            [field.field_name]: field.field_type === 'number' ? Number(e.target.value) : e.target.value
                                        })}
                                    />
                                </div>
                            ))}
                        </div>
                        <div className="form-actions">
                            <button type="submit" className="btn-submit">
                                {editingId ? 'Update' : 'Add'}
                            </button>
                            <button type="button" className="btn-cancel" onClick={cancelForm}>Cancel</button>
                        </div>
                    </form>
                </div>
            )}

            {/* Stats bar (top) — only if user set stats_position = 'top' */}
            {statsPosition === 'top' && !loading && displayItems.length > 0 && statsBlock}

            {/* Items list OR empty/loading message */}
            {loading ? (
                <div className="center-msg">Loading...</div>
            ) : displayItems.length === 0 ? (
                <div className="center-msg">
                    {searchTerm
                        ? 'No items match your search'
                        : `No items yet — tap "+ Add ${singularName}" to start!`}
                </div>
            ) : (
                <>
                    <div className="items-list">
                        {displayItems.map(item => (
                            <div className="item-card" key={item.id}>
                                <div className="item-fields">
                                    {fields.map(f => {
                                        const val = item[f.field_name];
                                        const isQty = f.field_name === 'quantity';
                                        const isLow = isQty && (val ?? 0) < lowThreshold;
                                        return (
                                            <div className="item-field" key={f.field_name}>
                                                <div className="field-label">{f.display_name}</div>
                                                <div className={`field-value${isQty ? ' qty' : ''}${isLow ? ' low-qty' : ''}`}>
                                                    {val ?? '-'}
                                                </div>
                                            </div>
                                        );
                                    })}
                                </div>
                                <div className="item-actions">
                                    <button className="btn-edit" onClick={() => startEdit(item)}>Edit</button>
                                    <button className="btn-del"  onClick={() => handleDelete(item.id)}>Delete</button>
                                </div>
                            </div>
                        ))}
                    </div>

                    {statsPosition !== 'top' && statsPosition !== 'hidden' && statsBlock}
                </>
            )}
        </div>
    );
}

// ============================================================================
// 13. MOUNT
// Mount React as soon as auth is confirmed (either already done, or via event).
// ============================================================================
function init() {
    ReactDOM.render(<InventoryApp />, document.getElementById('root'));
}
if (window.currentSession) init();
else window.addEventListener('auth-ready', init);
