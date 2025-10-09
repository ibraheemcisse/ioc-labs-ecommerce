// internal/auth/password.go
package auth

import (
	"errors"
	"golang.org/x/crypto/bcrypt"
)

// ErrInvalidPassword is returned when password verification fails
var ErrInvalidPassword = errors.New("invalid password")

// HashPassword generates a bcrypt hash of the password
// Uses bcrypt.DefaultCost (currently 10) which provides a good balance
// between security and performance
func HashPassword(password string) (string, error) {
	// Validate password is not empty
	if password == "" {
		return "", errors.New("password cannot be empty")
	}

	// bcrypt handles salting automatically
	bytes, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return "", err
	}
	
	return string(bytes), nil
}

// CheckPasswordHash compares a password with its bcrypt hash
// Returns nil if the password matches the hash, ErrInvalidPassword otherwise
func CheckPasswordHash(password, hash string) error {
	err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(password))
	if err != nil {
		if errors.Is(err, bcrypt.ErrMismatchedHashAndPassword) {
			return ErrInvalidPassword
		}
		return err
	}
	return nil
}

// ValidatePasswordStrength performs basic password strength validation
// This is a simple implementation - enhance based on your requirements
func ValidatePasswordStrength(password string) error {
	if len(password) < 8 {
		return errors.New("password must be at least 8 characters long")
	}
	
	// You can add more validation rules here:
	// - Contains uppercase letter
	// - Contains lowercase letter
	// - Contains number
	// - Contains special character
	
	return nil
}
