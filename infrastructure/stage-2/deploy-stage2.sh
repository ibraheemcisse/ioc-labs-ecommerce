#!/bin/bash
set -e

# Stage 2 E-Commerce Deployment Script
# Deploys products, Stripe integration, and updates to both EC2 instances

echo "=========================================="
echo "Stage 2 E-Commerce Deployment"
echo "=========================================="

# Configuration
INSTANCE1_IP="34.236.154.95"
INSTANCE2_IP="54.144.251.194"
KEY_PATH="/home/ibra/omega/ioc-labs-ecommerce/ioc-labs-key.pem"
RDS_HOST="ioc-labs-db.c85gyeucovob.us-east-1.rds.amazonaws.com"
DB_USER="iocadmin"
DB_NAME="ioc_labs_prod"
DB_PASS="SecurePass123Change!"

# Step 1: Build application locally
echo ""
echo "Step 1: Building application..."
cd ~/omega/ioc-labs-ecommerce
GOOS=linux GOARCH=amd64 go build -o ioc-labs-server cmd/api/main.go
if [ $? -eq 0 ]; then
    echo "✓ Build successful"
else
    echo "✗ Build failed"
    exit 1
fi

# Step 2: Seed 50+ products to database
echo ""
echo "Step 2: Seeding products to RDS..."
PGPASSWORD="$DB_PASS" psql -h "$RDS_HOST" -U "$DB_USER" -d "$DB_NAME" -f scripts/seed-50-products.sql
if [ $? -eq 0 ]; then
    echo "✓ 50 products seeded successfully"
else
    echo "✗ Product seeding failed"
    exit 1
fi

# Step 3: Apply payment migrations
echo ""
echo "Step 3: Applying payment table migrations..."
PGPASSWORD="$DB_PASS" psql -h "$RDS_HOST" -U "$DB_USER" -d "$DB_NAME" -f migrations/006_add_payment_fields.sql
if [ $? -eq 0 ]; then
    echo "✓ Payment fields added to orders table"
else
    echo "✗ Migration failed"
    exit 1
fi

# Step 4: Deploy to Instance 1
echo ""
echo "Step 4: Deploying to Instance 1 ($INSTANCE1_IP)..."

# Upload binary
scp -i "$KEY_PATH" ioc-labs-server ubuntu@$INSTANCE1_IP:~/ioc-labs-ecommerce/
echo "  ✓ Binary uploaded"

# Upload frontend
scp -i "$KEY_PATH" frontend/index.html ubuntu@$INSTANCE1_IP:~/ioc-labs-ecommerce/frontend/
echo "  ✓ Frontend uploaded"

# Update .env with Stripe keys
ssh -i "$KEY_PATH" ubuntu@$INSTANCE1_IP << 'ENDSSH'
cd ~/ioc-labs-ecommerce
# Add Stripe keys if not present
if ! grep -q "STRIPE_SECRET_KEY" .env; then
    echo "" >> .env
    echo "# Stripe Configuration (Test Mode)" >> .env
    echo "STRIPE_SECRET_KEY=sk_test_51QGET_YOUR_KEY_FROM_STRIPE" >> .env
    echo "STRIPE_PUBLISHABLE_KEY=pk_test_51QGET_YOUR_KEY_FROM_STRIPE" >> .env
fi
ENDSSH
echo "  ✓ Environment configured"

# Restart service
ssh -i "$KEY_PATH" ubuntu@$INSTANCE1_IP "sudo systemctl restart ioc-labs"
sleep 3
ssh -i "$KEY_PATH" ubuntu@$INSTANCE1_IP "sudo systemctl status ioc-labs | grep Active"
echo "  ✓ Service restarted"

# Step 5: Deploy to Instance 2
echo ""
echo "Step 5: Deploying to Instance 2 ($INSTANCE2_IP)..."

scp -i "$KEY_PATH" ioc-labs-server ubuntu@$INSTANCE2_IP:~/ioc-labs-ecommerce/
echo "  ✓ Binary uploaded"

scp -i "$KEY_PATH" frontend/index.html ubuntu@$INSTANCE2_IP:~/ioc-labs-ecommerce/frontend/
echo "  ✓ Frontend uploaded"

ssh -i "$KEY_PATH" ubuntu@$INSTANCE2_IP << 'ENDSSH'
cd ~/ioc-labs-ecommerce
if ! grep -q "STRIPE_SECRET_KEY" .env; then
    echo "" >> .env
    echo "# Stripe Configuration (Test Mode)" >> .env
    echo "STRIPE_SECRET_KEY=sk_test_51QGET_YOUR_KEY_FROM_STRIPE" >> .env
    echo "STRIPE_PUBLISHABLE_KEY=pk_test_51QGET_YOUR_KEY_FROM_STRIPE" >> .env
fi
ENDSSH
echo "  ✓ Environment configured"

ssh -i "$KEY_PATH" ubuntu@$INSTANCE2_IP "sudo systemctl restart ioc-labs"
sleep 3
ssh -i "$KEY_PATH" ubuntu@$INSTANCE2_IP "sudo systemctl status ioc-labs | grep Active"
echo "  ✓ Service restarted"

# Step 6: Verify deployment
echo ""
echo "Step 6: Verifying deployment..."
ALB_URL="http://ioc-labs-alb-265805501.us-east-1.elb.amazonaws.com"

# Test products endpoint
PRODUCTS_COUNT=$(curl -s "$ALB_URL/api/products" | jq '.data | length')
echo "  Products available: $PRODUCTS_COUNT"

if [ "$PRODUCTS_COUNT" -ge 50 ]; then
    echo "  ✓ Products loaded successfully"
else
    echo "  ⚠ Warning: Expected 50+ products, found $PRODUCTS_COUNT"
fi

# Test health endpoint
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$ALB_URL/api/health")
if [ "$HTTP_CODE" -eq 200 ]; then
    echo "  ✓ Health check passed"
else
    echo "  ✗ Health check failed (HTTP $HTTP_CODE)"
fi

echo ""
echo "=========================================="
echo "Deployment Summary"
echo "=========================================="
echo "Application: http://ioc-labs-alb-265805501.us-east-1.elb.amazonaws.com"
echo "Products seeded: 50+"
echo "Instances updated: 2"
echo "Status: READY FOR TESTING"
echo ""
echo "Next steps:"
echo "1. Get Stripe keys: https://dashboard.stripe.com/test/apikeys"
echo "2. Update .env files on both instances with actual Stripe keys"
echo "3. Test payment flow with card: 4242 4242 4242 4242"
echo "=========================================="
