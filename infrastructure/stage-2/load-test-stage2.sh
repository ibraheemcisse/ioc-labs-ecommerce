#!/bin/bash

# Stage 2 Load Testing Suite
# Tests ALB + 2 EC2 + RDS + Redis with 50+ products

set -e

ALB_URL="http://ioc-labs-alb-265805501.us-east-1.elb.amazonaws.com"
RESULTS_DIR="load-test-results-stage2"

mkdir -p $RESULTS_DIR

echo "=========================================="
echo "Stage 2 Load Testing - Full E-Commerce"
echo "=========================================="
echo "Target: $ALB_URL"
echo "Architecture: ALB → 2x EC2 → RDS + Redis"
echo "Products: 50+"
echo ""

# Test 1: Baseline - Light Load
echo "Test 1: Baseline (100 concurrent, 10,000 requests)"
echo "--------------------------------------------------"
ab -n 10000 -c 100 -g $RESULTS_DIR/test1-baseline.tsv \
  $ALB_URL/api/products > $RESULTS_DIR/test1-baseline.txt 2>&1

BASELINE_RPS=$(grep "Requests per second" $RESULTS_DIR/test1-baseline.txt | awk '{print $4}')
BASELINE_MEAN=$(grep "Time per request.*mean" $RESULTS_DIR/test1-baseline.txt | head -1 | awk '{print $4}')
echo "✓ Baseline: $BASELINE_RPS req/sec, ${BASELINE_MEAN}ms mean"
echo ""
sleep 5

# Test 2: Stage 1's Pain Point (200 concurrent)
echo "Test 2: Stage 1 Pain Point (200 concurrent, 20,000 requests)"
echo "-------------------------------------------------------------"
ab -n 20000 -c 200 -g $RESULTS_DIR/test2-stage1-pain.tsv \
  $ALB_URL/api/products > $RESULTS_DIR/test2-stage1-pain.txt 2>&1

PAIN_RPS=$(grep "Requests per second" $RESULTS_DIR/test2-stage1-pain.txt | awk '{print $4}')
PAIN_MEAN=$(grep "Time per request.*mean" $RESULTS_DIR/test2-stage1-pain.txt | head -1 | awk '{print $4}')
PAIN_FAILED=$(grep "Failed requests" $RESULTS_DIR/test2-stage1-pain.txt | awk '{print $3}')
echo "✓ 200 concurrent: $PAIN_RPS req/sec, ${PAIN_MEAN}ms mean, $PAIN_FAILED failed"
echo ""
sleep 5

# Test 3: Stage 1's Breaking Point (500 concurrent)
echo "Test 3: Stage 1 Breaking Point (500 concurrent, 50,000 requests)"
echo "-----------------------------------------------------------------"
ab -n 50000 -c 500 -g $RESULTS_DIR/test3-stage1-break.tsv \
  $ALB_URL/api/products > $RESULTS_DIR/test3-stage1-break.txt 2>&1

BREAK_RPS=$(grep "Requests per second" $RESULTS_DIR/test3-stage1-break.txt | awk '{print $4}')
BREAK_MEAN=$(grep "Time per request.*mean" $RESULTS_DIR/test3-stage1-break.txt | head -1 | awk '{print $4}')
BREAK_FAILED=$(grep "Failed requests" $RESULTS_DIR/test3-stage1-break.txt | awk '{print $3}')
echo "✓ 500 concurrent: $BREAK_RPS req/sec, ${BREAK_MEAN}ms mean, $BREAK_FAILED failed"
echo ""
sleep 10

# Test 4: Push Further (1000 concurrent)
echo "Test 4: Stress Test (1000 concurrent, 100,000 requests)"
echo "--------------------------------------------------------"
ab -n 100000 -c 1000 -g $RESULTS_DIR/test4-stress.tsv \
  $ALB_URL/api/products > $RESULTS_DIR/test4-stress.txt 2>&1

STRESS_RPS=$(grep "Requests per second" $RESULTS_DIR/test4-stress.txt | awk '{print $4}')
STRESS_MEAN=$(grep "Time per request.*mean" $RESULTS_DIR/test4-stress.txt | head -1 | awk '{print $4}')
STRESS_FAILED=$(grep "Failed requests" $RESULTS_DIR/test4-stress.txt | awk '{print $3}')
echo "✓ 1000 concurrent: $STRESS_RPS req/sec, ${STRESS_MEAN}ms mean, $STRESS_FAILED failed"
echo ""
sleep 10

