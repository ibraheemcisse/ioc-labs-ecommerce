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
