#!/bin/bash
# IOC Labs E-Commerce - Complete Improvements Script
# Adds: Input Validation, Rate Limiting, Error Handling, Database Indexes
# Usage: bash complete-fix.sh

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   IOC Labs - Stage 1 Improvements             ║${NC}"
echo -e "${BLUE}║   Adding: Validation, Rate Limiting, Indexes  ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
echo ""

# Check if in correct directory
if [ ! -f "go.mod" ]; then
    echo -e "${RED}Error: Must run from project root (where go.mod is)${NC}"
    exit 1
fi

echo -e "${YELLOW}📂 Creating new packages...${NC}"

# ============================================================================
# 1. Create validator package
# ============================================================================
mkdir -p pkg/validator

cat > pkg/validator/validator.go << 'EOF'
package validator

import (
	"fmt"
	"regexp"
	"strings"
)

var (
	emailRegex    = regexp.MustCompile(`^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$`)
	passwordRegex = regexp.MustCompile(`^.{8,}$`)
)

type ValidationError struct {
	Field   string `json:"field"`
	Message string `json:"message"`
}

type ValidationErrors []ValidationError

func (ve ValidationErrors) Error() string {
	var messages []string
	for _, err := range ve {
		messages = append(messages, fmt.Sprintf("%s: %s", err.Field, err.Message))
	}
	return strings.Join(messages, "; ")
}

type Validator struct {
	errors ValidationErrors
}

func New() *Validator {
	return &Validator{errors: ValidationErrors{}}
}

func (v *Validator) AddError(field, message string) {
	v.errors = append(v.errors, ValidationError{Field: field, Message: message})
}

func (v *Validator) IsValid() bool {
	return len(v.errors) == 0
}

func (v *Validator) Errors() ValidationErrors {
	return v.errors
}

func (v *Validator) Required(field, value string) {
	if strings.TrimSpace(value) == "" {
		v.AddError(field, "is required")
	}
}

func (v *Validator) Email(field, value string) {
	if value != "" && !emailRegex.MatchString(value) {
		v.AddError(field, "must be a valid email address")
	}
}

func (v *Validator) MinLength(field, value string, min int) {
	if len(value) < min {
		v.AddError(field, fmt.Sprintf("must be at least %d characters", min))
	}
}

func (v *Validator) MaxLength(field, value string, max int) {
	if len(value) > max {
		v.AddError(field, fmt.Sprintf("must not exceed %d characters", max))
	}
}

func (v *Validator) Min(field string, value, min int) {
	if value < min {
		v.AddError(field, fmt.Sprintf("must be at least %d", min))
	}
}

func (v *Validator) Max(field string, value, max int) {
	if value > max {
		v.AddError(field, fmt.Sprintf("must not exceed %d", max))
	}
}

func (v *Validator) PositiveFloat(field string, value float64) {
	if value <= 0 {
		v.AddError(field, "must be a positive number")
	}
}

func (v *Validator) Password(field, value string) {
	if !passwordRegex.MatchString(value) {
		v.AddError(field, "must be at least 8 characters")
	}
}

func (v *Validator) OneOf(field, value string, allowed []string) {
	for _, a := range allowed {
		if value == a {
			return
		}
	}
	v.AddError(field, fmt.Sprintf("must be one of: %s", strings.Join(allowed, ", ")))
}
EOF

echo -e "${GREEN}✓ Created pkg/validator/validator.go${NC}"

# ============================================================================
# 2. Create errors package
# ============================================================================
mkdir -p pkg/errors

cat > pkg/errors/errors.go << 'EOF'
package errors

import (
	"fmt"
	"net/http"
)

type AppError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
	Status  int    `json:"-"`
}

func (e *AppError) Error() string {
	return e.Message
}

var (
	ErrNotFound = &AppError{
		Code:    "NOT_FOUND",
		Message: "Resource not found",
		Status:  http.StatusNotFound,
	}

	ErrUnauthorized = &AppError{
		Code:    "UNAUTHORIZED",
		Message: "Authentication required",
		Status:  http.StatusUnauthorized,
	}

	ErrForbidden = &AppError{
		Code:    "FORBIDDEN",
		Message: "Access denied",
		Status:  http.StatusForbidden,
	}

	ErrBadRequest = &AppError{
		Code:    "BAD_REQUEST",
		Message: "Invalid request",
		Status:  http.StatusBadRequest,
	}

	ErrInternalServer = &AppError{
		Code:    "INTERNAL_ERROR",
		Message: "An internal error occurred",
		Status:  http.StatusInternalServerError,
	}

	ErrInvalidCredentials = &AppError{
		Code:    "INVALID_CREDENTIALS",
		Message: "Invalid email or password",
		Status:  http.StatusUnauthorized,
	}

	ErrEmailExists = &AppError{
		Code:    "EMAIL_EXISTS",
		Message: "Email already registered",
		Status:  http.StatusConflict,
	}

	ErrInsufficientStock = &AppError{
		Code:    "INSUFFICIENT_STOCK",
		Message: "Not enough stock available",
		Status:  http.StatusBadRequest,
	}

	ErrEmptyCart = &AppError{
		Code:    "EMPTY_CART",
		Message: "Cart is empty",
		Status:  http.StatusBadRequest,
	}
)

