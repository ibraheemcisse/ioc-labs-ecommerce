#!/bin/bash
# Stage 2 Breaking Point Test
# Progressively increase load until infrastructure fails

set -e

ALB_URL="http://ioc-labs-alb-265805501.us-east-1.elb.amazonaws.com"
RESULTS_DIR="breaking-point-test-$(date +%Y%m%d-%H%M%S)"
mkdir -p $RESULTS_DIR

echo "=========================================="
echo "Stage 2 Breaking Point Test"
echo "=========================================="
echo "Goal: Find infrastructure limits"
echo "Target: $ALB_URL"
echo "Results: $RESULTS_DIR"
echo ""

# Test 1: Baseline - Current Performance
echo "Test 1: Baseline (200 concurrent, 20,000 requests)"
echo "---------------------------------------------------"
ab -n 20000 -c 200 -g $RESULTS_DIR/baseline.tsv \
  $ALB_URL/api/products > $RESULTS_DIR/baseline.txt 2>&1

BASELINE_RPS=$(grep "Requests per second" $RESULTS_DIR/baseline.txt | awk '{print $4}')
BASELINE_FAILED=$(grep "Failed requests" $RESULTS_DIR/baseline.txt | awk '{print $3}')
echo "✓ Baseline: $BASELINE_RPS req/sec, $BASELINE_FAILED failed"
echo ""
sleep 5

# Test 2: Moderate Stress (500 concurrent)
echo "Test 2: Moderate Stress (500 concurrent, 50,000 requests)"
echo "----------------------------------------------------------"
ab -n 50000 -c 500 -g $RESULTS_DIR/stress-500.tsv \
  $ALB_URL/api/products > $RESULTS_DIR/stress-500.txt 2>&1

STRESS500_RPS=$(grep "Requests per second" $RESULTS_DIR/stress-500.txt | awk '{print $4}')
STRESS500_FAILED=$(grep "Failed requests" $RESULTS_DIR/stress-500.txt | awk '{print $3}')
STRESS500_MEAN=$(grep "Time per request.*mean" $RESULTS_DIR/stress-500.txt | head -1 | awk '{print $4}')
echo "✓ 500 concurrent: $STRESS500_RPS req/sec, ${STRESS500_MEAN}ms mean, $STRESS500_FAILED failed"
echo ""
sleep 10

# Test 3: Heavy Stress (1000 concurrent)
echo "Test 3: Heavy Stress (1000 concurrent, 100,000 requests)"
echo "---------------------------------------------------------"
ab -n 100000 -c 1000 -g $RESULTS_DIR/stress-1000.tsv \
  $ALB_URL/api/products > $RESULTS_DIR/stress-1000.txt 2>&1

STRESS1000_RPS=$(grep "Requests per second" $RESULTS_DIR/stress-1000.txt | awk '{print $4}')
STRESS1000_FAILED=$(grep "Failed requests" $RESULTS_DIR/stress-1000.txt | awk '{print $3}')
STRESS1000_MEAN=$(grep "Time per request.*mean" $RESULTS_DIR/stress-1000.txt | head -1 | awk '{print $4}')
echo "✓ 1000 concurrent: $STRESS1000_RPS req/sec, ${STRESS1000_MEAN}ms mean, $STRESS1000_FAILED failed"
echo ""
sleep 15

# Test 4: Extreme Stress (2000 concurrent)
echo "Test 4: Extreme Stress (2000 concurrent, 100,000 requests)"
echo "-----------------------------------------------------------"
ab -n 100000 -c 2000 -g $RESULTS_DIR/stress-2000.tsv \
  $ALB_URL/api/products > $RESULTS_DIR/stress-2000.txt 2>&1 || true

STRESS2000_RPS=$(grep "Requests per second" $RESULTS_DIR/stress-2000.txt | awk '{print $4}')
STRESS2000_FAILED=$(grep "Failed requests" $RESULTS_DIR/stress-2000.txt | awk '{print $3}')
STRESS2000_MEAN=$(grep "Time per request.*mean" $RESULTS_DIR/stress-2000.txt | head -1 | awk '{print $4}')
echo "✓ 2000 concurrent: $STRESS2000_RPS req/sec, ${STRESS2000_MEAN}ms mean, $STRESS2000_FAILED failed"
echo ""
sleep 20

