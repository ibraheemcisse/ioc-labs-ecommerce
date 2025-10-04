package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/go-redis/redis/v8"
	"github.com/gorilla/mux"
	"github.com/joho/godotenv"
	_ "github.com/lib/pq"
	"github.com/rs/zerolog"
	zlog "github.com/rs/zerolog/log"
	
	"github.com/ibraheemcisse/ioc-labs-ecommerce/internal/handlers"
)

var (
	db          *sql.DB
	redisClient *redis.Client
	ctx         = context.Background()
)

func main() {
	zerolog.TimeFieldFormat = zerolog.TimeFormatUnix
	zlog.Logger = zlog.Output(zerolog.ConsoleWriter{Out: os.Stderr})

	if err := godotenv.Load(); err != nil {
		zlog.Warn().Msg("No .env file found")
	}

	var err error
	db, err = sql.Open("postgres", os.Getenv("DATABASE_URL"))
	if err != nil {
		log.Fatal("Failed to connect to database:", err)
	}
	defer db.Close()

	db.SetMaxOpenConns(25)
	db.SetMaxIdleConns(25)
	db.SetConnMaxLifetime(5 * time.Minute)

	if err := db.Ping(); err != nil {
		log.Fatal("Database ping failed:", err)
	}
	zlog.Info().Msg("Connected to PostgreSQL")

	redisClient = redis.NewClient(&redis.Options{
		Addr:     os.Getenv("REDIS_URL"),
		Password: "",
		DB:       0,
	})

	if err := redisClient.Ping(ctx).Err(); err != nil {
		zlog.Warn().Err(err).Msg("Redis connection failed, continuing without cache")
		redisClient = nil
	} else {
		zlog.Info().Msg("Connected to Redis")
	}

	r := mux.NewRouter()
	r.Use(corsMiddleware)

	api := r.PathPrefix("/api").Subrouter()

	// Initialize payment handler
	paymentHandler := handlers.NewPaymentHandler(db)

	// Public routes
	api.HandleFunc("/health", handleHealth).Methods("GET", "OPTIONS")
	api.HandleFunc("/products", handleListProducts).Methods("GET", "OPTIONS")
	api.HandleFunc("/products/{id:[0-9]+}", handleGetProduct).Methods("GET", "OPTIONS")
	api.HandleFunc("/products/search", handleSearchProducts).Methods("GET", "OPTIONS")
	api.HandleFunc("/auth/register", handleRegister).Methods("POST", "OPTIONS")
	api.HandleFunc("/auth/login", handleLogin).Methods("POST", "OPTIONS")
	
	// Stripe webhook (public - no auth)
	api.HandleFunc("/webhook/stripe", paymentHandler.HandleStripeWebhook).Methods("POST")

	// Protected routes
	protected := api.PathPrefix("").Subrouter()
	protected.Use(authMiddleware)
	protected.HandleFunc("/cart", handleGetCart).Methods("GET", "OPTIONS")
	protected.HandleFunc("/cart", handleAddToCart).Methods("POST", "OPTIONS")
	protected.HandleFunc("/cart/clear", handleClearCart).Methods("DELETE", "OPTIONS")
	protected.HandleFunc("/orders", handleCreateOrder).Methods("POST", "OPTIONS")
	protected.HandleFunc("/orders", handleListOrders).Methods("GET", "OPTIONS")
	protected.HandleFunc("/orders/{id:[0-9]+}", handleGetOrder).Methods("GET", "OPTIONS")
	protected.HandleFunc("/payment/create-intent", paymentHandler.CreatePaymentIntent).Methods("POST", "OPTIONS")

	// Static files
	r.PathPrefix("/").Handler(http.FileServer(http.Dir("./frontend")))

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	zlog.Info().Msgf("Server starting on port %s", port)
	if err := http.ListenAndServe(":"+port, r); err != nil {
		log.Fatal(err)
	}
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	jsonResponse(w, http.StatusOK, map[string]string{"status": "healthy"})
}

