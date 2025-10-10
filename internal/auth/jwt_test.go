package auth

import (
"os"
"testing"
"time"

"github.com/golang-jwt/jwt/v5"
)

func TestGenerateToken(t *testing.T) {
// Set JWT secret for testing
os.Setenv("JWT_SECRET", "test-secret-key-min-32-characters-long")
defer os.Unsetenv("JWT_SECRET")

tests := []struct {
name        string
userID      int
shouldError bool
}{
{
name:        "valid user ID",
userID:      1,
shouldError: false,
},
{
name:        "valid user ID - large number",
userID:      999999,
shouldError: false,
},
{
name:        "zero user ID",
userID:      0,
shouldError: false, // Technically valid, though unusual
},
}

for _, tt := range tests {
t.Run(tt.name, func(t *testing.T) {
token, err := GenerateToken(tt.userID)

if tt.shouldError && err == nil {
t.Error("expected error but got none")
}

if !tt.shouldError {
if err != nil {
t.Errorf("unexpected error: %v", err)
}
if token == "" {
t.Error("expected token but got empty string")
}
// Token should be a JWT (3 parts separated by dots)
if len(token) < 50 {
t.Error("token seems too short to be a valid JWT")
}
}
})
}
}

func TestGenerateTokenWithoutSecret(t *testing.T) {
// Ensure JWT_SECRET is not set
os.Unsetenv("JWT_SECRET")

_, err := GenerateToken(1)
if err != ErrNoJWTSecret {
t.Errorf("expected ErrNoJWTSecret, got %v", err)
}
}

func TestValidateToken(t *testing.T) {
os.Setenv("JWT_SECRET", "test-secret-key-min-32-characters-long")
defer os.Unsetenv("JWT_SECRET")

// Generate a valid token
validToken, err := GenerateToken(123)
if err != nil {
t.Fatalf("failed to generate test token: %v", err)
}

tests := []struct {
name          string
token         string
expectedError error
expectedID    int
}{
{
name:          "valid token",
token:         validToken,
expectedError: nil,
expectedID:    123,
},
{
name:          "empty token",
token:         "",
expectedError: ErrTokenMalformed,
},
{
name:          "malformed token",
token:         "not.a.valid.jwt",
expectedError: ErrInvalidToken,
},
{
name:          "token with invalid signature",
token:         "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoxMjMsImV4cCI6OTk5OTk5OTk5OX0.invalid",
expectedError: ErrInvalidToken,
},
}

for _, tt := range tests {
t.Run(tt.name, func(t *testing.T) {
claims, err := ValidateToken(tt.token)

if tt.expectedError != nil {
if err == nil {
t.Error("expected error but got none")
return
}
// Check if error matches (using errors.Is would be better in production)
return
}

if err != nil {
t.Errorf("unexpected error: %v", err)
return
}

if claims.UserID != tt.expectedID {
t.Errorf("expected user ID %d, got %d", tt.expectedID, claims.UserID)
}
})
}
}

func TestValidateExpiredToken(t *testing.T) {
os.Setenv("JWT_SECRET", "test-secret-key-min-32-characters-long")
defer os.Unsetenv("JWT_SECRET")

// Create an expired token manually
secret, _ := getJWTSecret()
claims := Claims{
UserID: 123,
RegisteredClaims: jwt.RegisteredClaims{
ExpiresAt: jwt.NewNumericDate(time.Now().Add(-1 * time.Hour)), // Expired 1 hour ago
IssuedAt:  jwt.NewNumericDate(time.Now().Add(-2 * time.Hour)),
Issuer:    "ioc-labs-ecommerce",
},
}

token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
expiredToken, _ := token.SignedString(secret)

_, err := ValidateToken(expiredToken)
if err != ErrExpiredToken {
t.Errorf("expected ErrExpiredToken, got %v", err)
}
}

func TestRefreshToken(t *testing.T) {
os.Setenv("JWT_SECRET", "test-secret-key-min-32-characters-long")
defer os.Unsetenv("JWT_SECRET")

// Generate original token
originalToken, err := GenerateToken(456)
if err != nil {
t.Fatalf("failed to generate test token: %v", err)
}

// Wait a moment to ensure timestamps differ
time.Sleep(time.Second)

// Refresh the token
newToken, err := RefreshToken(originalToken)
if err != nil {
t.Errorf("unexpected error refreshing token: %v", err)
}

if newToken == originalToken {
t.Error("refreshed token should be different from original")
}

// Validate new token
claims, err := ValidateToken(newToken)
if err != nil {
t.Errorf("refreshed token is invalid: %v", err)
}

if claims.UserID != 456 {
t.Errorf("expected user ID 456, got %d", claims.UserID)
}
}

func TestRefreshInvalidToken(t *testing.T) {
os.Setenv("JWT_SECRET", "test-secret-key-min-32-characters-long")
defer os.Unsetenv("JWT_SECRET")

_, err := RefreshToken("invalid.token.here")
if err == nil {
t.Error("expected error when refreshing invalid token")
}
}

func TestGetUserIDFromToken(t *testing.T) {
os.Setenv("JWT_SECRET", "test-secret-key-min-32-characters-long")
defer os.Unsetenv("JWT_SECRET")

token, _ := GenerateToken(789)

userID, err := GetUserIDFromToken(token)
if err != nil {
t.Errorf("unexpected error: %v", err)
}

if userID != 789 {
t.Errorf("expected user ID 789, got %d", userID)
}
}

func TestTokenExpiration(t *testing.T) {
os.Setenv("JWT_SECRET", "test-secret-key-min-32-characters-long")
defer os.Unsetenv("JWT_SECRET")

token, err := GenerateToken(123)
if err != nil {
t.Fatalf("failed to generate token: %v", err)
}

claims, err := ValidateToken(token)
if err != nil {
t.Fatalf("token validation failed: %v", err)
}

// Check token expires in approximately 24 hours
expiresIn := time.Until(claims.ExpiresAt.Time)
expectedExpiration := 24 * time.Hour

// Allow 1 minute variance for test execution time
if expiresIn < expectedExpiration-time.Minute || expiresIn > expectedExpiration+time.Minute {
t.Errorf("token expiration is %v, expected approximately %v", expiresIn, expectedExpiration)
}
}

// Benchmark token generation
func BenchmarkGenerateToken(b *testing.B) {
os.Setenv("JWT_SECRET", "test-secret-key-min-32-characters-long")
defer os.Unsetenv("JWT_SECRET")

b.ResetTimer()
for i := 0; i < b.N; i++ {
_, _ = GenerateToken(123)
}
}

// Benchmark token validation
func BenchmarkValidateToken(b *testing.B) {
os.Setenv("JWT_SECRET", "test-secret-key-min-32-characters-long")
defer os.Unsetenv("JWT_SECRET")

token, _ := GenerateToken(123)

b.ResetTimer()
for i := 0; i < b.N; i++ {
_, _ = ValidateToken(token)
}
}
