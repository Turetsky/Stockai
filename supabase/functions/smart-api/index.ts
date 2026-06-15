/**
 * smart-api  —  Inventory Manager Edge Function  (v4.0)
 *
 * ┌─────────────────────────────────────────────────────────┐
 * │  JWT ENFORCEMENT: ON  (set this in Supabase Dashboard)  │
 * └─────────────────────────────────────────────────────────┘
 *
 * Security model:
 *   userDb  → all DML (SELECT / INSERT / UPDATE / DELETE)
 *              Carries user JWT → RLS auto-scopes to auth.uid()
 *              Every read/write is isolated per-user automatically.
 *
 *   adminDb → DDL only (CREATE TABLE / DROP TABLE / ALTER TABLE
 *              via exec_sql RPC — service role bypasses RLS)
 *              Also used for field_definitions writes (no user RLS on writes)
 *
 * Token handling:
 *   Frontend must call supabase.auth.refreshSession() before requests,
 *   not just getSession(). getSession() returns a cached token that may
 *   be stale. refreshSession() ensures a valid, fresh JWT is sent.
 *
 * HOW TO DEPLOY:
 *   Supabase Dashboard → Edge Functions → smart-api → Edit → paste → Deploy
 *   Secrets needed: ANTHROPIC_API_KEY, SUPABASE_SERVICE_ROLE_KEY
 *   Set JWT Enforcement: ON
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// ============================================================================
// 1. TOOL DEFINITIONS — schemas the AI sees
// ============================================================================
const tools = [
  {
    name: 'list_categories',
    description: 'List all inventory categories for the current user.',
    input_schema: { type: 'object', properties: {} },
  },
  {
    name: 'get_items',
    description: 'Get all items from a specific inventory table.',
    input_schema: {
      type: 'object',
      properties: {
        table_name: { type: 'string', description: 'e.g. "toners"' },
      },
      required: ['table_name'],
    },
  },
  {
    name: 'get_fields',
    description: 'Get the field/column definitions for an inventory table. ' +
      'Fields are ordered by sort_order. The field with the LOWEST sort_order is always the item identity/name (shown as card title). ' +
      'The field with the SECOND LOWEST sort_order is always the quantity (shown as stock badge). ' +
      'Always call this before upsert_item.',
    input_schema: {
      type: 'object',
      properties: { table_name: { type: 'string' } },
      required: ['table_name'],
    },
  },
  {
    name: 'create_category',
    description:
      'Create a new inventory category with custom fields. ' +
      'MANDATORY: fields array MUST contain at least 2 entries — omitting either is a bug.\n' +
      'FIELD ORDER IS CRITICAL — always structure the fields array exactly like this:\n' +
      '  fields[0]: item identity/name (field_type: "text", required: true) — card title. e.g. { field_name: "name", display_name: "Name", field_type: "text", required: true }\n' +
      '  fields[1]: quantity (field_type: "number") — stock count badge. e.g. { field_name: "quantity", display_name: "Quantity", field_type: "number" }\n' +
      '  fields[2+]: any additional custom fields (color, location, notes, price, etc.).\n' +
      'NEVER omit fields[0] or fields[1]. NEVER put a non-name field at position 0. ' +
      'The first field must always be the human-readable item name.',
    input_schema: {
      type: 'object',
      properties: {
        table_name:   { type: 'string', description: 'Lowercase snake_case, e.g. "computer_accessories"' },
        display_name: { type: 'string', description: 'Label shown on dashboard' },
        icon:         { type: 'string', description: 'Emoji icon, e.g. "💻"' },
        fields: {
          type: 'array',
          description: 'Columns for this table.',
          items: {
            type: 'object',
            properties: {
              field_name:   { type: 'string' },
              display_name: { type: 'string' },
              field_type:   { type: 'string', enum: ['text', 'number', 'date'] },
              required:     { type: 'boolean' },
              sort_order:   { type: 'number' },
            },
            required: ['field_name', 'display_name', 'field_type'],
          },
        },
      },
      required: ['table_name', 'display_name', 'fields'],
    },
  },
  {
    name: 'rename_category',
    description: 'Rename the display name or icon of an existing category.',
    input_schema: {
      type: 'object',
      properties: {
        table_name:       { type: 'string' },
        new_display_name: { type: 'string' },
        new_icon:         { type: 'string' },
      },
      required: ['table_name'],
    },
  },
  {
    name: 'delete_category',
    description: 'Permanently delete a category and all its items. Always confirm with the user first.',
    input_schema: {
      type: 'object',
      properties: { table_name: { type: 'string' } },
      required: ['table_name'],
    },
  },
  {
    name: 'add_field',
    description: 'Add a new column to an existing inventory table.',
    input_schema: {
      type: 'object',
      properties: {
        table_name:   { type: 'string' },
        field_name:   { type: 'string' },
        display_name: { type: 'string' },
        field_type:   { type: 'string', enum: ['text', 'number', 'date'] },
        required:     { type: 'boolean' },
      },
      required: ['table_name', 'field_name', 'display_name', 'field_type'],
    },
  },
  {
    name: 'remove_field',
    description: 'Remove a field/column from an existing inventory table. Always confirm with the user first as this deletes all data in that column.',
    input_schema: {
      type: 'object',
      properties: {
        table_name: { type: 'string' },
        field_name: { type: 'string', description: 'The field_name (snake_case) to remove' },
      },
      required: ['table_name', 'field_name'],
    },
  },
  {
    name: 'rename_field',
    description: 'Rename the display name of an existing field, and optionally change its type.',
    input_schema: {
      type: 'object',
      properties: {
        table_name:       { type: 'string' },
        field_name:       { type: 'string', description: 'The current field_name (snake_case)' },
        new_display_name: { type: 'string', description: 'New human-readable label' },
        new_field_type:   { type: 'string', enum: ['text', 'number', 'date', 'textarea'], description: 'Optional — change the column type. Existing data will be cast; cast failures will error.' },
      },
      required: ['table_name', 'field_name', 'new_display_name'],
    },
  },
  {
    name: 'upsert_item',
    description: 'Add a new item or update an existing one. IMPORTANT: You MUST call get_fields first to get the exact field_name and field_type for this table. The data keys must exactly match field_name values from get_fields. Number fields must have numeric values. Text fields must have string values. Do NOT guess field names.',
    input_schema: {
      type: 'object',
      properties: {
        table_name: { type: 'string' },
        id:         { type: 'string', description: 'UUID of item to update. Omit to create new.' },
        data:       { type: 'object', description: 'field_name → value pairs. Keys must exactly match field_name from get_fields. Values must match the field_type (number fields need numeric values, text fields need strings).' },
      },
      required: ['table_name', 'data'],
    },
  },
  {
    name: 'delete_item',
    description: 'Delete a specific item by ID.',
    input_schema: {
      type: 'object',
      properties: {
        table_name: { type: 'string' },
        id:         { type: 'string' },
      },
      required: ['table_name', 'id'],
    },
  },
  // run_sql removed from Claude's tool list — AI should not have arbitrary SQL access.
  // Still available via direct tool_call from trusted internal clients if needed.
  {
    name: 'get_ui_settings',
    description: 'Read all theme and layout settings for the current user.',
    input_schema: { type: 'object', properties: {} },
  },
  {
    name: 'set_ui_setting',
    description: `Update one or more UI/theme settings for the current user. Available keys:

HEADER & BRANDING:
- primary_color_start / primary_color_end  → header gradient (hex)
- header_text_color                        → header text color (hex)

COLORS (web & mobile app):
- theme_color         → Flutter app primary/seed color (hex, e.g. "#667eea") — changes the whole app palette
- theme_mode          → Flutter app color mode: "light", "dark", or "system"
- accent_color        → buttons, highlights (hex)
- bg_color            → page/app background (hex)
- card_color          → dashboard card / app card background (hex)

TYPOGRAPHY:
- font_size_base        → e.g. "14px", "16px"
- text_primary_color    → main text (hex)
- text_secondary_color  → secondary text (hex)

INVENTORY:
- item_card_bg    → item row background (hex)
- stats_bar_bg    → stats bar background (hex)
- low_stock_color → low-stock warning (hex)
- btn_add_bg / btn_edit_bg / btn_del_bg → button colors

CARD STYLE:
- card_radius → e.g. "8px", "20px"

THRESHOLDS:
- low_stock_threshold → integer`,
    input_schema: {
      type: 'object',
      properties: {
        settings: {
          type: 'object',
          description: 'key → value pairs',
        },
      },
      required: ['settings'],
    },
  },
  {
    name: 'set_layout',
    description: `Adjust layout and sort defaults. Available keys:

LAYOUT:
- search_position  → "card" | "standalone" | "hidden"
- stats_position   → "bottom" | "top" | "hidden"

SORT:
- dashboard_sort             → "default" | "name_asc" | "name_desc" | "count_desc" | "qty_desc"
- inventory_default_sort     → field name (e.g. "quantity", "created_at")
- inventory_default_sort_dir → "asc" | "desc"

SIZE:
- dashboard_card_min_width → "200px" | "280px" | "320px" | "360px"
- item_card_density        → "compact" | "normal" | "large"`,
    input_schema: {
      type: 'object',
      properties: {
        settings: { type: 'object', description: 'layout_key → value pairs' },
      },
      required: ['settings'],
    },
  },
];

// ============================================================================
// 2. HELPERS — pgType, sanitizeTableName, assertOwnership
// ============================================================================

function pgType(fieldType: string): string {
  if (fieldType === 'number') return 'numeric';
  if (fieldType === 'date')   return 'date';
  return 'text';
}

/** Sanitize a table name to prevent SQL injection in DDL statements.
 *  Only allows lowercase letters, digits, underscores. */
