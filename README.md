# Infrastructure Experiment Lab — IOC Labs E-Commerce

> An experimental journey building the same application across four infrastructure paradigms to understand trade-offs between **simplicity, cost, control, and scalability**.

**What This Is:** A rapid, hands-on exploration of cloud-native patterns over 5 days  

**What This Isn't:** Production-ready e-commerce (intentionally simplified for learning)  

**Funding:** $550 AWS Lift educational credits (used ~$20 ≈ 3.6%)

```mermaid
flowchart LR
  subgraph Stage1["Stage 1: Single EC2"]
    A1[Internet] --> B1[EC2: Nginx + Go + PostgreSQL]
  end

  subgraph Stage2["Stage 2: Load-Balanced EC2 + RDS"]
    A2[Internet] --> B2[ALB]
    B2 --> C2a[EC2 #1]
    B2 --> C2b[EC2 #2]
    C2a & C2b --> D2[RDS: PostgreSQL]
    D2 --> E2[ElastiCache: Redis]
  end

  subgraph Stage3["Stage 3: ECS Fargate"]
    A3[Internet] --> B3[ALB]
    B3 --> C3a[Fargate Task 1]
    B3 --> C3b[Fargate Task 2]
    C3a & C3b --> D3[RDS]
    D3 --> E3[Redis]
  end

  subgraph Stage4["Stage 4: Kubernetes + Istio"]
    A4[Internet] --> B4[NodePort Service]
    B4 --> P4a[K8s Pod 1 + Istio Sidecar]
    B4 --> P4b[K8s Pod 2 + Istio Sidecar]
    P4a & P4b --> D4[RDS]
    D4 --> E4[Redis]
    subgraph Mesh["Observability Stack"]
      F4[Meshery] --> G4[Kiali] --> H4[Grafana]
    end
  end

  Stage1 --> Stage2 --> Stage3 --> Stage4
```

## 🛡️ Recent Security Improvements

### Issue #1: Bcrypt Password Hashing  

**Status:** Complete & tested  

- Cryptographic hashing with automatic salting  
- Password strength validation (≥ 8 chars)  
- Generic error messages prevent user enumeration  
- 93.3 % test coverage with unit tests  

**Impact:** Eliminates risk of password leaks on DB compromise  
[📁 Full write-up →](./docs/ISSUE_1_PASSWORD_SECURITY_FIX.md)

---

### Issue #2: JWT Token Implementation  
**Status:** Complete & tested  

- HMAC-SHA256 signed tokens  
- 24-hour expiration  
- Claims-based payload (user_id, issuer, timestamps)  
- Robust validation & error handling  
- 87.5 % test coverage with performance benchmarks  

**Impact:** Prevents forgery & session hijacking  
**Performance:** 10 μs generation / 15 μs validation

---

## ☁️ The Infrastructure Experiment

Built identical functionality four times to answer one question:  
**How do infrastructure choices affect cost, complexity, and capability?**

Each stage ran ~1 day (Stage 4 = 3 days) to deploy → test → understand → tear down.

| Stage | Description | Duration | Cost |
|:------|:-------------|:----------|:------|
| 1 | Single EC2 Instance | 1 day | $0.40 |
| 2 | Load-Balanced EC2 + RDS | 1 day | $2.83 |
| 3 | ECS Fargate | 1 day | $2.00 |
| 4 | Kubernetes + Istio | 3 days | $11.00 |

**Total:** 5 days infra + 2 days security   **≈ $16–20**

---

## Cost Reality Check

| Stage | Monthly | Daily | Runtime | Real Cost |
|-------|----------|--------|----------|-----------|
| 1 | $12 | $0.40 | 1 d | $0.40 |
| 2 | $85 | $2.83 | 1 d | $2.83 |
| 3 | $60 | $2.00 | 1 d | $2.00 |
| 4 | $110 | $3.67 | 3 d | $11.00 |
| **Total** | — | — | **5 d** | **≈ $16-20** |

**Insight:** Rapid iteration → negligible cost.

---

## Performance Under Load

| Stage | 50 Users | 200 Users | Breaking Point | CPU @ Failure |
|:------|:---------:|:----------:|:---------------:|:--------------:|
| 1 | 45 ms | 265 ms | ≈ 150 concurrent | 20 % |
| 2 | 40 ms | 200 ms | ≈ 200 | 18 % |
| 3 | 43 ms | 185 ms | ≈ 500 | 10 % |
| 4 | 47 ms | 210 ms | ≈ 700 | 24 % |

**Observation:** CPU was never the bottleneck — DB connections were.

---

## Architecture Evolution

### Stage 1 — Single Server Baseline

```mermaid
flowchart LR
  subgraph Stage1["Stage 1: Single EC2 Architecture"]
    A[Internet] --> B[EC2 Instance]
    B --> C[Nginx Reverse Proxy]
    C --> D[Go Application]
    D --> E[PostgreSQL Database]
  end
```

### Stage 2 — Horizontal Scaling

```mermaid
flowchart LR
A[Internet] --> B[ALB]
B --> C1[EC2 #1]
B --> C2[EC2 #2]
C1 & C2 --> D[(RDS PostgreSQL)]
D --> E[(ElastiCache Redis)]
```