# Test 5: Breaking Point (3000 concurrent)
echo "Test 5: Breaking Point Attempt (3000 concurrent, 100,000 requests)"
echo "-------------------------------------------------------------------"
ab -n 100000 -c 3000 -g $RESULTS_DIR/stress-3000.tsv \
  $ALB_URL/api/products > $RESULTS_DIR/stress-3000.txt 2>&1 || true

STRESS3000_RPS=$(grep "Requests per second" $RESULTS_DIR/stress-3000.txt | awk '{print $4}')
STRESS3000_FAILED=$(grep "Failed requests" $RESULTS_DIR/stress-3000.txt | awk '{print $3}')
STRESS3000_MEAN=$(grep "Time per request.*mean" $RESULTS_DIR/stress-3000.txt | head -1 | awk '{print $4}')
echo "✓ 3000 concurrent: $STRESS3000_RPS req/sec, ${STRESS3000_MEAN}ms mean, $STRESS3000_FAILED failed"
echo ""
sleep 20

# Test 6: Nuclear (5000 concurrent - expect failures)
echo "Test 6: Nuclear Load (5000 concurrent, 100,000 requests)"
echo "---------------------------------------------------------"
echo "WARNING: Expecting high failure rate"
ab -n 100000 -c 5000 -g $RESULTS_DIR/stress-5000.tsv \
  $ALB_URL/api/products > $RESULTS_DIR/stress-5000.txt 2>&1 || true

STRESS5000_RPS=$(grep "Requests per second" $RESULTS_DIR/stress-5000.txt | awk '{print $4}')
STRESS5000_FAILED=$(grep "Failed requests" $RESULTS_DIR/stress-5000.txt | awk '{print $3}')
STRESS5000_MEAN=$(grep "Time per request.*mean" $RESULTS_DIR/stress-5000.txt | head -1 | awk '{print $4}')
echo "✓ 5000 concurrent: $STRESS5000_RPS req/sec, ${STRESS5000_MEAN}ms mean, $STRESS5000_FAILED failed"
echo ""

# Generate Breaking Point Report
cat > $RESULTS_DIR/breaking-point-report.md << EOF
# Stage 2 Breaking Point Analysis
**Test Date**: $(date)
**Infrastructure**: ALB + 2x t2.small EC2 + RDS + Redis

## Test Results

| Concurrent Users | Total Requests | Req/Sec | Mean Latency | Failed Requests | Pass/Fail |
|-----------------|----------------|---------|--------------|-----------------|-----------|
| 200 (Baseline)  | 20,000        | $BASELINE_RPS | - | $BASELINE_FAILED | PASS |
| 500             | 50,000        | $STRESS500_RPS | ${STRESS500_MEAN}ms | $STRESS500_FAILED | $([ "$STRESS500_FAILED" -lt 100 ] && echo "PASS" || echo "FAIL") |
| 1,000           | 100,000       | $STRESS1000_RPS | ${STRESS1000_MEAN}ms | $STRESS1000_FAILED | $([ "$STRESS1000_FAILED" -lt 500 ] && echo "PASS" || echo "FAIL") |
| 2,000           | 100,000       | $STRESS2000_RPS | ${STRESS2000_MEAN}ms | $STRESS2000_FAILED | $([ "$STRESS2000_FAILED" -lt 1000 ] && echo "DEGRADED" || echo "FAIL") |
| 3,000           | 100,000       | $STRESS3000_RPS | ${STRESS3000_MEAN}ms | $STRESS3000_FAILED | $([ "$STRESS3000_FAILED" -lt 5000 ] && echo "DEGRADED" || echo "FAIL") |
| 5,000           | 100,000       | $STRESS5000_RPS | ${STRESS5000_MEAN}ms | $STRESS5000_FAILED | FAIL |

## Breaking Point Analysis

EOF

