-- Performance indexes for IOC Labs E-Commerce

-- Products table indexes
CREATE INDEX IF NOT EXISTS idx_products_category ON products(category);
CREATE INDEX IF NOT EXISTS idx_products_price ON products(price);
CREATE INDEX IF NOT EXISTS idx_products_stock ON products(stock);
CREATE INDEX IF NOT EXISTS idx_products_created_at ON products(created_at);

-- Users table indexes
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);

-- Cart items indexes
CREATE INDEX IF NOT EXISTS idx_cart_items_cart_id ON cart_items(cart_id);
CREATE INDEX IF NOT EXISTS idx_cart_items_product_id ON cart_items(product_id);
-- REMOVED: user_id doesn't exist in cart_items, using cart_id instead
CREATE INDEX IF NOT EXISTS idx_cart_items_cart_product ON cart_items(cart_id, product_id);

-- Orders table indexes
CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON orders(created_at);
CREATE INDEX IF NOT EXISTS idx_orders_user_status ON orders(user_id, status);

-- Order items indexes
CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_product_id ON order_items(product_id);

-- Composite indexes for common queries
CREATE INDEX IF NOT EXISTS idx_products_category_stock ON products(category, stock) WHERE stock > 0;

-- Analyze tables for query optimization
ANALYZE users;
ANALYZE products;
ANALYZE carts;
ANALYZE cart_items;
ANALYZE orders;
ANALYZE order_items;
