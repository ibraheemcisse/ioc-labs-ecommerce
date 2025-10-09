# E-Commerce Infrastructure Evolution: A Learning Laboratory

An experimental journey building the same application across four infrastructure paradigms to understand trade-offs between simplicity, cost, control, and scalability.

**What This Is:** A rapid, hands-on exploration of cloud-native patterns over 5 days  
**What This Isn't:** Production-ready e-commerce (intentionally simplified for learning)  
**Funding:** $550 AWS Lift program educational credits (used ~$20, or 3.6%)

## The Experiment

I built identical functionality four times to answer one question: **How do infrastructure choices affect cost, complexity, and capability?**

Each stage ran for approximately 1 day just long enough to deploy, test, understand, and tear down before moving to the next.

```
Stage 1: Single EC2 Instance        →  1 day  →  $0.40 in credits
Stage 2: Load-Balanced EC2 + RDS    →  1 day  →  $2.83 in credits
Stage 3: ECS Fargate                →  1 day  →  $2.00 in credits
Stage 4: Kubernetes + Istio         →  3 days →  $11.00 in credits (load testing)
```

**Total Duration:** 5 days of focused experimentation  
**Total Cost:** ~$16-20 from $550 in AWS educational credits  
**Application Stack:** Go API, PostgreSQL, Redis, Stripe payments  
**Total Requests Processed:** 239,000+ across all load tests

## Why This Approach

I used AWS Lift program credits specifically designed for proof-of-concept work. The goal wasn't to run production infrastructure—it was to rapidly iterate through deployment patterns, measure the differences, and tear down quickly.

Critics say this is over-engineering. They're right—but missing the point. This was deliberate over-engineering to understand *why* it's over-engineering. You can't learn the cost of complexity without building complex things and measuring them.

## Key Findings

### Cost Reality Check

| Stage | Monthly Cost | Daily Cost | Actual Runtime | Real Cost |
|-------|--------------|------------|----------------|-----------|
| Stage 1 | $12 | $0.40 | 1 day | $0.40 |
| Stage 2 | $85 | $2.83 | 1 day | $2.83 |
| Stage 3 | $60 | $2.00 | 1 day | $2.00 |
| Stage 4 | $110 | $3.67 | 3 days | $11.00 |
| **Total** | — | — | **5 days** | **~$16-20** |

**Insight:** Rapid iteration kept costs negligible. Built, tested, understood, tore down. Repeat.

### Performance Under Load

| Stage | 50 Users | 200 Users | Breaking Point | CPU at Failure |
|-------|----------|-----------|----------------|----------------|
| Stage 1 | 45ms | 265ms | ~150 concurrent | 20% |
| Stage 2 | 40ms | 200ms | ~200 concurrent | 18% |
| Stage 3 | 43ms | 185ms | ~500 concurrent | 10% |
| Stage 4 | 47ms | 210ms | ~700 concurrent | 24% |

**Surprise:** CPU was never the bottleneck. Database connection pool exhaustion killed performance before compute resources were saturated.

### Operational Complexity

| Stage | Deploy Time | Config Complexity | Debugging Difficulty |
|-------|-------------|-------------------|----------------------|
| Stage 1 | 5 min | 3 commands | Easy (SSH + logs) |
| Stage 2 | 5 min | 6 commands | Medium (multiple instances) |
| Stage 3 | 2 min | 2 commands | Easy (CloudWatch) |
| Stage 4 | 2 min | 437 lines YAML | High (K8s + mesh) |

**Surprise:** Fargate had the best developer experience—faster than EC2, simpler than Kubernetes.

### Cost Per Request at Scale

Based on 500,000 req/month if run continuously:

| Stage | Monthly Cost | Cost per Request |
|-------|--------------|------------------|
| Stage 1 | $12 | $0.000024 |
| Stage 2 | $85 | $0.000170 |
| Stage 3 | $60 | $0.000120 |
| Stage 4 | $110 | $0.000220 |

**But I didn't run continuously.** Each stage ran 1-3 days, measured, then destroyed. Total: $16-20.

## The Architecture Evolution

### Stage 1: Single Server Baseline
```
Internet → EC2 (Nginx + Go + PostgreSQL)
Daily cost: $0.40 | Capacity: ~100 users
```

