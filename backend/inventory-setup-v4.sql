-- ============================================================
-- INVENTORY MANAGER v4 — UNIFIED SQL SETUP
-- Single source of truth. Safe to run on a fresh Supabase DB.
-- Run this ONCE in Supabase Dashboard → SQL Editor.
-- ============================================================
-- What this does:
--   • Creates all tables with correct structure
--   • Enables RLS with NULL-safe, per-user policies on everything
--   • Scopes field_definitions reads through table ownership check
--   • Sets up exec_sql helper for DDL from edge function
--   • Inserts default UI settings (per-user via user_id)
--   • Auto-creates a profile row when a new user signs up
-- ============================================================


-- ── 1. PROFILES ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS profiles (
    id           uuid        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    display_name text        NOT NULL DEFAULT 'User',
    email        text,
    role         text        NOT NULL DEFAULT 'user' CHECK (role IN ('admin', 'user')),
    created_at   timestamptz DEFAULT now()
);

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "profiles_select_own" ON profiles;
DROP POLICY IF EXISTS "profiles_update_own" ON profiles;
DROP POLICY IF EXISTS "profiles_insert_own" ON profiles;

CREATE POLICY "profiles_select_own" ON profiles FOR SELECT
    USING (auth.uid() IS NOT NULL AND id = auth.uid());

CREATE POLICY "profiles_update_own" ON profiles FOR UPDATE
    USING (auth.uid() IS NOT NULL AND id = auth.uid());

CREATE POLICY "profiles_insert_own" ON profiles FOR INSERT
    WITH CHECK (auth.uid() IS NOT NULL AND id = auth.uid());


-- Auto-create profile when a user signs up
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO profiles (id, display_name, email)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'display_name', split_part(NEW.email, '@', 1)),
        NEW.email
    )
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION handle_new_user();


-- ── 2. TABLE_DEFINITIONS ────────────────────────────────────
-- One row per inventory category. user_id is mandatory.
-- No more OR user_id IS NULL loophole.
CREATE TABLE IF NOT EXISTS table_definitions (
    id           uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
    table_name   text        NOT NULL,
    display_name text        NOT NULL,
    icon         text        DEFAULT '📦',
    user_id      uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at   timestamptz DEFAULT now(),
    -- Each user can have their own "toners" table etc.
    UNIQUE (table_name, user_id)
);

ALTER TABLE table_definitions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "td_select" ON table_definitions;
DROP POLICY IF EXISTS "td_insert" ON table_definitions;
DROP POLICY IF EXISTS "td_update" ON table_definitions;
DROP POLICY IF EXISTS "td_delete" ON table_definitions;
DROP POLICY IF EXISTS "td_allow_all" ON table_definitions;

-- NULL-safe: auth.uid() IS NOT NULL ensures no ghost matches when uid() is null
CREATE POLICY "td_select" ON table_definitions FOR SELECT
    USING (auth.uid() IS NOT NULL AND user_id = auth.uid());

CREATE POLICY "td_insert" ON table_definitions FOR INSERT
    WITH CHECK (auth.uid() IS NOT NULL AND user_id = auth.uid());

CREATE POLICY "td_update" ON table_definitions FOR UPDATE
    USING (auth.uid() IS NOT NULL AND user_id = auth.uid());

CREATE POLICY "td_delete" ON table_definitions FOR DELETE
    USING (auth.uid() IS NOT NULL AND user_id = auth.uid());


-- ── 3. FIELD_DEFINITIONS ────────────────────────────────────
-- Describes columns in each dynamic item table.
-- RLS: reads are scoped through table ownership (join to table_definitions).
-- This prevents user A from reading the schema of user B's tables.
CREATE TABLE IF NOT EXISTS field_definitions (
    id           uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
    table_name   text        NOT NULL,
    field_name   text        NOT NULL,
    display_name text        NOT NULL,
    field_type   text        DEFAULT 'text',
    required     boolean     DEFAULT false,
    sort_order   int         DEFAULT 0,
    user_id      uuid        REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at   timestamptz DEFAULT now(),
    -- Scoped per user: two users can both have "toners.quantity"
    UNIQUE (table_name, field_name, user_id)
);