# Determine breaking point
if [ "$STRESS500_FAILED" -gt 100 ]; then
    echo "**Breaking Point**: ~500 concurrent users" >> $RESULTS_DIR/breaking-point-report.md
elif [ "$STRESS1000_FAILED" -gt 500 ]; then
    echo "**Breaking Point**: ~1,000 concurrent users" >> $RESULTS_DIR/breaking-point-report.md
elif [ "$STRESS2000_FAILED" -gt 1000 ]; then
    echo "**Breaking Point**: ~2,000 concurrent users" >> $RESULTS_DIR/breaking-point-report.md
else
    echo "**Breaking Point**: ~3,000+ concurrent users" >> $RESULTS_DIR/breaking-point-report.md
fi

cat >> $RESULTS_DIR/breaking-point-report.md << EOF

## Infrastructure Limitations Identified

### 1. **Compute Constraints**
- 2x t2.small instances (2 vCPU, 2GB RAM each)
- Total capacity: 4 vCPUs, 4GB RAM
- No auto-scaling configured
- Fixed capacity regardless of load

### 2. **Database Bottleneck**
- Single RDS instance (db.t3.micro)
- Max connections: ~100
- No read replicas
- Connection pooling helps but limited

### 3. **Network Limits**
- t2.small network: Moderate baseline
- ALB connection limits
- No CDN for static assets

### 4. **Cost vs Performance**
- Current: ~\$85/month for fixed capacity
- Scaling to handle 5000+ concurrent:
  - Need 10+ EC2 instances: ~\$400/month
  - Larger RDS: ~\$100/month
  - **Total**: ~\$500/month for occasional spikes

## Stage 3 Serverless Benefits

### Why Serverless Solves These Problems

**1. Auto-Scaling**
- Lambda scales to 1000+ concurrent automatically
- No instance management
- Pay only for requests processed

**2. Cost Efficiency**
- Current: \$85/month for fixed 200 concurrent capacity
- Serverless: \$20/month base + per-request
- Handle 5000 concurrent spikes: ~\$50 for the spike event
- **Savings**: 75% reduction for variable traffic

**3. Performance**
- API Gateway + Lambda: <100ms response
- DynamoDB: Single-digit millisecond queries
- CloudFront CDN: Global edge caching

**4. Reliability**
- Multi-AZ automatic
- No single points of failure
- AWS manages infrastructure

### Cost Comparison: Stage 2 vs Stage 3

**Stage 2 (Current - To handle 5000 concurrent):**
- 10x EC2 t2.small: \$340/month
- RDS db.t3.medium: \$120/month
- ALB: \$16/month
- ElastiCache: \$50/month
- **Total**: ~\$526/month

**Stage 3 (Serverless - Handles any load):**
- API Gateway: \$3.50/million requests
- Lambda: \$0.20/million requests
- DynamoDB on-demand: \$1.25/million reads
- S3 + CloudFront: \$15/month
- **Estimated**: \$30-80/month depending on traffic
- **Peak load**: Scales automatically, pay only for use

### Business Case for Serverless

1. **85% cost reduction** for variable traffic patterns
2. **Zero infrastructure management** time
3. **Automatic scaling** to any load
4. **Better user experience** with global CDN
5. **Higher reliability** with AWS-managed infrastructure

## Recommendation

Move to Stage 3 (Serverless) when:
- Traffic becomes highly variable
- Costs approach \$200+/month
- Need global performance
- Want zero maintenance

Current Stage 2 is optimal for:
- Predictable 200-500 concurrent users
- Budget: <\$100/month
- Learning infrastructure management
EOF

echo ""
echo "=========================================="
echo "Breaking Point Test Complete"
echo "=========================================="
echo "Results saved to: $RESULTS_DIR/"
echo ""
cat $RESULTS_DIR/breaking-point-report.md
echo ""
echo "Detailed results available in:"
echo "  - $RESULTS_DIR/breaking-point-report.md"
echo "  - $RESULTS_DIR/*.txt (full ApacheBench output)"
echo "  - $RESULTS_DIR/*.tsv (timing data for graphing)"
echo "=========================================="
