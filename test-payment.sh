#!/bin/bash
API_URL="http://ioc-labs-alb-265805501.us-east-1.elb.amazonaws.com/api"

echo "=== Payment Flow Test ==="

# 1. Register
echo "Registering user..."
REGISTER=$(curl -s -X POST $API_URL/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email": "test'$(date +%s)'@example.com", "password": "Test123!", "full_name": "Tester"}')

TOKEN=$(echo $REGISTER | jq -r '.data.token')

if [ "$TOKEN" = "null" ]; then
  echo "Registration failed:"
  echo $REGISTER | jq '.'
  exit 1
fi

echo "✓ Registered, token: ${TOKEN:0:20}..."

# 2. Add to cart
echo "Adding to cart..."
curl -s -X POST $API_URL/cart \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"product_id": 1, "quantity": 2}' > /dev/null

# 3. Create order
echo "Creating order..."
ORDER=$(curl -s -X POST $API_URL/orders -H "Authorization: Bearer $TOKEN")
ORDER_ID=$(echo $ORDER | jq -r '.data.id')
TOTAL=$(echo $ORDER | jq -r '.data.total')
echo "✓ Order #$ORDER_ID created, total: \$$TOTAL"

# 4. Create payment intent
echo "Creating payment intent..."
PAYMENT=$(curl -s -X POST $API_URL/payment/create-intent \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"order_id\": $ORDER_ID}")

CLIENT_SECRET=$(echo $PAYMENT | jq -r '.data.client_secret')

if [ "$CLIENT_SECRET" = "null" ]; then
  echo "Payment intent failed:"
  echo $PAYMENT | jq '.'
  exit 1
fi

echo "✓ Payment intent created"
echo ""
echo "=== Test Complete ==="
echo "Order ID: $ORDER_ID"
echo "Status: pending"
echo ""
echo "Next: Test webhook in Stripe Dashboard"
echo "1. Go to: https://dashboard.stripe.com/test/webhooks"
echo "2. Click your webhook"
echo "3. Send test 'payment_intent.succeeded' event"
echo "4. Check order status:"
echo "   curl $API_URL/orders/$ORDER_ID -H 'Authorization: Bearer $TOKEN' | jq '.data.payment_status'"
