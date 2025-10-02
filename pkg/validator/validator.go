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