**Runtime:** 1 day  
**Cost:** $0.40  
**Breaking Point:** 150 concurrent users at 20% CPU

Everything on one t2.small instance. Load testing revealed the bottleneck wasn't CPU—it was database connection pooling.

**The lesson:** A single well-configured server handles more than you'd think. 100 concurrent users on $0.40/day is respectable.

[📁 Stage 1 Infrastructure →](./infrastructure/stage-1/)

### Stage 2: Horizontal Scaling
```
Internet → ALB → [EC2 #1, EC2 #2] → RDS PostgreSQL
                                   → ElastiCache Redis
Daily cost: $2.83 | Capacity: ~200 users
```

**Runtime:** 1 day  
**Cost:** $2.83  
**Breaking Point:** 200 concurrent users at 18% CPU

Added load balancer, second instance, external database. Cost increased 7x, capacity increased 33%.

**The lesson:** Horizontal scaling without understanding bottlenecks wastes money. I was scaling compute when I needed to scale database connections.

[📁 Stage 2 Infrastructure →](./infrastructure/stage-2/)

### Stage 3: Managed Containers
```
Internet → ALB → [Fargate Task 1, Fargate Task 2] → RDS
                                                   → Redis
Daily cost: $2.00 | Capacity: ~500 users
```

**Runtime:** 1 day  
**Cost:** $2.00  
**Breaking Point:** 500 concurrent users at 10% CPU

Containerized with Docker, deployed to ECS Fargate. Better performance, lower cost than Stage 2.

**The lesson:** Managed services aren't always more expensive. Fargate was cheaper and easier to operate than multi-instance EC2.

[📁 Stage 3 Infrastructure →](./infrastructure/stage-3-ecs/)

### Stage 4: Kubernetes + Service Mesh
```
Internet → NodePort → [K8s Pod 1, K8s Pod 2] → RDS
                     ↓ (Istio sidecar)        → Redis
              Meshery/Kiali/Grafana
Daily cost: $3.67 | Capacity: ~700 users
```

**Runtime:** 3 days (extended for comprehensive load testing)  
**Cost:** $11.00  
**Breaking Point:** 700 concurrent users at 24% CPU

Self-managed k3s cluster with Istio service mesh. Most complex, most capable, most expensive. Istio added 50-80ms latency per request for observability benefits.

**The lesson:** Kubernetes gives you power at the cost of complexity. For a single application, the trade-off doesn't make sense. For 20 microservices with complex routing needs, it does.

[📁 Stage 4 Infrastructure →](./infrastructure/stage-4-k8s/)

## What Didn't Work

### Failed Attempt: AWS Lambda + API Gateway

**Duration:** 8 hours  
**Outcome:** Abandoned  
**Cost:** $0

SAM CLI tooling for Go Lambda functions was unreliable. Build process repeatedly created empty deployment packages. After 8 hours of debugging tooling instead of learning serverless, I pivoted to containers.

**What I learned:** Knowing when to cut your losses is a skill. Tooling maturity matters.

## Real Bottlenecks Discovered

Through 239,000+ requests across all stages:

**1. Database Connection Pool Exhaustion**
- RDS db.t3.micro: ~87 max connections
- Application pool: 25 connections per instance initially
- This limited scale more than CPU or memory

**2. Connection Pool Mode**
- Switching from session to transaction pooling improved throughput 3x
- Cost: $0, just a config change

**3. Missing Indexes**
- Added indexes on `users.email` and `products.category`
- Query time: 150ms → 12ms
- Cost: $0, just SQL commands

**4. Health Check Frequency**
- Reduced ALB health checks from every 5s to every 30s
- Freed up 20% of connection pool
- Cost: $0, just a config change

**Key Insight:** None of these required new infrastructure. Application and database tuning beat infrastructure scaling.

## The Honest Conclusion

**If I were building this for real, I'd choose Stage 3 (ECS Fargate):**

- Lower cost than multi-instance EC2
- No server management
- Fast deployments (2 minutes)
- Automatic scaling
- Good AWS integration

**I wouldn't choose Stage 4 (Kubernetes) unless:**
- Running multiple microservices (5+)
- Need multi-cloud portability
- Have dedicated ops team
- Advanced traffic management requirements

The K8s setup cost more and delivered less for a single application. But the learning was invaluable for understanding when and why to use it.