# Test 5: Database-Heavy (Category Search)
echo "Test 5: Database Query Test (Category filter, 500 concurrent)"
echo "--------------------------------------------------------------"
ab -n 50000 -c 500 -g $RESULTS_DIR/test5-db-query.tsv \
  "$ALB_URL/api/products?category=Electronics" > $RESULTS_DIR/test5-db-query.txt 2>&1

DB_RPS=$(grep "Requests per second" $RESULTS_DIR/test5-db-query.txt | awk '{print $4}')
DB_MEAN=$(grep "Time per request.*mean" $RESULTS_DIR/test5-db-query.txt | head -1 | awk '{print $4}')
echo "✓ Category filter: $DB_RPS req/sec, ${DB_MEAN}ms mean"
echo ""
sleep 10

# Test 6: Authenticated Endpoints (Cart operations)
echo "Test 6: Creating test user for authenticated tests..."
REGISTER_RESPONSE=$(curl -s -X POST $ALB_URL/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "loadtest@example.com",
    "password": "LoadTest123!",
    "full_name": "Load Tester"
  }')

TOKEN=$(echo $REGISTER_RESPONSE | jq -r '.data.token')

if [ "$TOKEN" != "null" ] && [ ! -z "$TOKEN" ]; then
  echo "✓ Test user created, testing authenticated endpoints"
  
  # Warm up - add item to cart
  curl -s -X POST $ALB_URL/api/cart \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"product_id": 1, "quantity": 1}' > /dev/null
  
  echo ""
  echo "Test 6a: Cart Read Operations (500 concurrent)"
  echo "-----------------------------------------------"
  ab -n 50000 -c 500 \
    -H "Authorization: Bearer $TOKEN" \
    -g $RESULTS_DIR/test6-cart.tsv \
    $ALB_URL/api/cart > $RESULTS_DIR/test6-cart.txt 2>&1
  
  CART_RPS=$(grep "Requests per second" $RESULTS_DIR/test6-cart.txt | awk '{print $4}')
  CART_MEAN=$(grep "Time per request.*mean" $RESULTS_DIR/test6-cart.txt | head -1 | awk '{print $4}')
  echo "✓ Cart operations: $CART_RPS req/sec, ${CART_MEAN}ms mean"
else
  echo "⚠ Skipping authenticated tests (couldn't create user)"
fi

echo ""
sleep 5

# Test 7: Sustained Load (10 minutes)
echo "Test 7: Sustained Load Test (300 concurrent for 10 minutes)"
echo "------------------------------------------------------------"
echo "This simulates real-world sustained traffic..."

timeout 600 ab -t 600 -c 300 -g $RESULTS_DIR/test7-sustained.tsv \
  $ALB_URL/api/products > $RESULTS_DIR/test7-sustained.txt 2>&1 || true

SUSTAINED_RPS=$(grep "Requests per second" $RESULTS_DIR/test7-sustained.txt | awk '{print $4}')
SUSTAINED_TOTAL=$(grep "Complete requests" $RESULTS_DIR/test7-sustained.txt | awk '{print $3}')
echo "✓ Sustained: $SUSTAINED_RPS req/sec over 10 minutes ($SUSTAINED_TOTAL total requests)"
echo ""

# Generate Summary Report
echo "=========================================="
echo "Load Test Summary - Stage 2"
echo "=========================================="
echo ""

cat > $RESULTS_DIR/summary.txt << EOF
Stage 2 Load Test Results
Generated: $(date)
Target: $ALB_URL
Architecture: ALB + 2x t2.small EC2 + RDS PostgreSQL + ElastiCache Redis
Products: 50+

Test Results:
-------------
1. Baseline (100c)       : $BASELINE_RPS req/sec, ${BASELINE_MEAN}ms mean
2. 200 concurrent        : $PAIN_RPS req/sec, ${PAIN_MEAN}ms mean, $PAIN_FAILED failed
3. 500 concurrent        : $BREAK_RPS req/sec, ${BREAK_MEAN}ms mean, $BREAK_FAILED failed
4. 1000 concurrent       : $STRESS_RPS req/sec, ${STRESS_MEAN}ms mean, $STRESS_FAILED failed
5. Database queries      : $DB_RPS req/sec, ${DB_MEAN}ms mean
6. Cart operations       : $CART_RPS req/sec, ${CART_MEAN}ms mean
7. Sustained (10min)     : $SUSTAINED_RPS req/sec, $SUSTAINED_TOTAL total requests