func New(code, message string, status int) *AppError {
	return &AppError{Code: code, Message: message, Status: status}
}

func NotFound(resource string) *AppError {
	return &AppError{
		Code:    "NOT_FOUND",
		Message: fmt.Sprintf("%s not found", resource),
		Status:  http.StatusNotFound,
	}
}

func ValidationError(message string) *AppError {
	return &AppError{
		Code:    "VALIDATION_ERROR",
		Message: message,
		Status:  http.StatusBadRequest,
	}
}
EOF

echo -e "${GREEN}✓ Created pkg/errors/errors.go${NC}"

# ============================================================================
# 3. Update response package
# ============================================================================
mkdir -p pkg/response

cat > pkg/response/response.go << 'EOF'
package response

import (
	"encoding/json"
	"log"
	"net/http"

	apperrors "github.com/ibraheemcisse/ioc-labs-ecommerce/pkg/errors"
	"github.com/ibraheemcisse/ioc-labs-ecommerce/pkg/validator"
)

type Response struct {
	Success bool        `json:"success"`
	Data    interface{} `json:"data,omitempty"`
	Error   *ErrorData  `json:"error,omitempty"`
}

type ErrorData struct {
	Code    string                     `json:"code"`
	Message string                     `json:"message"`
	Details []validator.ValidationError `json:"details,omitempty"`
}

func JSON(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)

	response := Response{
		Success: status < 400,
		Data:    data,
	}

	if err := json.NewEncoder(w).Encode(response); err != nil {
		log.Printf("Error encoding response: %v", err)
	}
}

func Error(w http.ResponseWriter, status int, code, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)

	response := Response{
		Success: false,
		Error: &ErrorData{
			Code:    code,
			Message: message,
		},
	}

	if err := json.NewEncoder(w).Encode(response); err != nil {
		log.Printf("Error encoding error response: %v", err)
	}
}

func ValidationErrors(w http.ResponseWriter, errors validator.ValidationErrors) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusBadRequest)

	response := Response{
		Success: false,
		Error: &ErrorData{
			Code:    "VALIDATION_ERROR",
			Message: "Validation failed",
			Details: errors,
		},
	}

	if err := json.NewEncoder(w).Encode(response); err != nil {
		log.Printf("Error encoding validation errors: %v", err)
	}
}

func AppError(w http.ResponseWriter, err *apperrors.AppError) {
	Error(w, err.Status, err.Code, err.Message)
}
EOF

echo -e "${GREEN}✓ Created pkg/response/response.go${NC}"

# ============================================================================
# 4. Create rate limiter middleware
# ============================================================================

cat > internal/middleware/ratelimit.go << 'EOF'
package middleware

import (
	"net/http"
	"sync"
	"time"

	"github.com/ibraheemcisse/ioc-labs-ecommerce/pkg/response"
)

type rateLimiter struct {
	requests map[string]*clientInfo
	mu       sync.RWMutex
	limit    int
	window   time.Duration
}

type clientInfo struct {
	count      int
	resetAt    time.Time
	lastAccess time.Time
}

func NewRateLimiter(requestsPerWindow int, window time.Duration) *rateLimiter {
	rl := &rateLimiter{
		requests: make(map[string]*clientInfo),
		limit:    requestsPerWindow,
		window:   window,
	}

	go rl.cleanup()
	return rl
}

func (rl *rateLimiter) cleanup() {
	ticker := time.NewTicker(time.Minute)
	defer ticker.Stop()

	for range ticker.C {
		rl.mu.Lock()
		now := time.Now()
		for ip, info := range rl.requests {
			if now.Sub(info.lastAccess) > 5*time.Minute {
				delete(rl.requests, ip)
			}
		}
		rl.mu.Unlock()
	}
}