function sanitizeTableName(name: string): string {
  const clean = name.toLowerCase().replace(/[^a-z0-9_]/g, '');
  if (!clean) throw new Error('Invalid table name.');
  return clean;
}

/** Verify the table belongs to userId via RLS-scoped userDb.
 *  Returns the table_definitions row or throws. */
async function assertOwnership(
  tableName: string,
  userDb: ReturnType<typeof createClient>,
): Promise<void> {
  const { data, error } = await userDb
    .from('table_definitions')
    .select('table_name')
    .eq('table_name', tableName)
    .single();

  if (error || !data) {
    throw new Error(`Category "${tableName}" not found or does not belong to your account.`);
  }
}

// ============================================================================
// 3. TOOL EXECUTOR — switch on tool name, run the requested action
// ============================================================================
async function runTool(
  name: string,
  input: Record<string, unknown>,
  userId: string,
  adminDb: ReturnType<typeof createClient>,
  userDb: ReturnType<typeof createClient>,
): Promise<{ result: string; refresh: boolean }> {
  let refresh = false;

  try {
    switch (name) {

      /* ── READ ─────────────────────────────────────────────── */

      case 'list_categories': {
        // userDb + RLS: only returns this user's categories automatically
        const { data, error } = await userDb
          .from('table_definitions')
          .select('*')
          .order('display_name');
        if (error) throw error;
        return { result: JSON.stringify(data ?? []), refresh: false };
      }

      case 'get_items': {
        const tn = sanitizeTableName(input.table_name as string);
        // Ownership check first — prevents probing other users' tables
        await assertOwnership(tn, userDb);

        // userDb + RLS: only returns this user's rows
        const { data, error } = await userDb
          .from(tn)
          .select('*')
          .order('created_at', { ascending: false });
        if (error) throw error;
        return { result: JSON.stringify(data ?? []), refresh: false };
      }

      case 'get_fields': {
        const tn = sanitizeTableName(input.table_name as string);
        // Ownership check via userDb — RLS enforces this user owns the table
        await assertOwnership(tn, userDb);

        // field_definitions SELECT policy is ownership-scoped; also filter by user_id for certainty
        const { data, error } = await userDb
          .from('field_definitions')
          .select('*')
          .eq('table_name', tn)
          .eq('user_id', userId)
          .order('sort_order');
        if (error) throw error;
        return { result: JSON.stringify(data ?? []), refresh: false };
      }

      /* ── CATEGORIES ───────────────────────────────────────── */

      case 'create_category': {
        const tn     = sanitizeTableName(input.table_name as string);
        const dname  = input.display_name as string;
        const icon   = (input.icon as string) ?? '📦';
        const fields = input.fields as Array<{
          field_name: string;
          display_name: string;
          field_type: string;
          required?: boolean;
          sort_order?: number;
        }>;

        if (!dname?.trim()) throw new Error('display_name is required.');
        if (!fields?.length) throw new Error('At least one field is required.');

        // Enforce required structure: fields[0] must be text (item name), fields[1] must exist (quantity)
        const firstIsText = fields[0]?.field_type === 'text';
        if (!firstIsText) {
          // Prepend a name field if the AI forgot it or put a number field first
          fields.unshift({ field_name: 'name', display_name: 'Name', field_type: 'text', required: true });
        }
        if (fields.length < 2) {
          fields.push({ field_name: 'quantity', display_name: 'Quantity', field_type: 'number', required: false });
        }

        // 1. Register category — userDb WITH CHECK enforces user_id = auth.uid()
        const { error: tdErr } = await userDb.from('table_definitions').insert({
          table_name:   tn,
          display_name: dname.trim(),
          icon,
          user_id:      userId,
        });
        if (tdErr) throw tdErr;

        // 2. Create the physical table (DDL via service role)
        const colDefs = fields
          .map(f => `  ${sanitizeTableName(f.field_name)} ${pgType(f.field_type)}`)
          .join(',\n');

        const createSQL = `
          CREATE TABLE IF NOT EXISTS ${tn} (
            id         uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
            user_id    uuid        NOT NULL,
            created_at timestamptz DEFAULT now()
            ${colDefs ? ',\n' + colDefs : ''}
          );
          ALTER TABLE ${tn} ENABLE ROW LEVEL SECURITY;

          DROP POLICY IF EXISTS "${tn}_select" ON ${tn};
          DROP POLICY IF EXISTS "${tn}_insert" ON ${tn};
          DROP POLICY IF EXISTS "${tn}_update" ON ${tn};
          DROP POLICY IF EXISTS "${tn}_delete" ON ${tn};

          CREATE POLICY "${tn}_select" ON ${tn}
            FOR SELECT USING (auth.uid() IS NOT NULL AND auth.uid() = user_id);
          CREATE POLICY "${tn}_insert" ON ${tn}
            FOR INSERT WITH CHECK (auth.uid() IS NOT NULL AND auth.uid() = user_id);
          CREATE POLICY "${tn}_update" ON ${tn}
            FOR UPDATE USING (auth.uid() IS NOT NULL AND auth.uid() = user_id);
          CREATE POLICY "${tn}_delete" ON ${tn}
            FOR DELETE USING (auth.uid() IS NOT NULL AND auth.uid() = user_id);
        `;

        const { data: sqlRes } = await adminDb.rpc('exec_sql', { sql: createSQL });
        if (sqlRes?.error) throw new Error(`DDL error: ${sqlRes.error}`);

        // 3. Register field definitions (service role — field_definitions has no user write RLS)
        const fieldRows = fields.map((f, i) => ({
          table_name:   tn,
          field_name:   sanitizeTableName(f.field_name),
          display_name: f.display_name,
          field_type:   f.field_type,
          required:     f.required  ?? false,
          sort_order:   f.sort_order ?? i,
          user_id:      userId,   // scoped per user — two users can share same field names
        }));
        const { error: fdErr } = await adminDb.from('field_definitions').insert(fieldRows);
        if (fdErr) throw fdErr;

        refresh = true;
        return {
          result: `✅ Category "${dname}" created with ${fields.length} field(s).`,
          refresh,
        };
      }

      case 'rename_category': {
        const tn = sanitizeTableName(input.table_name as string);
        const updates: Record<string, unknown> = {};
        if (input.new_display_name) updates.display_name = input.new_display_name;
        if (input.new_icon)         updates.icon         = input.new_icon;
        if (!Object.keys(updates).length) throw new Error('Nothing to update.');

        // userDb + RLS: only updates this user's row (USING auth.uid() = user_id)
        const { error } = await userDb
          .from('table_definitions')
          .update(updates)
          .eq('table_name', tn);
        if (error) throw error;

        refresh = true;
        return { result: `✅ Category updated.`, refresh };
      }

      case 'delete_category': {
        const tn = sanitizeTableName(input.table_name as string);

        // Verify ownership — throws if not found or not this user's
        await assertOwnership(tn, userDb);

        // Drop physical table (service role for DDL)
        const { data: dropRes } = await adminDb.rpc('exec_sql', {
          sql: `DROP TABLE IF EXISTS ${tn} CASCADE;`,
        });
        if (dropRes?.error) throw new Error(`DDL error: ${dropRes.error}`);

        // Remove metadata (userDb RLS ensures own-row-only delete)
        await userDb.from('table_definitions').delete().eq('table_name', tn);
        // field_definitions cleanup via adminDb — scoped to this user's fields
        await adminDb.from('field_definitions').delete().eq('table_name', tn).eq('user_id', userId);

        refresh = true;
        return { result: `✅ Category "${tn}" and all its items have been deleted.`, refresh };
      }

      /* ── FIELDS ───────────────────────────────────────────── */

      case 'add_field': {
        const tn = sanitizeTableName(input.table_name as string);
        const fn = sanitizeTableName(input.field_name as string);

        // Verify ownership
        await assertOwnership(tn, userDb);

        // DDL: add column to physical table
        const { data: alterRes } = await adminDb.rpc('exec_sql', {
          sql: `ALTER TABLE ${tn} ADD COLUMN IF NOT EXISTS ${fn} ${pgType(input.field_type as string)};`,
        });
        if (alterRes?.error) throw new Error(`DDL error: ${alterRes.error}`);

        // Get next sort order
        const { data: existing } = await adminDb
          .from('field_definitions')
          .select('sort_order')
          .eq('table_name', tn)
          .order('sort_order', { ascending: false })
          .limit(1);
        const nextOrder = ((existing?.[0]?.sort_order as number) ?? 0) + 1;

        const { error } = await adminDb.from('field_definitions').insert({
          table_name:   tn,
          field_name:   fn,
          display_name: input.display_name as string,
          field_type:   input.field_type as string,
          required:     (input.required as boolean) ?? false,
          sort_order:   nextOrder,
          user_id:      userId,   // scoped per user
        });
        if (error) throw error;

        refresh = true;
        return { result: `✅ Field "${input.display_name}" added to ${tn}.`, refresh };
      }

      case 'remove_field': {
        const tn = sanitizeTableName(input.table_name as string);
        const fn = sanitizeTableName(input.field_name as string);

        // Prevent removing system/protected fields
        const protected_fields = ['id', 'user_id', 'created_at', 'updated_at'];
        if (protected_fields.includes(fn)) {
          throw new Error(`Cannot remove system field "${fn}".`);
        }

        await assertOwnership(tn, userDb);

        // Drop column from physical table
        const { data: alterRes } = await adminDb.rpc('exec_sql', {
          sql: `ALTER TABLE ${tn} DROP COLUMN IF EXISTS ${fn};`,
        });
        if (alterRes?.error) throw new Error(`DDL error: ${alterRes.error}`);

        // Remove from field_definitions
        await adminDb.from('field_definitions')
          .delete()
          .eq('table_name', tn)
          .eq('field_name', fn)
          .eq('user_id', userId);

        refresh = true;
        return { result: `✅ Field "${fn}" removed from ${tn}.`, refresh };
      }

      case 'rename_field': {
        const tn = sanitizeTableName(input.table_name as string);
        const fn = sanitizeTableName(input.field_name as string);
        const newType = input.new_field_type as string | undefined;

        await assertOwnership(tn, userDb);

        // If field type is changing, ALTER the physical column first
        if (newType) {
          const pgT = pgType(newType);
          const { data: alterRes } = await adminDb.rpc('exec_sql', {
            sql: `ALTER TABLE ${tn} ALTER COLUMN ${fn} TYPE ${pgT} USING ${fn}::${pgT};`,
          });
          if (alterRes?.error) throw new Error(`Type change failed: ${alterRes.error}`);
        }

        const metaUpdate: Record<string, string> = { display_name: input.new_display_name as string };
        if (newType) metaUpdate['field_type'] = newType;

        const { error } = await adminDb.from('field_definitions')
          .update(metaUpdate)
          .eq('table_name', tn)
          .eq('field_name', fn)
          .eq('user_id', userId);
        if (error) throw error;

        refresh = true;
        const typeNote = newType ? ` (type → ${newType})` : '';
        return { result: `✅ Field "${fn}" renamed to "${input.new_display_name}"${typeNote}.`, refresh };
      }

      /* ── ITEMS ────────────────────────────────────────────── */

      case 'upsert_item': {
        const tn   = sanitizeTableName(input.table_name as string);
        const data = input.data as Record<string, unknown>;

        // Ownership check before any write
        await assertOwnership(tn, userDb);

        if (input.id) {
          // UPDATE — userDb + RLS USING(auth.uid() = user_id) prevents touching others' rows
          const { error } = await userDb
            .from(tn)
            .update(data)
            .eq('id', input.id as string);
          if (error) throw error;
        } else {
          // INSERT — explicitly stamp user_id; RLS WITH CHECK is a second layer
          const { error } = await userDb
            .from(tn)
            .insert({ ...data, user_id: userId });
          if (error) throw error;
        }

        refresh = true;
        return { result: `✅ Item saved.`, refresh };
      }

      case 'delete_item': {
        const tn = sanitizeTableName(input.table_name as string);

        // Ownership check
        await assertOwnership(tn, userDb);

        // Fetch the item before deleting so we can archive it
        const { data: itemRow } = await userDb
          .from(tn)
          .select('*')
          .eq('id', input.id as string)
          .single();

        if (itemRow) {
          // Soft-delete: move to recycling bin (non-blocking — failure must not prevent hard delete)
          try {
            await userDb.from('recycling_bin').insert({
              user_id:      userId,
              source_table: tn,
              item_id:      input.id as string,
              item_data:    itemRow,
            });

            // Auto-cleanup: purge this user's recycled items older than 30 days
            await userDb
              .from('recycling_bin')
              .delete()
              .eq('user_id', userId)
              .lt('deleted_at', new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString());
          } catch (_) {
            // Recycling bin is best-effort; do not block the actual delete
          }
        }

        // Hard-delete from source table (RLS scoped to auth.uid())
        const { error } = await userDb
          .from(tn)
          .delete()
          .eq('id', input.id as string);
        if (error) throw error;

        refresh = true;
        return { result: `✅ Item deleted.`, refresh };
      }

      case 'run_sql': {
        const rawSql = input.sql as string;

        // Strip comments before checking (prevent bypass via -- or /* */)
        const stripped = rawSql
          .replace(/--[^\n]*/g, '')
          .replace(/\/\*[\s\S]*?\*\//g, '');

        // Block DDL/DCL and system schema access — use dedicated tools for schema changes
        const forbidden: Array<[RegExp, string]> = [
          [/\balter\b/i,               'ALTER'],
          [/\bdrop\b/i,                'DROP'],
          [/\bcreate\b/i,              'CREATE'],
          [/\bgrant\b/i,               'GRANT'],
          [/\brevoke\b/i,              'REVOKE'],
          [/\btruncate\b/i,            'TRUNCATE'],
          [/\bset\s+role\b/i,          'SET ROLE'],
          [/\bauth\./i,                'auth schema'],
          [/\bpg_/i,                   'pg_ system tables'],
          [/\binformation_schema\b/i,  'information_schema'],
        ];

        for (const [pattern, label] of forbidden) {
          if (pattern.test(stripped)) {
            throw new Error(
              `SQL blocked: "${label}" is not permitted in run_sql. Use the dedicated tools (create_category, add_field, delete_category) for schema changes.`
            );
          }
        }

        // Require user_id scoped to the authenticated user's exact UUID.
        // Loose word-match on "user_id" is bypassable (e.g. WHERE user_id IS NOT NULL)
        // so we require the actual UUID to appear alongside user_id.
        const userIdFilter = new RegExp(`\\buser_id\\s*=\\s*'${userId}'`, 'i');
        if (!userIdFilter.test(stripped)) {
          throw new Error(
            `SQL blocked: query must include WHERE user_id = '${userId}' to prevent cross-user data access.`
          );
        }

        const { data, error } = await adminDb.rpc('exec_sql', { sql: rawSql });
        if (error) throw error;
        if (data?.error) throw new Error(data.error);
        refresh = true;
        return { result: `✅ SQL executed: ${JSON.stringify(data)}`, refresh };
      }

      /* ── UI SETTINGS ──────────────────────────────────────── */

      case 'get_ui_settings': {
        // userDb + RLS: each user only sees their own settings
        const { data, error } = await userDb
          .from('ui_settings')
          .select('key, value')
          .order('key');
        if (error) throw error;
        return { result: JSON.stringify(data ?? []), refresh: false };
      }

      case 'set_ui_setting': {
        const settings = input.settings as Record<string, string>;
        for (const [key, value] of Object.entries(settings)) {
          const { error } = await userDb
            .from('ui_settings')
            .upsert(
              { key, value, user_id: userId, updated_at: new Date().toISOString() },
              { onConflict: 'key,user_id' },
            );
          if (error) throw error;
        }
        refresh = true;
        return {
          result: `✅ Updated settings: ${Object.keys(settings).join(', ')}. Page will refresh.`,
          refresh,
        };
      }

      case 'set_layout': {
        const settings = input.settings as Record<string, string>;
        for (const [key, value] of Object.entries(settings)) {
          const { error } = await userDb
            .from('ui_settings')
            .upsert(
              { key, value, user_id: userId, updated_at: new Date().toISOString() },
              { onConflict: 'key,user_id' },
            );
          if (error) throw error;
        }
        refresh = true;
        return {
          result: `✅ Layout updated: ${Object.keys(settings).join(', ')}. Page will refresh.`,
          refresh,
        };
      }

      case 'send_feedback': {
        const message = input.message as string;
        const userEmail = (input.user_email as string) ?? '';
        if (!message?.trim()) throw new Error('Message is required.');

        // Always persist to DB
        const { error: fbErr } = await adminDb
          .from('feedback')
          .insert({ user_id: userId, user_email: userEmail, message: message.trim() });
        if (fbErr) console.error('Feedback DB error:', fbErr.message);

        // Send email via Resend if key is configured
        const resendKey = Deno.env.get('RESEND_API_KEY');
        if (resendKey) {
          const emailRes = await fetch('https://api.resend.com/emails', {
            method: 'POST',
            headers: {
              'Authorization': `Bearer ${resendKey}`,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({
              from: 'Inventory Feedback <onboarding@resend.dev>',
              to: ['yjturetsky@gmail.com'],
              subject: `Feedback from ${userEmail || userId}`,
              text: message.trim(),
            }),
          });
          if (!emailRes.ok) {
            console.error('Resend error:', await emailRes.text());
          }
        }

        return { result: '✅ Feedback submitted. Thank you!', refresh: false };
      }

      default:
        return { result: `Unknown tool: ${name}`, refresh: false };
    }
  } catch (err) {
    return { result: `❌ Error in ${name}: ${(err as Error).message}`, refresh: false };
  }
}

// ============================================================================
// 4. MAIN REQUEST HANDLER — serves every incoming POST
// ============================================================================
Deno.serve(async (req) => {
  // CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const body        = await req.json();
    const userMessage = (body.message ?? body.messages?.at(-1)?.content ?? '') as string;
    const inventory   = body.inventory ?? [];
    const context     = body.context   ?? {};

    /* ── Token extraction ─────────────────────────────────── */
    const authHeader = req.headers.get('Authorization') ?? '';
    const token      = authHeader.startsWith('Bearer ')
      ? authHeader.slice(7).trim()
      : authHeader.trim();

    if (!token) {
      return new Response(
        JSON.stringify({ error: 'Missing Authorization header. Please log in again.' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    /* ── Supabase clients ─────────────────────────────────── */

    // Service-role client — DDL only, bypasses RLS
    const adminDb = createClient(
      Deno.env.get('SUPABASE_URL')              ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { persistSession: false } },
    );

    // User client — carries the JWT so RLS evaluates as auth.uid() = this user
    const userDb = createClient(
      Deno.env.get('SUPABASE_URL')      ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      {
        global: { headers: { Authorization: `Bearer ${token}` } },
        auth:   { persistSession: false },
      },
    );

    /* ── Token validation ─────────────────────────────────── */
    // Use userDb (anon key) to validate the JWT — avoids depending on SUPABASE_SERVICE_ROLE_KEY
    // being present for auth validation. userDb already has the JWT in its global headers,
    // so auth.getUser(token) sends: Authorization: Bearer {user_jwt} + apikey: {anon_key}.
    const { data: { user }, error: authErr } = await userDb.auth.getUser(token);

    if (authErr || !user) {
      const detail = authErr?.message ?? 'Token invalid or expired.';
      return new Response(
        JSON.stringify({
          error: `Unauthorized: ${detail}. Please refresh your session and try again.`,
        }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const userId = user.id;

    /* ── Seed UI defaults for new users (idempotent) ─────── */
    // In case the DB trigger didn't fire (e.g. user created before this migration).
    // The function uses ON CONFLICT DO NOTHING so it's safe to call every time.
    // We fire-and-forget — don't await to avoid slowing the response.
    adminDb.rpc('seed_default_ui_settings', { target_user_id: userId }).then(() => {}).catch(() => {});

    /* ── Direct tool-call mode (bypasses AI loop) ─────────── */
    if (body.tool_call) {
      const { name, input } = body.tool_call;
      const { result, refresh } = await runTool(name, input ?? {}, userId, adminDb, userDb);
      return new Response(
        JSON.stringify({ result, refresh, message: result }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    /* ── AI (Claude) mode ─────────────────────────────────── */
    const ANTHROPIC_API_KEY = Deno.env.get('ANTHROPIC_API_KEY');
    if (!ANTHROPIC_API_KEY) {
      return new Response(
        JSON.stringify({ error: 'ANTHROPIC_API_KEY not configured.' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const systemPrompt = `You are an AI assistant built into an Inventory Manager web app.
You are operating on behalf of user ${userId}.
Every tool call you make is automatically scoped to this user's data only via Row Level Security.
You cannot read or modify any other user's data.

Current context:
- Page: ${context.page ?? 'unknown'}
- Active table: ${context.tableName ?? 'none'}
- Items in context: ${inventory.length}

CAPABILITIES:

READ:
  list_categories  → see this user's inventory tabs
  get_items        → items in a table
  get_fields       → column definitions for a table

MANAGE INVENTORY:
  create_category  → create a new tab (ALWAYS include BOTH: fields[0] = name (text), fields[1] = quantity (number))
  rename_category  → rename or change icon
  delete_category  → permanently remove (confirm first!)
  add_field        → add a column
  remove_field     → remove a column (confirm first — deletes all data in that column!)
  rename_field     → rename a field's display label
  upsert_item      → add or update an item
  delete_item      → remove an item

APPEARANCE (set_ui_setting):
  theme_color (Flutter seed/primary color, hex e.g. "#ff6600"),
  theme_mode (Flutter: "light"/"dark"/"system"),
  bg_color, card_color, accent_color (web + Flutter custom overrides),
  primary_color_start/end, header_text_color, font_size_base,
  text_primary_color, text_secondary_color,
  item_card_bg, stats_bar_bg, low_stock_color,
  btn_add_bg, btn_edit_bg, btn_del_bg,
  card_radius, low_stock_threshold

LAYOUT (set_layout):
  search_position, stats_position,
  dashboard_sort, inventory_default_sort, inventory_default_sort_dir,
  dashboard_card_min_width, item_card_density

RULES:
- table_name must be lowercase snake_case.
- Always confirm with the user before deleting anything or removing a field.
- Be concise. Summarize what changed after each action.
- To navigate: say "navigate to inventory.html?table=TABLE_NAME"

CATEGORY CREATION RULES:
⚠️ MANDATORY: Every create_category call MUST include AT LEAST 2 fields. Missing either field is a bug.
- fields[0] MUST be the item identity/name field (field_type: "text", required: true). This is the card title. Example: { field_name: "name", display_name: "Name", field_type: "text", required: true }
- fields[1] MUST be the quantity field (field_type: "number", required: false). This is the stock count badge. Example: { field_name: "quantity", display_name: "Quantity", field_type: "number" }
- fields[2+] are any additional custom fields the user requests.
- NEVER omit fields[0] or fields[1]. A category with only one field is BROKEN.
- NEVER put a price, cost, type, unit, or any non-name field at position 0. Position 0 is always the human-readable item name.
- Always include a relevant emoji icon for the category.

DATA INSERTION RULES:
- ALWAYS call get_fields before upsert_item. Never guess field names.
- Use the exact field_name values from get_fields. Values must match field_type (number fields need numbers, text fields need strings).
- To insert multiple items: call upsert_item once per item separately. Do not batch multiple items in one call.

CRITICAL — WHEN INSERTING DATA (upsert_item), FIELD ROLE IS DETERMINED BY SORT_ORDER, NOT BY FIELD_NAME:
- This rule applies to data insertion only, NOT to category creation (see CATEGORY CREATION RULES above).
- The field with the LOWEST sort_order is ALWAYS the item's identity/name.
  Put the human-readable item name there, even if the field happens to be named "cost_per_unit", "type", "sku", etc.
- The field with the SECOND LOWEST sort_order is ALWAYS the quantity count.
  Put the numeric quantity there, even if the field happens to be named "type", "color", etc.
- All remaining fields (sort_order 2+): fill based on their semantic field_name and field_type.
- If you notice sort_order 0 is a number field type (not text), warn the user that this category was set up incorrectly and offer to recreate it with the right field order.`;

    const messages: Array<{ role: string; content: unknown }> = [
      { role: 'user', content: userMessage },
    ];

    let finalText  = '';
    let anyRefresh = false;
    let navigate: string | null = null;

    // Tool-use loop (up to 8 iterations)
    for (let i = 0; i < 8; i++) {
      const resp = await fetch('https://api.anthropic.com/v1/messages', {
        method: 'POST',
        headers: {
          'Content-Type':      'application/json',
          'x-api-key':         ANTHROPIC_API_KEY,
          'anthropic-version': '2023-06-01',
        },
        body: JSON.stringify({
          model:      'claude-haiku-4-5-20251001',
          max_tokens: 1500,
          system:     systemPrompt,
          tools,
          messages,
        }),
      });

      if (!resp.ok) {
        const errBody = await resp.text();
        finalText = `Claude API error ${resp.status}: ${errBody}`;
        break;
      }

      const claude = await resp.json();

      if (claude.error) {
        finalText = `Claude API error: ${claude.error.message}`;
        break;
      }

      if (claude.stop_reason === 'end_turn') {
        finalText = (claude.content as Array<{ type: string; text?: string }>)
          .filter(b => b.type === 'text')
          .map(b => b.text ?? '')
          .join('');

        // Extract navigation instruction if present
        const navMatch = finalText.match(
          /navigate(?:\s+to)?\s+["']?(inventory\.html\?table=[\w]+)["']?/i,
        );
        if (navMatch) navigate = navMatch[1];
        break;
      }

      if (claude.stop_reason === 'tool_use') {
        messages.push({ role: 'assistant', content: claude.content });

        const toolResults = [];
        for (const block of claude.content as Array<{ type: string; id: string; name: string; input: Record<string, unknown> }>) {
          if (block.type !== 'tool_use') continue;

          const { result, refresh } = await runTool(
            block.name,
            block.input ?? {},
            userId,
            adminDb,
            userDb,
          );

          if (refresh) anyRefresh = true;

          toolResults.push({
            type:        'tool_result',
            tool_use_id: block.id,
            content:     result,
          });
        }

        messages.push({ role: 'user', content: toolResults });
        continue;
      }

      // Unexpected stop reason
      finalText = (claude.content as Array<{ type: string; text?: string }>)
        ?.filter(b => b.type === 'text')
        .map(b => b.text ?? '')
        .join('') ?? 'Done.';
      break;
    }

    return new Response(
      JSON.stringify({
        content:  [{ type: 'text', text: finalText || 'Done.' }],
        message:  finalText || 'Done.',
        refresh:  anyRefresh,
        navigate,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );

  } catch (err) {
    const msg = (err as Error).message;
    console.error('smart-api error:', msg);
    return new Response(
      JSON.stringify({
        content: [{ type: 'text', text: `Server error: ${msg}` }],
        error: msg,
      }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});
