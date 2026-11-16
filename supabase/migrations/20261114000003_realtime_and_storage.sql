-- ============================================================================
-- CafeFlow Phase 03 Migration 03: Realtime Publications & Storage Policies
-- Version: 20261114000003
-- Scope: Supabase Realtime publication setup and menu-images storage bucket
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Supabase Realtime Publication Setup
-- ----------------------------------------------------------------------------
-- Configure REPLICA IDENTITY FULL so UPDATE/DELETE events broadcast previous values
ALTER TABLE orders REPLICA IDENTITY FULL;
ALTER TABLE order_items REPLICA IDENTITY FULL;
ALTER TABLE order_status_history REPLICA IDENTITY FULL;
ALTER TABLE menu_items REPLICA IDENTITY FULL;
ALTER TABLE dining_tables REPLICA IDENTITY FULL;
ALTER TABLE inventory_items REPLICA IDENTITY FULL;

-- Add operational tables to the supabase_realtime publication
DO $$ BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE orders;
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE order_items;
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE order_status_history;
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE menu_items;
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE dining_tables;
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE inventory_items;
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

-- ----------------------------------------------------------------------------
-- 2. Storage: menu-images Bucket & Storage RLS
-- ----------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'menu-images',
    'menu-images',
    true,
    5242880, -- 5 MB limit
    ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
ON CONFLICT (id) DO UPDATE SET
    public = true,
    file_size_limit = 5242880,
    allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif'];

-- Storage RLS Policies
CREATE POLICY "Public can view menu images"
    ON storage.objects FOR SELECT
    USING (bucket_id = 'menu-images');

CREATE POLICY "Authenticated staff and admins can upload menu images"
    ON storage.objects FOR INSERT
    TO authenticated
    WITH CHECK (
        bucket_id = 'menu-images' AND
        EXISTS (
            SELECT 1 FROM public.restaurant_memberships
            WHERE user_id = auth.uid()
              AND role IN ('OWNER'::public.app_role, 'ADMIN'::public.app_role)
              AND is_active = true
              AND deleted_at IS NULL
        )
    );

CREATE POLICY "Admins can update or delete menu images"
    ON storage.objects FOR ALL
    TO authenticated
    USING (
        bucket_id = 'menu-images' AND
        EXISTS (
            SELECT 1 FROM public.restaurant_memberships
            WHERE user_id = auth.uid()
              AND role IN ('OWNER'::public.app_role, 'ADMIN'::public.app_role)
              AND is_active = true
              AND deleted_at IS NULL
        )
    );