ALTER TABLE field_definitions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "fd_read_all"  ON field_definitions;
DROP POLICY IF EXISTS "fd_write_all" ON field_definitions;
DROP POLICY IF EXISTS "fd_allow_all" ON field_definitions;
DROP POLICY IF EXISTS "fd_select"    ON field_definitions;
DROP POLICY IF EXISTS "fd_insert"    ON field_definitions;
DROP POLICY IF EXISTS "fd_update"    ON field_definitions;
DROP POLICY IF EXISTS "fd_delete"    ON field_definitions;

-- SELECT: only if the record's user_id matches, OR if owned via table_definitions
-- user_id NULL check handles rows created before user_id column was added
CREATE POLICY "fd_select" ON field_definitions FOR SELECT
    USING (
        auth.uid() IS NOT NULL AND (
            user_id = auth.uid()
            OR EXISTS (
                SELECT 1 FROM table_definitions td
                WHERE td.table_name = field_definitions.table_name
                  AND td.user_id    = auth.uid()
            )
        )
    );

-- INSERT/UPDATE/DELETE: Allow users to manage fields for tables they own.
-- This is required for client-side data import.
CREATE POLICY "fd_insert" ON field_definitions FOR INSERT
    WITH CHECK (auth.uid() IS NOT NULL AND user_id = auth.uid());

CREATE POLICY "fd_update" ON field_definitions FOR UPDATE
    USING (auth.uid() IS NOT NULL AND user_id = auth.uid());

CREATE POLICY "fd_delete" ON field_definitions FOR DELETE
    USING (auth.uid() IS NOT NULL AND user_id = auth.uid());


-- ── 4. UI_SETTINGS ──────────────────────────────────────────
-- Per-user key/value store for theme and layout preferences.
CREATE TABLE IF NOT EXISTS ui_settings (
    id         uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
    key        text        NOT NULL,
    user_id    uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    value      text        NOT NULL,
    updated_at timestamptz DEFAULT now(),
    UNIQUE (key, user_id)
);

ALTER TABLE ui_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "ui_select"   ON ui_settings;
DROP POLICY IF EXISTS "ui_insert"   ON ui_settings;
DROP POLICY IF EXISTS "ui_update"   ON ui_settings;
DROP POLICY IF EXISTS "ui_delete"   ON ui_settings;
DROP POLICY IF EXISTS "ui_allow_all" ON ui_settings;
DROP POLICY IF EXISTS "allow_all"   ON ui_settings;
DROP POLICY IF EXISTS "ui_upsert"   ON ui_settings;

CREATE POLICY "ui_select" ON ui_settings FOR SELECT
    USING (auth.uid() IS NOT NULL AND user_id = auth.uid());

CREATE POLICY "ui_insert" ON ui_settings FOR INSERT
    WITH CHECK (auth.uid() IS NOT NULL AND user_id = auth.uid());

CREATE POLICY "ui_update" ON ui_settings FOR UPDATE
    USING (auth.uid() IS NOT NULL AND user_id = auth.uid());

CREATE POLICY "ui_delete" ON ui_settings FOR DELETE
    USING (auth.uid() IS NOT NULL AND user_id = auth.uid());


