# E-Commerce Infrastructure Evolution: A Learning Laboratory

An experimental journey building the same application across four infrastructure paradigms to understand trade-offs between simplicity, cost, control, and scalability.

**What This Is:** A rapid, hands-on exploration of cloud-native patterns over 5 days  
**What This Isn't:** Production-ready e-commerce (intentionally simplified for learning)  
**Funding:** $550 AWS Lift program educational credits (used ~$20, or 3.6%)

## Recent Updates

### ✅ Security Fix: Bcrypt Password Hashing (Issue #1)
**Status:** Fixed and tested  
**Context:** Code review identified critical password security vulnerability  

After receiving feedback that passwords were being stored in plain text, I implemented industry-standard bcrypt password hashing with:
- Automatic salting and key derivation
- Password strength validation (minimum 8 characters)
- Generic error messages to prevent user enumeration
- Comprehensive unit tests (93.3% coverage)

**Why this matters:** Even in a learning project, basic security hygiene is essential. This fix demonstrates:
- Responsiveness to code review feedback
- Security-first mindset even in POC work
- Professional testing and documentation practices

The fix was developed in a local Docker environment after accidentally terminating the EC2 instance - which forced creation of a reproducible local development setup that benefits all future work.

[📁 Full writeup and technical details →](./docs/ISSUE_1_PASSWORD_SECURITY_FIX.md)

---

## The Experiment

I built identical functionality four times to answer one question: **How do infrastructure choices affect cost, complexity, and capability?**

Each stage ran for approximately 1 day just long enough to deploy, test, understand, and tear down before moving to the next.Stage 1: Single EC2 Instance        →  1 day  →  $0.40 in credits
Stage 2: Load-Balanced EC2 + RDS    →  1 day  →  $2.83 in credits
Stage 3: ECS Fargate                →  1 day  →  $2.00 in credits
Stage 4: Kubernetes + Istio         →  3 days →  $11.00 in credits (load testing)

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

### Stage 1: Single Server BaselineInternet → EC2 (Nginx + Go + PostgreSQL)
Daily cost: $0.40 | Capacity: ~100 users

**Runtime:** 1 day  
**Cost:** $0.40  
**Breaking Point:** 150 concurrent users at 20% CPU

Everything on one t2.small instance. Load testing revealed the bottleneck wasn't CPU—it was database connection pooling.

**The lesson:** A single well-configured server handles more than you'd think. 100 concurrent users on $0.40/day is respectable.

[📁 Stage 1 Infrastructure →](./infrastructure/stage-1/)

### Stage 2: Horizontal ScalingInternet → ALB → [EC2 #1, EC2 #2] → RDS PostgreSQL
→ ElastiCache Redis
Daily cost: $2.83 | Capacity: ~200 users

**Runtime:** 1 day  
**Cost:** $2.83  
**Breaking Point:** 200 concurrent users at 18% CPU

Added load balancer, second instance, external database. Cost increased 7x, capacity increased 33%.

**The lesson:** Horizontal scaling without understanding bottlenecks wastes money. I was scaling compute when I needed to scale database connections.

[📁 Stage 2 Infrastructure →](./infrastructure/stage-2/)

### Stage 3: Managed ContainersInternet → ALB → [Fargate Task 1, Fargate Task 2] → RDS
→ Redis
Daily cost: $2.00 | Capacity: ~500 users

**Runtime:** 1 day  
**Cost:** $2.00  
**Breaking Point:** 500 concurrent users at 10% CPU

Containerized with Docker, deployed to ECS Fargate. Better performance, lower cost than Stage 2.

**The lesson:** Managed services aren't always more expensive. Fargate was cheaper and easier to operate than multi-instance EC2.

[📁 Stage 3 Infrastructure →](./infrastructure/stage-3-ecs/)

### Stage 4: Kubernetes + Service MeshInternet → NodePort → [K8s Pod 1, K8s Pod 2] → RDS
↓ (Istio sidecar)        → Redis
Meshery/Kiali/Grafana
Daily cost: $3.67 | Capacity: ~700 users

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

## Security Evolution

### Phase 1: Learning Project Security
Initially, this project used simplified authentication to focus on infrastructure learning:
- Plain text passwords (explicitly documented as insecure)
- Simple token generation
- No HTTPS

### Phase 2: Security Hardening (Current)
After code review feedback, implemented production-grade authentication:

**✅ Implemented:**
- Bcrypt password hashing (cost factor 10, ~90ms per hash)
- Automatic salting
- Password strength validation
- Generic error messages (prevents user enumeration)
- Input sanitization
- 93.3% test coverage on auth functions