func handleListProducts(w http.ResponseWriter, r *http.Request) {
	page, _ := strconv.Atoi(r.URL.Query().Get("page"))
	perPage, _ := strconv.Atoi(r.URL.Query().Get("per_page"))
	if page < 1 {
		page = 1
	}
	if perPage < 1 {
		perPage = 20
	}
	offset := (page - 1) * perPage

	var total int
	db.QueryRow("SELECT COUNT(*) FROM products").Scan(&total)

	rows, _ := db.Query(
		"SELECT id, name, description, price, category, stock, image_url FROM products ORDER BY created_at DESC LIMIT $1 OFFSET $2",
		perPage, offset,
	)
	defer rows.Close()

	products := []map[string]interface{}{}
	for rows.Next() {
		var id, stock int
		var name, description, category, imageURL string
		var price float64
		rows.Scan(&id, &name, &description, &price, &category, &stock, &imageURL)
		products = append(products, map[string]interface{}{
			"id": id, "name": name, "description": description,
			"price": price, "category": category, "stock": stock, "image_url": imageURL,
		})
	}

	jsonResponse(w, http.StatusOK, map[string]interface{}{
		"products": products,
		"pagination": map[string]int{
			"page":     page,
			"per_page": perPage,
			"total":    total,
		},
	})
}

func handleGetProduct(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	id := vars["id"]

	var name, description, category, imageURL string
	var price float64
	var stock int

	err := db.QueryRow(
		"SELECT name, description, price, category, stock, image_url FROM products WHERE id = $1", id,
	).Scan(&name, &description, &price, &category, &stock, &imageURL)

	if err == sql.ErrNoRows {
		jsonError(w, http.StatusNotFound, "NOT_FOUND", "Product not found")
		return
	}

	jsonResponse(w, http.StatusOK, map[string]interface{}{
		"id": id, "name": name, "description": description,
		"price": price, "category": category, "stock": stock, "image_url": imageURL,
	})
}

func handleSearchProducts(w http.ResponseWriter, r *http.Request) {
	query := r.URL.Query().Get("q")
	searchTerm := "%" + strings.ToLower(query) + "%"

	rows, _ := db.Query(
		"SELECT id, name, description, price, category, stock, image_url FROM products WHERE LOWER(name) LIKE $1 OR LOWER(description) LIKE $1 LIMIT 50",
		searchTerm,
	)
	defer rows.Close()

	products := []map[string]interface{}{}
	for rows.Next() {
		var id, stock int
		var name, description, category, imageURL string
		var price float64
		rows.Scan(&id, &name, &description, &price, &category, &stock, &imageURL)
		products = append(products, map[string]interface{}{
			"id": id, "name": name, "description": description,
			"price": price, "category": category, "stock": stock, "image_url": imageURL,
		})
	}

	jsonResponse(w, http.StatusOK, products)
}

func handleRegister(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Email    string `json:"email"`
		Password string `json:"password"`
		FullName string `json:"full_name"`
	}
	json.NewDecoder(r.Body).Decode(&req)

	var userID int
	err := db.QueryRow(
		"INSERT INTO users (email, password_hash, full_name) VALUES ($1, $2, $3) RETURNING id",
		req.Email, req.Password, req.FullName,
	).Scan(&userID)

	if err != nil {
		jsonError(w, http.StatusBadRequest, "REGISTRATION_FAILED", "Email already exists")
		return
	}

	db.Exec("INSERT INTO carts (user_id) VALUES ($1)", userID)

	token := fmt.Sprintf("token_%d_%d", userID, time.Now().Unix())
	jsonResponse(w, http.StatusCreated, map[string]interface{}{
		"user_id": userID,
		"token":   token,
	})
}

func handleLogin(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	json.NewDecoder(r.Body).Decode(&req)

	var userID int
	var passwordHash string
	err := db.QueryRow("SELECT id, password_hash FROM users WHERE email = $1", req.Email).Scan(&userID, &passwordHash)

	if err == sql.ErrNoRows || passwordHash != req.Password {
		jsonError(w, http.StatusUnauthorized, "INVALID_CREDENTIALS", "Invalid email or password")
		return
	}

	token := fmt.Sprintf("token_%d_%d", userID, time.Now().Unix())
	jsonResponse(w, http.StatusOK, map[string]interface{}{
		"user_id": userID,
		"token":   token,
	})
}