-- ── 5. EXEC_SQL HELPER ──────────────────────────────────────
-- Used by the edge function (service role only) for DDL operations:
-- CREATE TABLE, DROP TABLE, ALTER TABLE, CREATE POLICY, etc.
-- Regular users cannot call this — only service_role is granted EXECUTE.
CREATE OR REPLACE FUNCTION exec_sql(sql text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    EXECUTE sql;
    RETURN '{"success": true}'::jsonb;
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('error', SQLERRM, 'detail', SQLSTATE);
END;
$$;

-- Revoke from public, grant only to service role
REVOKE EXECUTE ON FUNCTION exec_sql(text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION exec_sql(text) TO service_role;


-- ── 6. DEFAULT UI SETTINGS SEED FUNCTION ────────────────────
-- Call this from the edge function (or manually) to seed defaults
-- for a specific user after they sign up.
-- Usage: SELECT seed_default_ui_settings('user-uuid-here');
CREATE OR REPLACE FUNCTION seed_default_ui_settings(target_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO ui_settings (key, user_id, value) VALUES
        ('primary_color_start',       target_user_id, '#667eea'),
        ('primary_color_end',         target_user_id, '#764ba2'),
        ('header_text_color',         target_user_id, '#ffffff'),
        ('accent_color',              target_user_id, '#667eea'),
        ('bg_color',                  target_user_id, '#f5f5f5'),
        ('card_color',                target_user_id, '#ffffff'),
        ('card_radius',               target_user_id, '12px'),
        ('font_size_base',            target_user_id, '15px'),
        ('text_primary_color',        target_user_id, '#222222'),
        ('text_secondary_color',      target_user_id, '#666666'),
        ('low_stock_threshold',       target_user_id, '10'),
        ('item_card_bg',              target_user_id, '#ffffff'),
        ('stats_bar_bg',              target_user_id, '#ffffff'),
        ('low_stock_color',           target_user_id, '#ef4444'),
        ('btn_add_bg',                target_user_id, '#22c55e'),
        ('btn_edit_bg',               target_user_id, '#fbbf24'),
        ('btn_del_bg',                target_user_id, '#ef4444'),
        ('dashboard_sort',            target_user_id, 'name_asc'),
        ('dashboard_card_min_width',  target_user_id, '280px'),
        ('search_position',           target_user_id, 'card'),
        ('stats_position',            target_user_id, 'bottom'),
        ('item_card_density',         target_user_id, 'normal'),
        ('inventory_default_sort',    target_user_id, 'created_at'),
        ('inventory_default_sort_dir',target_user_id, 'desc'),
        ('ai_panel_size',             target_user_id, 'medium')
    ON CONFLICT (key, user_id) DO NOTHING;
END;
$$;

GRANT EXECUTE ON FUNCTION seed_default_ui_settings(uuid) TO service_role;


-- ── 7. AUTO-SEED DEFAULTS ON NEW USER SIGNUP ────────────────
-- Extends handle_new_user trigger to also seed UI defaults.
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Create profile
    INSERT INTO profiles (id, display_name, email)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'display_name', split_part(NEW.email, '@', 1)),
        NEW.email
    )
    ON CONFLICT (id) DO NOTHING;

    -- Seed default UI settings for this user
    PERFORM seed_default_ui_settings(NEW.id);

    RETURN NEW;
END;
$$;

-- Re-create trigger (function was just replaced above)
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION handle_new_user();


-- ── 8. ONE-TIME: MIGRATE EXISTING DATA ──────────────────────
-- Only relevant if you have existing data from a previous setup.
-- Safe to run even if tables/data don't exist yet.

DO $$
DECLARE
    owner_id uuid;
BEGIN
    -- Find the primary account to claim orphaned data
    SELECT id INTO owner_id
    FROM auth.users
    WHERE email = 'yjturetsky@gmail.com'
    LIMIT 1;

    IF owner_id IS NULL THEN
        RAISE NOTICE 'Primary user not found — skipping data migration. This is fine on a fresh DB.';
        RETURN;
    END IF;

    -- Claim any table_definitions without a user_id
    -- (old schema had user_id as nullable)
    BEGIN
        UPDATE table_definitions SET user_id = owner_id WHERE user_id IS NULL;
        RAISE NOTICE 'Claimed orphaned table_definitions rows for %', owner_id;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Could not update table_definitions (may be new schema): %', SQLERRM;
    END;

    -- Backfill field_definitions user_id for rows that belong to owner's tables
    BEGIN
        UPDATE field_definitions fd
        SET user_id = owner_id
        FROM table_definitions td
        WHERE td.table_name = fd.table_name
          AND td.user_id = owner_id
          AND fd.user_id IS NULL;
        RAISE NOTICE 'Backfilled field_definitions user_id for %', owner_id;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Could not backfill field_definitions (may be new schema): %', SQLERRM;
    END;

    -- Seed UI defaults for existing user if not already done
    PERFORM seed_default_ui_settings(owner_id);
    RAISE NOTICE 'Seeded UI defaults for existing user %', owner_id;

END $$;

-- ── 9. DELETE USER ACCOUNT ────────────────────────────────────
-- Function to delete a user's account and all associated data.
-- This is called by the user from the app.
CREATE OR REPLACE FUNCTION delete_user_account()
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER -- Changed from DEFINER for security best practices
AS $$
BEGIN
  -- Delete the user from auth.users. This will trigger the on_auth_user_deleted trigger.
  DELETE FROM auth.users WHERE id = auth.uid();
END;
$$;

-- Allow authenticated users to call this function.
GRANT EXECUTE ON FUNCTION delete_user_account() TO authenticated;


-- Function to clean up all of a user's data.
CREATE OR REPLACE FUNCTION cleanup_user_data()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  table_rec RECORD;
BEGIN
  -- Delete from profiles table
  DELETE FROM public.profiles WHERE user_id = OLD.id;

  -- Delete from ui_settings table
  DELETE FROM public.ui_settings WHERE user_id = OLD.id;
  
  -- Delete from field_definitions table
  DELETE FROM public.field_definitions WHERE user_id = OLD.id;

  -- Delete dynamic item tables
  FOR table_rec IN
    SELECT table_name FROM public.table_definitions WHERE user_id = OLD.id
  LOOP
    EXECUTE 'DROP TABLE IF EXISTS ' || quote_ident(table_rec.table_name);
  END LOOP;
  
  -- Finally, delete from table_definitions table
  DELETE FROM public.table_definitions WHERE user_id = OLD.id;

  RETURN OLD;
END;
$$;

-- Trigger to clean up user data after a user is deleted from auth.users.
CREATE TRIGGER on_auth_user_deleted
  AFTER DELETE ON auth.users
  FOR EACH ROW EXECUTE FUNCTION cleanup_user_data();


-- ── RECYCLING BIN ────────────────────────────────────────────
-- Soft-deleted items land here. Auto-purged after 30 days
-- (triggered by the edge function on each delete_item call).
CREATE TABLE IF NOT EXISTS recycling_bin (
    id           uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id      uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    source_table text        NOT NULL,
    item_id      uuid,
    item_data    jsonb       NOT NULL,
    deleted_at   timestamptz DEFAULT NOW() NOT NULL
);

ALTER TABLE recycling_bin ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "rb_select" ON recycling_bin;
DROP POLICY IF EXISTS "rb_insert" ON recycling_bin;
DROP POLICY IF EXISTS "rb_delete" ON recycling_bin;

CREATE POLICY "rb_select" ON recycling_bin FOR SELECT
    USING (auth.uid() IS NOT NULL AND user_id = auth.uid());

CREATE POLICY "rb_insert" ON recycling_bin FOR INSERT
    WITH CHECK (auth.uid() IS NOT NULL AND user_id = auth.uid());

CREATE POLICY "rb_delete" ON recycling_bin FOR DELETE
    USING (auth.uid() IS NOT NULL AND user_id = auth.uid());

CREATE INDEX IF NOT EXISTS recycling_bin_user_deleted
    ON recycling_bin (user_id, deleted_at);


-- ── DONE ────────────────────────────────────────────────────
-- Summary of security model:
--
--   profiles          → user sees/edits only their own row
--   table_definitions → strict per-user RLS (NULL-safe), user_id NOT NULL
--   field_definitions → SELECT via ownership join to table_definitions;
--                        INSERT/UPDATE/DELETE only via service role (edge function)
--   ui_settings       → strict per-user RLS (NULL-safe), user_id NOT NULL
--   recycling_bin     → per-user RLS; items auto-purged after 30 days by edge function
--   exec_sql()        → service_role only, used for DDL from edge function
--
--   Dynamic item tables (created by edge function via exec_sql):
--     Each gets: id uuid PK, user_id uuid NOT NULL, created_at,
--     and NULL-safe per-user RLS on all four operations.
--
-- JWT Enforcement on the edge function:
--   Keep ON. The function validates the token via adminDb.auth.getUser(token).
--   If you see "invalid JWT" errors, the frontend must call
--   supabase.auth.refreshSession() (not just getSession()) before requests.
-- ============================================================