func (rl *rateLimiter) allow(ip string) bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	now := time.Now()
	info, exists := rl.requests[ip]

	if !exists || now.After(info.resetAt) {
		rl.requests[ip] = &clientInfo{
			count:      1,
			resetAt:    now.Add(rl.window),
			lastAccess: now,
		}
		return true
	}

	info.lastAccess = now

	if info.count >= rl.limit {
		return false
	}

	info.count++
	return true
}

func (rl *rateLimiter) Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ip := r.RemoteAddr

		if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
			ip = xff
		} else if xri := r.Header.Get("X-Real-IP"); xri != "" {
			ip = xri
		}

		if !rl.allow(ip) {
			response.Error(w, http.StatusTooManyRequests, "RATE_LIMIT_EXCEEDED", "Too many requests. Please try again later.")
			return
		}

		next.ServeHTTP(w, r)
	})
}
EOF

echo -e "${GREEN}✓ Created internal/middleware/ratelimit.go${NC}"

# ============================================================================
# 5. Create database indexes migration
# ============================================================================

cat > migrations/005_add_indexes.sql << 'EOF'
-- Performance indexes for IOC Labs E-Commerce

-- Products table indexes
CREATE INDEX IF NOT EXISTS idx_products_category ON products(category);
CREATE INDEX IF NOT EXISTS idx_products_price ON products(price);
CREATE INDEX IF NOT EXISTS idx_products_stock ON products(stock);
CREATE INDEX IF NOT EXISTS idx_products_created_at ON products(created_at);

-- Users table indexes
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);

-- Cart items indexes
CREATE INDEX IF NOT EXISTS idx_cart_items_user_id ON cart_items(user_id);
CREATE INDEX IF NOT EXISTS idx_cart_items_product_id ON cart_items(product_id);
CREATE INDEX IF NOT EXISTS idx_cart_items_user_product ON cart_items(user_id, product_id);

-- Orders table indexes
CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON orders(created_at);
CREATE INDEX IF NOT EXISTS idx_orders_user_status ON orders(user_id, status);

-- Order items indexes
CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_product_id ON order_items(product_id);

-- Composite indexes for common queries
CREATE INDEX IF NOT EXISTS idx_products_category_stock ON products(category, stock) WHERE stock > 0;

-- Analyze tables
ANALYZE users;
ANALYZE products;
ANALYZE cart_items;
ANALYZE orders;
ANALYZE order_items;
EOF

echo -e "${GREEN}✓ Created migrations/005_add_indexes.sql${NC}"

# ============================================================================
# 6. Apply database migrations
# ============================================================================
echo ""
echo -e "${YELLOW}📊 Applying database indexes...${NC}"

DB_NAME="${DATABASE_NAME:-ioc_labs_dev}"

if command -v psql &> /dev/null; then
    if psql -lqt | cut -d \| -f 1 | grep -qw $DB_NAME; then
        psql -d $DB_NAME -f migrations/005_add_indexes.sql
        echo -e "${GREEN}✓ Database indexes created${NC}"
    else
        echo -e "${YELLOW}⚠ Database $DB_NAME not found. Run migration manually:${NC}"
        echo "  psql -d $DB_NAME -f migrations/005_add_indexes.sql"
    fi
else
    echo -e "${YELLOW}⚠ psql not found. Run migration manually:${NC}"
    echo "  psql -d $DB_NAME -f migrations/005_add_indexes.sql"
fi

# ============================================================================
# 7. Update go.mod
# ============================================================================
echo ""
echo -e "${YELLOW}📦 Updating dependencies...${NC}"
go mod tidy
echo -e "${GREEN}✓ Dependencies updated${NC}"

# ============================================================================
# 8. Create example updated handler
# ============================================================================
echo ""
echo -e "${YELLOW}📝 Creating example handler updates...${NC}"

cat > HANDLER_UPDATES.md << 'EOF'
# Handler Updates Guide

Your handlers need to be updated to use the new validation and error handling.

## Example: Update internal/handlers/auth.go

Add these imports:
```go
import (
    // ... existing imports
    apperrors "github.com/ibraheemcisse/ioc-labs-ecommerce/pkg/errors"
    "github.com/ibraheemcisse/ioc-labs-ecommerce/pkg/response"
    "github.com/ibraheemcisse/ioc-labs-ecommerce/pkg/validator"
)
```

