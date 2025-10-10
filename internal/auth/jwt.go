package auth

import (
"errors"
"fmt"
"os"
"time"

"github.com/golang-jwt/jwt/v5"
)

// Custom errors for JWT operations
var (
ErrInvalidToken      = errors.New("invalid token")
ErrExpiredToken      = errors.New("token has expired")
ErrTokenMalformed    = errors.New("token is malformed")
ErrNoJWTSecret       = errors.New("JWT_SECRET environment variable not set")
ErrInvalidSignMethod = errors.New("invalid signing method")
)

// Claims represents the JWT claims structure
type Claims struct {
UserID int `json:"user_id"`
jwt.RegisteredClaims
}

// getJWTSecret retrieves the JWT secret from environment
func getJWTSecret() ([]byte, error) {
secret := os.Getenv("JWT_SECRET")
if secret == "" {
return nil, ErrNoJWTSecret
}
return []byte(secret), nil
}

// GenerateToken creates a new JWT token for a user
// The token expires after 24 hours
func GenerateToken(userID int) (string, error) {
secret, err := getJWTSecret()
if err != nil {
return "", err
}

// Create claims with user ID and standard claims
claims := Claims{
UserID: userID,
RegisteredClaims: jwt.RegisteredClaims{
ExpiresAt: jwt.NewNumericDate(time.Now().Add(24 * time.Hour)),
IssuedAt:  jwt.NewNumericDate(time.Now()),
NotBefore: jwt.NewNumericDate(time.Now()),
Issuer:    "ioc-labs-ecommerce",
Subject:   fmt.Sprintf("user-%d", userID),
},
}

// Create token with claims
token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)

// Sign the token with secret
tokenString, err := token.SignedString(secret)
if err != nil {
return "", fmt.Errorf("failed to sign token: %w", err)
}

return tokenString, nil
}

// ValidateToken validates a JWT token and returns the claims if valid
func ValidateToken(tokenString string) (*Claims, error) {
secret, err := getJWTSecret()
if err != nil {
return nil, err
}

// Parse the token
token, err := jwt.ParseWithClaims(tokenString, &Claims{}, func(token *jwt.Token) (interface{}, error) {
// Verify signing method
if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
return nil, fmt.Errorf("%w: %v", ErrInvalidSignMethod, token.Header["alg"])
}
return secret, nil
})

if err != nil {
// Check for specific error types
if errors.Is(err, jwt.ErrTokenMalformed) {
return nil, ErrTokenMalformed
}
if errors.Is(err, jwt.ErrTokenExpired) {
return nil, ErrExpiredToken
}
return nil, fmt.Errorf("%w: %v", ErrInvalidToken, err)
}

// Extract claims
claims, ok := token.Claims.(*Claims)
if !ok || !token.Valid {
return nil, ErrInvalidToken
}

return claims, nil
}

// RefreshToken generates a new token from an existing valid token
// This extends the expiration time while maintaining the same user ID
func RefreshToken(oldTokenString string) (string, error) {
// Validate the old token
claims, err := ValidateToken(oldTokenString)
if err != nil {
return "", fmt.Errorf("cannot refresh invalid token: %w", err)
}

// Generate new token with same user ID
return GenerateToken(claims.UserID)
}

// GetUserIDFromToken extracts just the user ID from a token without full validation
// This is useful for logging/debugging but should NOT be used for authentication
func GetUserIDFromToken(tokenString string) (int, error) {
token, _, err := jwt.NewParser().ParseUnverified(tokenString, &Claims{})
if err != nil {
return 0, err
}

claims, ok := token.Claims.(*Claims)
if !ok {
return 0, ErrInvalidToken
}

return claims.UserID, nil
}
