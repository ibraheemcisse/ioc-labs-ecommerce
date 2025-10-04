package services

import (
"fmt"

"github.com/stripe/stripe-go/v76"
"github.com/stripe/stripe-go/v76/paymentintent"
)

type PaymentService struct{}

func NewPaymentService(stripeKey string) *PaymentService {
stripe.Key = stripeKey
return &PaymentService{}
}

// CreatePaymentIntent - Creates a Stripe payment intent
// Returns client_secret that frontend uses to confirm payment
func (s *PaymentService) CreatePaymentIntent(amountCents int64, currency string, metadata map[string]string) (*stripe.PaymentIntent, error) {
params := &stripe.PaymentIntentParams{
Amount:   stripe.Int64(amountCents),
Currency: stripe.String(currency),
AutomaticPaymentMethods: &stripe.PaymentIntentAutomaticPaymentMethodsParams{
Enabled: stripe.Bool(true),
},
}

// Add metadata (order ID, user ID, etc)
for key, value := range metadata {
params.AddMetadata(key, value)
}

pi, err := paymentintent.New(params)
if err != nil {
return nil, fmt.Errorf("failed to create payment intent: %w", err)
}

return pi, nil
}

// GetPaymentIntent - Retrieves payment intent status
func (s *PaymentService) GetPaymentIntent(paymentIntentID string) (*stripe.PaymentIntent, error) {
pi, err := paymentintent.Get(paymentIntentID, nil)
if err != nil {
return nil, fmt.Errorf("failed to retrieve payment intent: %w", err)
}
return pi, nil
}