Performance Analysis:
--------------------
EOF

# Calculate Stage 1 vs Stage 2 comparison
echo "Comparing with Stage 1 (if data available)..."
if [ -f "../load-test-results-stage1/test2-stage1-pain.txt" ]; then
  STAGE1_200C=$(grep "Requests per second" ../load-test-results-stage1/test2-stage1-pain.txt | awk '{print $4}')
  IMPROVEMENT=$(echo "scale=1; ($PAIN_RPS - $STAGE1_200C) / $STAGE1_200C * 100" | bc)
  
  cat >> $RESULTS_DIR/summary.txt << EOF

Stage 1 vs Stage 2 Comparison:
------------------------------
200 concurrent load:
  Stage 1: $STAGE1_200C req/sec
  Stage 2: $PAIN_RPS req/sec
  Improvement: ${IMPROVEMENT}%

Key Improvements:
- Load distributed across 2 instances
- Better handling of connection spikes
- Database connection pooling with RDS
- Redis caching reduces database load
EOF
else
  cat >> $RESULTS_DIR/summary.txt << EOF

Stage 1 comparison data not available.
Run Stage 1 tests for comparison.
EOF
fi

# Performance thresholds
cat >> $RESULTS_DIR/summary.txt << EOF

Performance Goals Met:
---------------------
EOF

if (( $(echo "$PAIN_RPS > 100" | bc -l) )); then
  echo "✓ 200 concurrent > 100 req/sec" >> $RESULTS_DIR/summary.txt
else
  echo "✗ 200 concurrent < 100 req/sec (target: >100)" >> $RESULTS_DIR/summary.txt
fi

if [ "$PAIN_FAILED" = "0" ]; then
  echo "✓ Zero failed requests at 200 concurrent" >> $RESULTS_DIR/summary.txt
else
  echo "✗ $PAIN_FAILED failed requests (target: 0)" >> $RESULTS_DIR/summary.txt
fi

if (( $(echo "$PAIN_MEAN < 2000" | bc -l) )); then
  echo "✓ Mean response time < 2000ms" >> $RESULTS_DIR/summary.txt
else
  echo "✗ Mean response time > 2000ms (target: <2000ms)" >> $RESULTS_DIR/summary.txt
fi

# Display summary
cat $RESULTS_DIR/summary.txt
echo ""

# Check CloudWatch metrics
echo "=========================================="
echo "Checking AWS Resource Utilization"
echo "=========================================="
echo ""
echo "To view detailed metrics, run:"
echo ""
echo "# EC2 CPU utilization"
echo "aws cloudwatch get-metric-statistics \\"
echo "  --namespace AWS/EC2 \\"
echo "  --metric-name CPUUtilization \\"
echo "  --dimensions Name=InstanceId,Value=i-05b8c18cb22aa6110 \\"
echo "  --start-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%S) \\"
echo "  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \\"
echo "  --period 300 \\"
echo "  --statistics Average,Maximum"
echo ""
echo "# ALB request count"
echo "aws cloudwatch get-metric-statistics \\"
echo "  --namespace AWS/ApplicationELB \\"
echo "  --metric-name RequestCount \\"
echo "  --dimensions Name=LoadBalancer,Value=app/ioc-labs-alb/... \\"
echo "  --start-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%S) \\"
echo "  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \\"
echo "  --period 300 \\"
echo "  --statistics Sum"
echo ""

echo "=========================================="
echo "Load Test Complete!"
echo "=========================================="
echo "Results saved to: $RESULTS_DIR/"
echo ""
echo "Key Files:"
echo "  - summary.txt       : Overall results"
echo "  - test*.txt         : Detailed ApacheBench output"
echo "  - test*.tsv         : Raw timing data (for graphing)"
echo ""
echo "Next Steps:"
echo "1. Review summary.txt for performance analysis"
echo "2. Check AWS CloudWatch for resource utilization"
echo "3. If needed, scale to 3-4 instances for higher load"
echo "4. Consider adding CDN for static assets"
echo "=========================================="