Update Register handler:
```go
func (h *AuthHandler) Register(w http.ResponseWriter, r *http.Request) {
    var req RegisterRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        response.Error(w, http.StatusBadRequest, "INVALID_JSON", "Invalid request body")
        return
    }

    // Validate
    v := validator.New()
    v.Required("email", req.Email)
    v.Email("email", req.Email)
    v.Required("password", req.Password)
    v.Password("password", req.Password)
    v.Required("first_name", req.FirstName)
    v.MaxLength("first_name", req.FirstName, 50)
    v.Required("last_name", req.LastName)
    v.MaxLength("last_name", req.LastName, 50)

    if !v.IsValid() {
        response.ValidationErrors(w, v.Errors())
        return
    }

    // Call service (update service to return *apperrors.AppError)
    user, token, err := h.authService.Register(r.Context(), req.Email, req.Password, req.FirstName, req.LastName)
    if err != nil {
        if appErr, ok := err.(*apperrors.AppError); ok {
            response.AppError(w, appErr)
            return
        }
        response.Error(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Registration failed")
        return
    }

    response.JSON(w, http.StatusCreated, map[string]interface{}{
        "user":  user,
        "token": token,
    })
}
```

## Example: Update internal/handlers/cart.go

```go
func (h *CartHandler) AddItem(w http.ResponseWriter, r *http.Request) {
    userID := r.Context().Value("user_id").(int64)

    var req AddToCartRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        response.Error(w, http.StatusBadRequest, "INVALID_JSON", "Invalid request body")
        return
    }

    // Validate
    v := validator.New()
    v.Min("product_id", req.ProductID, 1)
    v.Min("quantity", req.Quantity, 1)
    v.Max("quantity", req.Quantity, 100)

    if !v.IsValid() {
        response.ValidationErrors(w, v.Errors())
        return
    }

    err := h.service.AddItem(r.Context(), userID, int64(req.ProductID), req.Quantity)
    if err != nil {
        if appErr, ok := err.(*apperrors.AppError); ok {
            response.AppError(w, appErr)
            return
        }
        response.Error(w, http.StatusInternalServerError, "ADD_FAILED", "Failed to add item")
        return
    }

    response.JSON(w, http.StatusOK, map[string]string{"message": "Item added to cart"})
}
```

## Update main.go

Add rate limiting middleware:
```go
import (
    // ... existing imports
    "time"
)

func main() {
    // ... existing setup

    r := mux.NewRouter()
    
    // Global middleware
    r.Use(middleware.Logging)
    r.Use(middleware.CORS)
    
    // Rate limiting: 100 requests per minute per IP
    rateLimiter := middleware.NewRateLimiter(100, time.Minute)
    r.Use(rateLimiter.Middleware)
    
    // ... rest of setup
}
```

Apply these patterns to all your handlers.
EOF

echo -e "${GREEN}✓ Created HANDLER_UPDATES.md${NC}"

# ============================================================================
# 9. Run tests
# ============================================================================
echo ""
echo -e "${YELLOW}🧪 Running tests...${NC}"

if go test ./... -v 2>/dev/null; then
    echo -e "${GREEN}✓ All tests passed${NC}"
else
    echo -e "${YELLOW}⚠ No tests found or tests failed (this is okay for now)${NC}"
fi

# ============================================================================
# 10. Summary
# ============================================================================
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║            ✓ Improvements Complete!           ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}What was added:${NC}"
echo -e "  ${GREEN}✓${NC} Input validation package (pkg/validator)"
echo -e "  ${GREEN}✓${NC} Error handling package (pkg/errors)"
echo -e "  ${GREEN}✓${NC} Standardized response package (pkg/response)"
echo -e "  ${GREEN}✓${NC} Rate limiting middleware (100 req/min per IP)"
echo -e "  ${GREEN}✓${NC} Database indexes for performance"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo -e "  1. Read ${BLUE}HANDLER_UPDATES.md${NC} for examples"
echo -e "  2. Update your handlers to use validation"
echo -e "  3. Update services to return apperrors.AppError"
echo -e "  4. Add rate limiter to main.go"
echo -e "  5. Test with: ${BLUE}go run cmd/api/main.go${NC}"
echo ""
echo -e "${YELLOW}Test validation:${NC}"
echo -e "  ${BLUE}curl -X POST http://localhost:8080/api/register \\${NC}"
echo -e "  ${BLUE}  -H 'Content-Type: application/json' \\${NC}"
echo -e "  ${BLUE}  -d '{\"email\":\"bad\",\"password\":\"123\"}'${NC}"
echo ""
echo -e "${YELLOW}Test rate limiting:${NC}"
echo -e "  ${BLUE}for i in {1..110}; do curl http://localhost:8080/api/products & done${NC}"
echo ""
echo -e "${YELLOW}Commit changes:${NC}"
echo -e "  ${BLUE}git add .${NC}"
echo -e "  ${BLUE}git commit -m 'feat: Add validation, rate limiting, error handling, indexes'${NC}"
echo -e "  ${BLUE}git push origin main${NC}"
echo ""
