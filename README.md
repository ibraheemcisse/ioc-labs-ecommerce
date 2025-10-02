
# IOC Labs E-Commerce Platform

**Quality Assured**

Full-stack e-commerce platform built with Go, designed to scale from 5 to 10,000 users.

## Features

- JWT authentication
- Product catalog
- Shopping cart
- Order management
- PostgreSQL database
- Redis caching
- RESTful API

## Tech Stack

- **Backend:** Go 1.21+
- **Database:** PostgreSQL 15+
- **Cache:** Redis
- **Frontend:** Vanilla JS

## Quick Start
```bash
# Clone
git clone https://github.com/ibraheemcisse/ioc-labs-ecommerce.git
cd ioc-labs-ecommerce

# Install dependencies
go mod download

# Setup environment
cp .env.example .env
# Edit .env with your credentials

# Create database
createdb ioc_labs_dev

# Run migrations
for migration in migrations/*.sql; do
    psql -d ioc_labs_dev -f $migration
done

# Start server
go run cmd/api/main.go
Frontend
bashcd frontend
python3 -m http.server 3000
Visit http://localhost:3000
API Endpoints
Auth

POST /api/register - Register user
POST /api/login - Login

Products

GET /api/products - List products
GET /api/products/:id - Get product
GET /api/products/search - Search

Cart

GET /api/cart - View cart
POST /api/cart/add - Add to cart
DELETE /api/cart/remove/:id - Remove item

Orders

GET /api/orders - List orders
POST /api/orders - Create order

Architecture Stages

Stage 1: Single VM Monolith (5 users) ✓
Stage 2: Load Balanced (500 users)
Stage 3: Serverless (2,000 users)
Stage 4: Kubernetes (5,000 users)
Stage 5: Multi-Region (10,000 users)

Project Structure
├── cmd/api/              # Entry point
├── internal/
│   ├── handlers/         # HTTP handlers
│   ├── services/         # Business logic
│   ├── repository/       # Database layer
│   ├── models/           # Data models
│   └── middleware/       # Auth, CORS, logging
├── pkg/                  # Utilities
├── migrations/           # SQL migrations
└── frontend/             # UI
License
MIT
Contact
Ibrahim Cisse - ibrahimcisse@ioc-labs.com