Cost: $2.83 / day Capacity: ~200 users

- Scaling compute didn’t fix DB pool bottleneck.

### Stage 3 — Managed Containers (ECS Fargate)

```mermaid
flowchart LR
A[Internet] --> B[ALB]
B --> C1[Fargate Task 1]
B --> C2[Fargate Task 2]
C1 & C2 --> D[(RDS)]
D --> E[(Redis)]
```

- Cost: $2.00 / day Capacity: ~500 users

- Simpler ops, better performance than EC2.

### Stage 4 — Kubernetes + Istio

```mermaid
flowchart LR
A[Internet] --> B[NodePort Service]
B --> P1[K8s Pod 1 + Istio Sidecar]
B --> P2[K8s Pod 2 + Istio Sidecar]
P1 & P2 --> D[(RDS)]
D --> E[(Redis)]
subgraph Mesh[Service Mesh Observability]
  F[Meshery] --> G[Kiali] --> H[Grafana]
end
```
Cost: $3.67 / day Capacity: ~700 users

Most capable yet most complex (+ 50–80 ms latency).

### 🧠 Real Bottlenecks Found

- DB Connection Pool Exhaustion — RDS max ~87 connections

- Connection Mode — Transaction pooling → 3× throughput

- Missing Indexes — Query 150 ms → 12 ms

- Health Check Tuning — Reduced ALB checks = 20 % more pool capacity

Insight: Tuning > Scaling.

### 🔐 Security Evolution

```mermaid
journey
    title Security Journey
    section Simplified (POC)
      Plain-text passwords: 5: Insecure
      Simple tokens: 5: Insecure
    section Hardening Phase
      Bcrypt hashing: 3: Secure
      JWT tokens: 3: Secure
      HTTPS ready: 3: Secure
    section Outcome
      Production-grade auth: 1: Achieved
```

- Bcrypt: salted, cost factor 10 (~90 ms per hash)

- JWT: HMAC-SHA256, 24 h expiry, validated claims

- High test coverage and responsive code reviews

- EC2 termination incident led to Dockerized local dev environment

### 🧾 Key Takeaways

| Area               | Lesson                                                |
| ------------------ | ----------------------------------------------------- |
| **Infrastructure** | Fargate was the sweet spot — simple, cheap, effective |
| **Security**       | Iterative improvement beats initial perfection        |
| **Learning**       | Failure (Lambda) taught as much as success            |
| **Cost**           | $16–20 for end-to-end learning is a bargain           |
| **Complexity**     | K8s teaches why simpler is often better               |

```bash
ioc-labs-ecommerce/
├── cmd/api/              # Entry point
├── internal/
│   ├── auth/             # bcrypt + JWT
│   ├── handlers/         # HTTP handlers
│   ├── services/         # Business logic
│   ├── repository/       # Database access
│   └── middleware/       # Auth, rate limiting
├── pkg/
│   ├── validator/        # Input validation
│   ├── errors/           # Error handling
│   └── database/         # Connection helpers
├── frontend/             # Vanilla JS/HTML
├── migrations/           # SQL migrations
├── infrastructure/
│   ├── stage-1/          # Single EC2
│   ├── stage-2/          # ALB + multi-EC2
│   ├── stage-3-ecs/      # Fargate
│   └── stage-4-k8s/      # K8s + Istio
├── docs/
│   ├── ISSUE_1_PASSWORD_SECURITY_FIX.md
│   ├── SECURITY.md
│   └── stage-summaries/
└── scripts/              # Automation
```

## 🧩 Implemented vs Missing

### ✅ Implemented

1. Bcrypt password hashing
2. JWT authentication
3. Generic error handling
4. Input validation & sanitization
5. Health checks
6. High test coverage

### ⚠️ Missing (POC Scope)

1. Rate limiting / lockouts
2. Email verification & 2FA
3. Password reset flow
4. TLS enforcement + security headers
5. CSRF protection & session refresh
6. CI/CD and advanced monitoring

## 🧭 Conclusion

- If built for production, Stage 3 (Fargate) wins:
- No server management
- Fast deploys (~2 min)
- Auto scaling
- Lower cost & complexity

### Use Kubernetes only when:

- You have 5+ microservices
- Need multi-cloud portability
- Need fine-grained traffic control
- Have dedicated ops team

## 🤝 Contributing

- Contributions that improve documentation or educational value are welcome.

- Open an issue to discuss
- Follow existing code style
- Include tests
- Update docs

### 📜 License

MIT License — Use, fork, and learn freely.

### 🧡 Acknowledgments

- Funded by AWS Lift educational credits ($550 budget, 3.6 % used).
- Special thanks to the code reviewer whose feedback drove security upgrades.
- Experimentation and reflection beat perfection.
- Build the complex thing to learn why the simple thing was better.

- Current Status: All cloud infra torn down | Local dev active
- Cloud Cost: $16–20 (3.6 % of credits)
- Key Lesson: Simplicity wins — but you must build complexity to understand why.
