// internal/auth/password_test.go
package auth

import (
	"testing"
)

func TestHashPassword(t *testing.T) {
	tests := []struct {
		name        string
		password    string
		shouldError bool
	}{
		{
			name:        "valid password",
			password:    "MySecureP@ssw0rd",
			shouldError: false,
		},
		{
			name:        "empty password",
			password:    "",
			shouldError: true,
		},
		{
			name:        "short password",
			password:    "pass",
			shouldError: false, // hashing should work, validation is separate
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			hash, err := HashPassword(tt.password)
			
			if tt.shouldError && err == nil {
				t.Error("expected error but got none")
			}
			
			if !tt.shouldError && err != nil {
				t.Errorf("unexpected error: %v", err)
			}
			
			if !tt.shouldError && hash == "" {
				t.Error("expected hash but got empty string")
			}
			
			// Verify hash is different from password
			if !tt.shouldError && hash == tt.password {
				t.Error("hash should not equal plain text password")
			}
		})
	}
}

func TestCheckPasswordHash(t *testing.T) {
	password := "MySecureP@ssw0rd"
	hash, err := HashPassword(password)
	if err != nil {
		t.Fatalf("failed to hash password: %v", err)
	}

	tests := []struct {
		name        string
		password    string
		hash        string
		shouldError bool
	}{
		{
			name:        "correct password",
			password:    password,
			hash:        hash,
			shouldError: false,
		},
		{
			name:        "incorrect password",
			password:    "WrongPassword123",
			hash:        hash,
			shouldError: true,
		},
		{
			name:        "empty password",
			password:    "",
			hash:        hash,
			shouldError: true,
		},
		{
			name:        "invalid hash",
			password:    password,
			hash:        "not-a-valid-hash",
			shouldError: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := CheckPasswordHash(tt.password, tt.hash)
			
			if tt.shouldError && err == nil {
				t.Error("expected error but got none")
			}
			
			if !tt.shouldError && err != nil {
				t.Errorf("unexpected error: %v", err)
			}
		})
	}
}

func TestValidatePasswordStrength(t *testing.T) {
	tests := []struct {
		name        string
		password    string
		shouldError bool
	}{
		{
			name:        "valid password",
			password:    "SecureP@ss123",
			shouldError: false,
		},
		{
			name:        "too short",
			password:    "short",
			shouldError: true,
		},
		{
			name:        "exactly 8 characters",
			password:    "12345678",
			shouldError: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := ValidatePasswordStrength(tt.password)
			
			if tt.shouldError && err == nil {
				t.Error("expected error but got none")
			}
			
			if !tt.shouldError && err != nil {
				t.Errorf("unexpected error: %v", err)
			}
		})
	}
}

// Benchmark to ensure bcrypt cost is reasonable
func BenchmarkHashPassword(b *testing.B) {
	password := "MySecureP@ssw0rd"
	
	for i := 0; i < b.N; i++ {
		_, _ = HashPassword(password)
	}
}

func BenchmarkCheckPasswordHash(b *testing.B) {
	password := "MySecureP@ssw0rd"
	hash, _ := HashPassword(password)
	
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_ = CheckPasswordHash(password, hash)
	}
}