## Project Timeline

**Day 1:** Stage 1 - Single EC2 baseline  
**Day 2:** Stage 2 - Horizontal scaling with RDS  
**Day 3:** Stage 3 - Containerization with Fargate  
**Days 4-6:** Stage 4 - Kubernetes + Istio with comprehensive load testing  

**8 hours:** Failed Lambda attempt (learned when to pivot)  

**Total:** ~40 hours over 5 days of focused work

## Lessons Learned

### On Infrastructure

1. **Rapid iteration teaches more than prolonged operation** — Build, test, understand, tear down
2. **Managed services are underrated** — Fargate beat both EC2 and K8s on cost and ops burden
3. **CPU is rarely the bottleneck** — Connection pools, database queries, and network I/O matter more
4. **Complexity has overhead** — Istio added 50-80ms latency for observability benefits

### On Learning

1. **Educational credits enable experimentation** — $550 budget, used 3.6%, learned everything
2. **Failure is educational** — Lambda attempt taught as much as successful deploys
3. **Measure, don't assume** — Load testing revealed database as bottleneck, not compute
4. **Build to understand trade-offs** — Can't learn when NOT to use K8s without building it

### On Cost

1. **Daily costs enable cheap experimentation** — $16-20 total for comprehensive learning
2. **Teardown discipline matters** — Destroy after understanding, don't let resources drift
3. **Credits are for learning** — AWS Lift program explicitly supports this type of PoC work

## Repository Structure

```
ioc-labs-ecommerce/
├── cmd/api/              # Application entry point
├── internal/
│   ├── handlers/         # HTTP request handlers
│   ├── services/         # Business logic
│   ├── repository/       # Database access layer
│   └── middleware/       # Auth, rate limiting
├── pkg/
│   ├── validator/        # Input validation
│   ├── errors/           # Error handling
│   └── database/         # DB connection
├── frontend/             # Vanilla HTML/CSS/JS
├── migrations/           # SQL schema migrations
├── infrastructure/
│   ├── stage-1/          # Single EC2 setup
│   ├── stage-2/          # ALB + multi-instance
│   ├── stage-3-ecs/      # Fargate deployment
│   └── stage-4-k8s/      # Kubernetes manifests
├── docs/
│   ├── load-test-results/
│   └── stage-summaries/
└── scripts/              # Deployment automation
```

## What's Missing (Intentionally)

This is a learning project, so I skipped:

- **Password hashing** — Using plain text (DO NOT DO THIS IN PRODUCTION)
- **HTTPS/TLS** — HTTP only for simplicity
- **CI/CD pipeline** — Manual deployments to understand the process
- **Comprehensive tests** — Focused on infrastructure, not application logic
- **Advanced security** — Basic security groups, no WAF
- **Disaster recovery** — No backup strategy

## Addressing Critics

**"This is over-engineering"** — Yes, deliberately. You can't learn the cost of complexity without building complex things and measuring them. The conclusion is that simpler was better for this use case.

**"You're wasting money"** — Used $16-20 of $550 in educational credits (3.6%). That's efficient use of learning resources.

**"You don't know what you're doing"** — The documentation explicitly concludes Stage 4 was overkill. That's judgment, not ignorance.

**"This isn't production-ready"** — Correct. It's explicitly labeled as a learning laboratory. The goal was understanding trade-offs, not building production systems.

The project isn't claiming Kubernetes is better. It's proving it's not better for single applications. That required building it to verify.


## License

MIT License - feel free to learn from this, fork it, or use it as a starting point for your own experiments.

## Acknowledgments

This was funded by AWS Lift program educational credits, which provide resources for proof-of-concept development. The rapid iteration approach (1 day per stage) kept costs negligible while maximizing learning.

If you're learning infrastructure, I hope this repository shows that experimentation and honest reflection are more valuable than getting everything right the first time. Sometimes the best way to understand why NOT to use something is to build it and measure it.

---

**Current Status:** All stages torn down after testing  
**Total Cost:** $16-20 from $550 in AWS educational credits (3.6% utilization)  
**Most Valuable Learning:** Complexity for its own sake is expensive. Choose the simplest solution that meets your needs. And sometimes, you need to build the complex thing to understand why the simple thing was better.
