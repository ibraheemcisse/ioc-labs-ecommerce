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
