-- ============================================================================
-- CafeFlow Phase 03 Deterministic Development Seed Data
-- ============================================================================

-- 1. Fictional Cafe Flagship Restaurant
INSERT INTO restaurants (id, name, slug, address, phone, email, is_active)
VALUES (
    'a0000000-0000-0000-0000-000000000001',
    'CafeFlow Flagship Bistro',
    'cafeflow-flagship',
    '12 Heritage Cross, 100ft Road, Indiranagar, Bengaluru, KA 560038',
    '+91 80 4912 8800',
    'flagship@cafeflow.local',
    true
) ON CONFLICT (id) DO NOTHING;

-- 2. Restaurant Settings
INSERT INTO restaurant_settings (id, restaurant_id, currency, gst_rate_basis_points, receipt_prefix, auto_accept_orders)
VALUES (
    'b0000000-0000-0000-0000-000000000001',
    'a0000000-0000-0000-0000-000000000001',
    'INR',
    500, -- 5.00% GST
    'ORD-',
    true
) ON CONFLICT (restaurant_id) DO NOTHING;

-- 3. Payment Methods
INSERT INTO payment_methods (id, restaurant_id, code, display_name, is_active)
VALUES
    ('c0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'CASH', 'Cash on Counter', true),
    ('c0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'UPI', 'UPI Instant QR', true),
    ('c0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'CARD', 'Credit / Debit Card', true)
ON CONFLICT (id) DO NOTHING;

-- 4. Menu Categories
INSERT INTO menu_categories (id, restaurant_id, name, display_order, is_active)
VALUES
    ('d0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'Coffee', 1, true),
    ('d0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'Bakery', 2, true),
    ('d0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'Mains', 3, true),
    ('d0000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000001', 'Refreshments', 4, true)
ON CONFLICT (id) DO NOTHING;

-- 5. Menu Items
INSERT INTO menu_items (id, restaurant_id, category_id, name, description, price_minor, is_available, is_featured)
VALUES
    ('e0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'Velvet Latte', 'Double shot single-origin arabica with velvety textured whole milk.', 24000, true, true),
    ('e0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'House Espresso', 'Intense and balanced double ristretto with notes of cocoa and dried fruit.', 18000, true, false),
    ('e0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'Cold Brew Reserve', '18-hour cold steeped micro-lot brew served over clear ice.', 26000, true, true),
    ('e0000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000002', 'Golden Croissant', 'Three-day laminated French-style cultured butter pastry baked golden brown.', 21000, true, true),
    ('e0000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000002', 'Cardamom Morning Bun', 'Spiced sourdough brioche rolled in raw demerara and cardamom.', 19000, true, false),
    ('e0000000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-000000000003', 'd0000000-0000-0000-0000-000000000003', 'Avocado Sourdough Toast', 'Hass avocado mash on toasted country sourdough with zaatar and radish.', 34000, true, true),
    ('e0000000-0000-0000-0000-000000000007', 'a0000000-0000-0000-0000-000000000004', 'd0000000-0000-0000-0000-000000000004', 'Wild Berry Kombucha', 'Naturally fermented effervescent green tea with blackcurrant & mint.', 22000, true, false)
ON CONFLICT (id) DO NOTHING;

-- 6. Dining Tables
INSERT INTO dining_tables (id, restaurant_id, table_number, capacity, status)
VALUES
    ('f0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'Table 01', 2, 'OCCUPIED'),
    ('f0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'Table 02', 4, 'AVAILABLE'),
    ('f0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'Table 03', 4, 'OCCUPIED'),
    ('f0000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000001', 'Table 04', 6, 'RESERVED'),
    ('f0000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000001', 'Table 05', 2, 'AVAILABLE'),
    ('f0000000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-000000000001', 'Table 06', 4, 'AVAILABLE')
ON CONFLICT (id) DO NOTHING;

-- 7. Customers
INSERT INTO customers (id, restaurant_id, name, phone, email, loyalty_tier, total_spend_minor, visits_count, favorite_item)
VALUES
    ('a1000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'Rohan Mehra', '+91 98450 12345', 'rohan@example.com', 'GOLD', 482000, 24, 'Velvet Latte'),
    ('a1000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'Ananya Deshmukh', '+91 98765 43210', 'ananya@example.com', 'SILVER', 294000, 15, 'Avocado Sourdough Toast'),
    ('a1000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'Vikram Seth', '+91 91234 56789', 'vikram@example.com', 'GUEST', 84000, 4, 'Cold Brew Reserve')
ON CONFLICT (id) DO NOTHING;

-- 8. Inventory Categories
INSERT INTO inventory_categories (id, restaurant_id, name)
VALUES
    ('b1000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'Coffee Beans'),
    ('b1000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'Dairy & Alternatives'),
    ('b1000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'Bakery Staples')
ON CONFLICT (id) DO NOTHING;

-- 9. Inventory Items
INSERT INTO inventory_items (id, restaurant_id, category_id, name, unit, current_stock, reorder_level, cost_per_unit_minor)
VALUES
    ('c1000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 'House Espresso Beans', 'kg', 3.2, 5.0, 95000),
    ('c1000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000002', 'Whole Milk (Organic)', 'liters', 14.0, 10.0, 7200),
    ('c1000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000002', 'Barista Oat Milk', 'liters', 4.5, 8.0, 19500),
    ('c1000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000003', 'French Cultured Butter', 'kg', 2.0, 4.0, 85000)
ON CONFLICT (id) DO NOTHING;
