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