func handleGetCart(w http.ResponseWriter, r *http.Request) {
	userID := r.Context().Value("user_id").(int64)

	var cartID int
	db.QueryRow("SELECT id FROM carts WHERE user_id = $1", userID).Scan(&cartID)

	rows, _ := db.Query(`
		SELECT ci.id, ci.product_id, ci.quantity, p.name, p.price, p.image_url
		FROM cart_items ci JOIN products p ON ci.product_id = p.id
		WHERE ci.cart_id = $1
	`, cartID)
	defer rows.Close()

	items := []map[string]interface{}{}
	var total float64

	for rows.Next() {
		var itemID, productID, quantity int
		var name, imageURL string
		var price float64
		rows.Scan(&itemID, &productID, &quantity, &name, &price, &imageURL)
		subtotal := price * float64(quantity)
		total += subtotal
		items = append(items, map[string]interface{}{
			"id": itemID, "product_id": productID, "quantity": quantity,
			"name": name, "price": price, "image_url": imageURL, "subtotal": subtotal,
		})
	}

	jsonResponse(w, http.StatusOK, map[string]interface{}{
		"items": items,
		"total": total,
	})
}

func handleAddToCart(w http.ResponseWriter, r *http.Request) {
	userID := r.Context().Value("user_id").(int64)

	var req struct {
		ProductID int `json:"product_id"`
		Quantity  int `json:"quantity"`
	}
	json.NewDecoder(r.Body).Decode(&req)

	var cartID int
	db.QueryRow("SELECT id FROM carts WHERE user_id = $1", userID).Scan(&cartID)

	var stock int
	db.QueryRow("SELECT stock FROM products WHERE id = $1", req.ProductID).Scan(&stock)

	if stock < req.Quantity {
		jsonError(w, http.StatusBadRequest, "INSUFFICIENT_STOCK", "Not enough stock")
		return
	}

	db.Exec(`
		INSERT INTO cart_items (cart_id, product_id, quantity)
		VALUES ($1, $2, $3)
		ON CONFLICT (cart_id, product_id) DO UPDATE SET quantity = cart_items.quantity + $3
	`, cartID, req.ProductID, req.Quantity)

	jsonResponse(w, http.StatusOK, map[string]string{"message": "Added to cart"})
}

func handleClearCart(w http.ResponseWriter, r *http.Request) {
	userID := r.Context().Value("user_id").(int64)

	var cartID int
	db.QueryRow("SELECT id FROM carts WHERE user_id = $1", userID).Scan(&cartID)
	db.Exec("DELETE FROM cart_items WHERE cart_id = $1", cartID)

	jsonResponse(w, http.StatusOK, map[string]string{"message": "Cart cleared"})
}

func handleCreateOrder(w http.ResponseWriter, r *http.Request) {
	userID := r.Context().Value("user_id").(int64)

	var cartID int
	db.QueryRow("SELECT id FROM carts WHERE user_id = $1", userID).Scan(&cartID)

	rows, _ := db.Query(`
		SELECT ci.product_id, ci.quantity, p.name, p.price
		FROM cart_items ci JOIN products p ON ci.product_id = p.id
		WHERE ci.cart_id = $1
	`, cartID)
	defer rows.Close()

	type CartItem struct {
		ProductID int
		Quantity  int
		Name      string
		Price     float64
	}

	var items []CartItem
	var total float64

	for rows.Next() {
		var item CartItem
		rows.Scan(&item.ProductID, &item.Quantity, &item.Name, &item.Price)
		total += item.Price * float64(item.Quantity)
		items = append(items, item)
	}

	if len(items) == 0 {
		jsonError(w, http.StatusBadRequest, "EMPTY_CART", "Cart is empty")
		return
	}

	var orderID int
	err := db.QueryRow(
		"INSERT INTO orders (user_id, total, status) VALUES ($1, $2, $3) RETURNING id",
		userID, total, "pending",
	).Scan(&orderID)

	if err != nil {
		jsonError(w, http.StatusInternalServerError, "ORDER_FAILED", "Failed to create order")
		return
	}

	for _, item := range items {
		db.Exec(
			"INSERT INTO order_items (order_id, product_id, product_name, quantity, price, subtotal) VALUES ($1, $2, $3, $4, $5, $6)",
			orderID, item.ProductID, item.Name, item.Quantity, item.Price, float64(item.Quantity)*item.Price,
		)
		db.Exec("UPDATE products SET stock = stock - $1 WHERE id = $2", item.Quantity, item.ProductID)
	}

	db.Exec("DELETE FROM cart_items WHERE cart_id = $1", cartID)

	jsonResponse(w, http.StatusCreated, map[string]interface{}{
		"id":     orderID,
		"total":  total,
		"status": "pending",
	})
}

