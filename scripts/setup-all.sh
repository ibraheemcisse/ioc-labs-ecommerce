#!/bin/bash
set -e
source .env

echo "🔧 IOC Labs - Complete Setup"

# Create database
echo "📊 Creating database..."
sudo -u postgres psql -c "CREATE DATABASE $DATABASE_NAME;" 2>/dev/null || echo "Database exists"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DATABASE_NAME TO $DATABASE_USER;" 2>/dev/null

# Run migrations
echo "🔄 Running migrations..."
for migration in migrations/*.sql; do
    PGPASSWORD=$DATABASE_PASSWORD psql -h $DATABASE_HOST -U $DATABASE_USER -d $DATABASE_NAME -f $migration
done

# Seed database
echo "🌱 Seeding database..."
PGPASSWORD=$DATABASE_PASSWORD psql -h $DATABASE_HOST -U $DATABASE_USER -d $DATABASE_NAME << 'SQL'
INSERT INTO users (email, password_hash, first_name, last_name) 
VALUES ('admin@ioclabs.com', '$2a$10$rHw.8PvFJ9pJZqFqK8L7XeYkN3lQxF4gqVJ7kK6GxN8PFqJ7.8PvF', 'Admin', 'IOC Labs')
ON CONFLICT (email) DO NOTHING;

INSERT INTO products (name, description, price, category, stock, image_url) VALUES
('Premium Wireless Mouse', 'Ergonomic wireless mouse with precision tracking.', 29.99, 'Electronics', 150, 'https://images.unsplash.com/photo-1527864550417-7fd91fc51a46?w=400'),
('Classic Cotton T-Shirt', '100% premium cotton t-shirt.', 19.99, 'Clothing', 200, 'https://images.unsplash.com/photo-1521572163474-6864f9cf17ab?w=400'),
('Wireless Keyboard', 'Sleek wireless keyboard.', 49.99, 'Electronics', 100, 'https://images.unsplash.com/photo-1587829741301-dc798b83add3?w=400'),
('Designer Hoodie', 'Premium quality hoodie.', 59.99, 'Clothing', 80, 'https://images.unsplash.com/photo-1556821840-3a63f95609a7?w=400')
ON CONFLICT DO NOTHING;
SQL

echo "✅ Setup complete!"
echo ""
echo "Default credentials:"
echo "  Email: admin@ioclabs.com"
echo "  Password: Admin123!"
