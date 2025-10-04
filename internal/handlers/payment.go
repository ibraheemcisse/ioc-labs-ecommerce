package handlers

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"

	"github.com/stripe/stripe-go/v76"
	"github.com/stripe/stripe-go/v76/paymentintent"
	"github.com/stripe/stripe-go/v76/webhook"
)

type PaymentHandler struct {
	db *sql.DB
}

func NewPaymentHandler(db *sql.DB) *PaymentHandler {
	return &PaymentHandler{db: db}
}

// CreatePaymentIntent - Creates a Stripe payment intent for an order
func (h *PaymentHandler) CreatePaymentIntent(w http.ResponseWriter, r *http.Request) {
	userID := r.Context().Value("user_id").(int64)

	var req struct {
		OrderID int64 `json:"order_id"`
	}
	
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.jsonError(w, http.StatusBadRequest, "INVALID_JSON", "Invalid request body")
		return
	}

	// Get order and verify ownership
	var order struct {
		ID     int64
		UserID int64
		Total  float64
		Status string
	}
	
	err := h.db.QueryRow(
		"SELECT id, user_id, total, status FROM orders WHERE id = $1",
		req.OrderID,
	).Scan(&order.ID, &order.UserID, &order.Total, &order.Status)
	
	if err == sql.ErrNoRows {
		h.jsonError(w, http.StatusNotFound, "NOT_FOUND", "Order not found")
		return
	}

	if order.UserID != userID {
		h.jsonError(w, http.StatusForbidden, "FORBIDDEN", "Not your order")
		return
	}

	if order.Status == "paid" {
		h.jsonError(w, http.StatusBadRequest, "ALREADY_PAID", "Order already paid")
		return
	}

	// Create payment intent
	stripe.Key = os.Getenv("STRIPE_SECRET_KEY")
	
	amountCents := int64(order.Total * 100)
	params := &stripe.PaymentIntentParams{
		Amount:   stripe.Int64(amountCents),
		Currency: stripe.String("usd"),
		AutomaticPaymentMethods: &stripe.PaymentIntentAutomaticPaymentMethodsParams{
			Enabled: stripe.Bool(true),
		},
	}
	
	// Add metadata
	params.AddMetadata("order_id", fmt.Sprintf("%d", order.ID))
	params.AddMetadata("user_id", fmt.Sprintf("%d", order.UserID))

	pi, err := paymentintent.New(params)
	if err != nil {
		h.jsonError(w, http.StatusInternalServerError, "PAYMENT_FAILED", "Failed to create payment")
		return
	}

	h.jsonResponse(w, http.StatusOK, map[string]interface{}{
		"client_secret": pi.ClientSecret,
		"amount":        pi.Amount,
	})
}