func handleListOrders(w http.ResponseWriter, r *http.Request) {
	userID := r.Context().Value("user_id").(int64)

	rows, _ := db.Query(
		"SELECT id, total, status, payment_status, created_at FROM orders WHERE user_id = $1 ORDER BY created_at DESC",
		userID,
	)
	defer rows.Close()

	orders := []map[string]interface{}{}
	for rows.Next() {
		var id int
		var total float64
		var status, paymentStatus string
		var createdAt time.Time
		rows.Scan(&id, &total, &status, &paymentStatus, &createdAt)
		orders = append(orders, map[string]interface{}{
			"id":             id,
			"total":          total,
			"status":         status,
			"payment_status": paymentStatus,
			"created_at":     createdAt,
		})
	}

	jsonResponse(w, http.StatusOK, orders)
}

func handleGetOrder(w http.ResponseWriter, r *http.Request) {
	userID := r.Context().Value("user_id").(int64)
	vars := mux.Vars(r)
	orderID := vars["id"]

	var total float64
	var status, paymentStatus string
	var createdAt time.Time
	var ownerID int64

	err := db.QueryRow(
		"SELECT user_id, total, status, payment_status, created_at FROM orders WHERE id = $1",
		orderID,
	).Scan(&ownerID, &total, &status, &paymentStatus, &createdAt)

	if err == sql.ErrNoRows {
		jsonError(w, http.StatusNotFound, "NOT_FOUND", "Order not found")
		return
	}

	if ownerID != userID {
		jsonError(w, http.StatusForbidden, "FORBIDDEN", "Not your order")
		return
	}

	rows, _ := db.Query(
		"SELECT product_name, quantity, price, subtotal FROM order_items WHERE order_id = $1",
		orderID,
	)
	defer rows.Close()

	items := []map[string]interface{}{}
	for rows.Next() {
		var name string
		var quantity int
		var price, subtotal float64
		rows.Scan(&name, &quantity, &price, &subtotal)
		items = append(items, map[string]interface{}{
			"name": name, "quantity": quantity, "price": price, "subtotal": subtotal,
		})
	}

	jsonResponse(w, http.StatusOK, map[string]interface{}{
		"id":             orderID,
		"total":          total,
		"status":         status,
		"payment_status": paymentStatus,
		"items":          items,
		"created_at":     createdAt,
	})
}

func authMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token := r.Header.Get("Authorization")
		if token == "" {
			jsonError(w, http.StatusUnauthorized, "UNAUTHORIZED", "Missing token")
			return
		}

		token = strings.TrimPrefix(token, "Bearer ")
		parts := strings.Split(token, "_")
		if len(parts) < 2 {
			jsonError(w, http.StatusUnauthorized, "INVALID_TOKEN", "Invalid token")
			return
		}

		userID, _ := strconv.ParseInt(parts[1], 10, 64)
		ctx := context.WithValue(r.Context(), "user_id", userID)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")

		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusOK)
			return
		}

		next.ServeHTTP(w, r)
	})
}

func jsonResponse(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success": true,
		"data":    data,
	})
}

func jsonError(w http.ResponseWriter, status int, code, message string) {
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
