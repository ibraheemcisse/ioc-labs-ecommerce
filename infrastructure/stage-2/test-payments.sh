#!/bin/bash
# Test complete payment flow via API

API_URL="http://ioc-labs-alb-265805501.us-east-1.elb.amazonaws.com/api"

echo "=== Payment Flow Test ==="

# Step 1: Register user
echo -e "\n1. Creating test user..."
REGISTER_RESPONSE=$(curl -s -X POST $API_URL/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test-payment@example.com",
    "password": "TestPass123!",
    "full_name": "Payment Tester"
  }')

TOKEN=$(echo $REGISTER_RESPONSE | jq -r '.data.token')
echo "✓ User registered, token obtained"

# Step 2: Add products to cart
echo -e "\n2. Adding products to cart..."
curl -s -X POST $API_URL/cart \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"product_id": 1, "quantity": 2}' > /dev/null

curl -s -X POST $API_URL/cart \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"product_id": 5, "quantity": 1}' > /dev/null

CART=$(curl -s -X GET $API_URL/cart \
  -H "Authorization: Bearer $TOKEN")

CART_TOTAL=$(echo $CART | jq -r '.data.total')
ITEM_COUNT=$(echo $CART | jq -r '.data.items | length')
echo "✓ Cart created: $ITEM_COUNT items, total: \$$CART_TOTAL"

# Step 3: Create order
echo -e "\n3. Creating order..."
ORDER_RESPONSE=$(curl -s -X POST $API_URL/orders \
  -H "Authorization: Bearer $TOKEN")

ORDER_ID=$(echo $ORDER_RESPONSE | jq -r '.data.id')
ORDER_TOTAL=$(echo $ORDER_RESPONSE | jq -r '.data.total')
echo "✓ Order created: ID=$ORDER_ID, Total=\$$ORDER_TOTAL"

# Step 4: Create payment intent
echo -e "\n4. Creating Stripe payment intent..."
PAYMENT_RESPONSE=$(curl -s -X POST $API_URL/payment/create-intent \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"order_id\": $ORDER_ID}")

CLIENT_SECRET=$(echo $PAYMENT_RESPONSE | jq -r '.data.client_secret')
AMOUNT=$(echo $PAYMENT_RESPONSE | jq -r '.data.amount')
echo "✓ Payment intent created"
echo "  Client secret: ${CLIENT_SECRET:0:20}..."
echo "  Amount: \$$(echo "scale=2; $AMOUNT/100" | bc)"

# Step 5: Manual payment in browser
echo -e "\n5. Complete payment in browser:"
echo "  → Open: http://ioc-labs-alb-265805501.us-east-1.elb.amazonaws.com"
echo "  → Login as: test-payment@example.com / TestPass123!"
echo "  → Go to Orders tab"
echo "  → Click 'Pay Now' for Order #$ORDER_ID"
echo "  → Use card: 4242 4242 4242 4242"
echo "  → Expiry: 12/25, CVC: 123, ZIP: 12345"
echo ""
echo "Press Enter after completing payment..."
read

# Step 6: Verify payment status
echo -e "\n6. Verifying payment..."
sleep 5  # Wait for webhook processing

ORDER_STATUS=$(curl -s -X GET $API_URL/orders/$ORDER_ID \
  -H "Authorization: Bearer $TOKEN")

STATUS=$(echo $ORDER_STATUS | jq -r '.data.status')
PAYMENT_STATUS=$(echo $ORDER_STATUS | jq -r '.data.payment_status')

if [ "$STATUS" = "paid" ] && [ "$PAYMENT_STATUS" = "succeeded" ]; then
    echo "✓ Payment verified successfully!"
    echo "  Order status: $STATUS"
    echo "  Payment status: $PAYMENT_STATUS"
else
    echo "✗ Payment verification failed"
    echo "  Order status: $STATUS"
    echo "  Payment status: $PAYMENT_STATUS"
    exit 1
fi

echo -e "\n=== Test Complete ==="