// HandleStripeWebhook - Processes Stripe webhook events
func (h *PaymentHandler) HandleStripeWebhook(w http.ResponseWriter, r *http.Request) {
	const MaxBodyBytes = int64(65536)
	r.Body = http.MaxBytesReader(w, r.Body, MaxBodyBytes)
	
	payload, err := io.ReadAll(r.Body)
	if err != nil {
		http.Error(w, "Error reading request body", http.StatusBadRequest)
		return
	}

	signature := r.Header.Get("Stripe-Signature")
	webhookSecret := os.Getenv("STRIPE_WEBHOOK_SECRET")
	
	if webhookSecret == "" {
		http.Error(w, "Webhook secret not configured", http.StatusInternalServerError)
		return
	}

	// Verify webhook signature
	event, err := webhook.ConstructEvent(payload, signature, webhookSecret)
	if err != nil {
		http.Error(w, fmt.Sprintf("Webhook signature verification failed: %v", err), http.StatusBadRequest)
		return
	}

	// Handle the event
	switch event.Type {
	case "payment_intent.succeeded":
		var pi stripe.PaymentIntent
		if err := json.Unmarshal(event.Data.Raw, &pi); err != nil {
			http.Error(w, "Error parsing webhook JSON", http.StatusBadRequest)
			return
		}
		if err := h.handlePaymentSuccess(&pi); err != nil {
			http.Error(w, "Error processing payment", http.StatusInternalServerError)
			return
		}

	case "payment_intent.payment_failed":
		var pi stripe.PaymentIntent
		if err := json.Unmarshal(event.Data.Raw, &pi); err != nil {
			http.Error(w, "Error parsing webhook JSON", http.StatusBadRequest)
			return
		}
		if err := h.handlePaymentFailure(&pi); err != nil {
			http.Error(w, "Error processing payment failure", http.StatusInternalServerError)
			return
		}

	case "payment_intent.canceled":
		var pi stripe.PaymentIntent
		if err := json.Unmarshal(event.Data.Raw, &pi); err != nil {
			http.Error(w, "Error parsing webhook JSON", http.StatusBadRequest)
			return
		}
		if err := h.handlePaymentCanceled(&pi); err != nil {
			http.Error(w, "Error processing cancellation", http.StatusInternalServerError)
			return
		}

	default:
		fmt.Printf("Unhandled event type: %s\n", event.Type)
	}

	w.WriteHeader(http.StatusOK)
}

func (h *PaymentHandler) handlePaymentSuccess(pi *stripe.PaymentIntent) error {
	orderIDStr, exists := pi.Metadata["order_id"]
	if !exists {
		return fmt.Errorf("order_id not found in payment intent metadata")
	}

	orderID, err := strconv.ParseInt(orderIDStr, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid order_id: %w", err)
	}

	query := `
		UPDATE orders 
		SET 
			status = 'paid',
			payment_status = 'succeeded',
			stripe_payment_intent_id = $1,
			updated_at = NOW()
		WHERE id = $2
	`

	_, err = h.db.Exec(query, pi.ID, orderID)
	if err != nil {
		return fmt.Errorf("failed to update order: %w", err)
	}

	fmt.Printf("✓ Payment succeeded for order %d (payment_intent: %s)\n", orderID, pi.ID)
	return nil
}

func (h *PaymentHandler) handlePaymentFailure(pi *stripe.PaymentIntent) error {
	orderIDStr, exists := pi.Metadata["order_id"]
	if !exists {
		return fmt.Errorf("order_id not found in payment intent metadata")
	}

	orderID, err := strconv.ParseInt(orderIDStr, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid order_id: %w", err)
	}

	query := `
		UPDATE orders 
		SET 
			payment_status = 'failed',
			updated_at = NOW()
		WHERE id = $1
	`

	_, err = h.db.Exec(query, orderID)
	if err != nil {
		return fmt.Errorf("failed to update order: %w", err)
	}

	fmt.Printf("✗ Payment failed for order %d (payment_intent: %s)\n", orderID, pi.ID)
	return nil
}

func (h *PaymentHandler) handlePaymentCanceled(pi *stripe.PaymentIntent) error {
	orderIDStr, exists := pi.Metadata["order_id"]
	if !exists {
		return fmt.Errorf("order_id not found in payment intent metadata")
	}

	orderID, err := strconv.ParseInt(orderIDStr, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid order_id: %w", err)
	}

	query := `
		UPDATE orders 
		SET 
			status = 'canceled',
			payment_status = 'canceled',
			updated_at = NOW()
		WHERE id = $1
	`

	_, err = h.db.Exec(query, orderID)
	if err != nil {
		return fmt.Errorf("failed to update order: %w", err)
	}

	fmt.Printf("⚠ Payment canceled for order %d (payment_intent: %s)\n", orderID, pi.ID)
	return nil
}

// Helper functions
func (h *PaymentHandler) jsonError(w http.ResponseWriter, status int, code, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success": false,
		"error": map[string]string{
			"code":    code,
			"message": message,
		},
	})
}

func (h *PaymentHandler) jsonResponse(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success": true,
		"data":    data,
	})
}