**🔄 In Progress (Future Issues):**
- JWT token implementation (#2)
- Rate limiting on auth endpoints (#3)
- Account lockout after failed attempts
- Email verification
- HTTPS/TLS enforcement
- Security headers (CSP, HSTS)

**The Journey:**
What started as "skip security to focus on infrastructure" became a lesson in responsive security engineering:
1. Code review identified the vulnerability
2. EC2 instance accidentally terminated during fix
3. Built local Docker development environment
4. Implemented proper bcrypt hashing
5. Comprehensive testing (unit + integration)
6. Documentation for future developers

**The Learning:** Even POC projects benefit from security fundamentals. Basic hygiene (password hashing, input validation) costs little but teaches proper habits.

[📁 See full security writeup →](./docs/ISSUE_1_PASSWORD_SECURITY_FIX.md)

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
**Day 7:** Security hardening - Bcrypt password hashing implementation  

**8 hours:** Failed Lambda attempt (learned when to pivot)  

**Total:** ~48 hours over 7 days of focused work

## Lessons Learned

### On Infrastructure

1. **Rapid iteration teaches more than prolonged operation** — Build, test, understand, tear down
2. **Managed services are underrated** — Fargate beat both EC2 and K8s on cost and ops burden
3. **CPU is rarely the bottleneck** — Connection pools, database queries, and network I/O matter more
4. **Complexity has overhead** — Istio added 50-80ms latency for observability benefits

### On Security

1. **Security is iterative** — Start simple, respond to feedback, improve continuously
2. **Code review catches vulnerabilities** — External eyes found what I missed
3. **Local development enables rapid fixes** — Docker setup paid dividends during incident response
4. **Test coverage matters** — 93.3% coverage caught edge cases in password handling

### On Learning

1. **Educational credits enable experimentation** — $550 budget, used 3.6%, learned everything
2. **Failure is educational** — Lambda attempt taught as much as successful deploys
3. **Measure, don't assume** — Load testing revealed database as bottleneck, not compute
4. **Build to understand trade-offs** — Can't learn when NOT to use K8s without building it
5. **Incidents create opportunities** — EC2 termination led to better local dev setup

### On Cost

1. **Daily costs enable cheap experimentation** — $16-20 total for comprehensive learning
2. **Teardown discipline matters** — Destroy after understanding, don't let resources drift
3. **Credits are for learning** — AWS Lift program explicitly supports this type of PoC work

## Repository Structureioc-labs-ecommerce/
├── cmd/api/              # Application entry point
├── internal/
│   ├── auth/             # Password hashing & validation (bcrypt)
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
│   ├── ISSUE_1_PASSWORD_SECURITY_FIX.md  # Security fix writeup
│   ├── SECURITY.md       # Security considerations
│   ├── load-test-results/
│   └── stage-summaries/
└── scripts/              # Deployment automation

## What's Still Missing (For Production)

This is a learning project. Still needed for production:

**Authentication & Authorization:**
- ✅ ~~Password hashing~~ (Fixed - bcrypt implemented)
- ⏳ JWT token implementation (Issue #2)
- ⏳ Rate limiting on auth endpoints (Issue #3)
- ❌ Account lockout mechanism
- ❌ Email verification
- ❌ Password reset flow
- ❌ Two-factor authentication

**Infrastructure & Operations:**
- ❌ HTTPS/TLS enforcement
- ❌ CI/CD pipeline
- ❌ Comprehensive test suite
- ❌ WAF and advanced security
- ❌ Disaster recovery / backups
- ❌ Monitoring and alerting
- ❌ Log aggregation

**Application Features:**
- ❌ Order fulfillment workflow
- ❌ Inventory management
- ❌ Admin dashboard
- ❌ Customer support system

**Security Headers:**
- ❌ CSP, HSTS, X-Frame-Options
- ❌ CSRF protection
- ❌ Input sanitization beyond basic validation

## Addressing Critics

**"This is over-engineering"** — Yes, deliberately. You can't learn the cost of complexity without building complex things and measuring them. The conclusion is that simpler was better for this use case.

**"You're wasting money"** — Used $16-20 of $550 in educational credits (3.6%). That's efficient use of learning resources.

**"You don't know what you're doing"** — The documentation explicitly concludes Stage 4 was overkill. That's judgment, not ignorance. The security fix demonstrates responsiveness to feedback and proper engineering practices.

**"This isn't production-ready"** — Correct. It's explicitly labeled as a learning laboratory. The goal was understanding trade-offs, not building production systems. However, security improvements show a path toward production readiness.

**"Why fix security in a learning project?"** — Because even learning projects teach habits. Writing insecure code as a "learning shortcut" teaches bad patterns. Responding to code review and implementing proper security teaches professional engineering.

The project isn't claiming Kubernetes is better. It's proving it's not better for single applications. That required building it to verify.

## Contributing

This is primarily a learning project, but contributions that improve documentation, fix bugs, or add educational value are welcome! Please:

1. Open an issue to discuss the change
2. Follow existing code style
3. Include tests for new functionality
4. Update documentation

See [SECURITY.md](./docs/SECURITY.md) for security-related contributions.

## License

MIT License - feel free to learn from this, fork it, or use it as a starting point for your own experiments.

## Acknowledgments

This was funded by AWS Lift program educational credits, which provide resources for proof-of-concept development. The rapid iteration approach (1 day per stage) kept costs negligible while maximizing learning.

Special thanks to the code reviewer whose feedback led to the password security improvements. Code review is invaluable.

If you're learning infrastructure, I hope this repository shows that experimentation and honest reflection are more valuable than getting everything right the first time. Sometimes the best way to understand why NOT to use something is to build it and measure it.

---

**Current Status:** All cloud stages torn down after testing, local development active  
**Total Cloud Cost:** $16-20 from $550 in AWS educational credits (3.6% utilization)  
**Security Status:** Basic authentication hardened (bcrypt), JWT implementation planned  
**Most Valuable Learning:** Complexity for its own sake is expensive. Choose the simplest solution that meets your needs. And sometimes, you need to build the complex thing to understand why the simple thing was better. The same applies to security—implement it properly from the start, even in learning projects.
