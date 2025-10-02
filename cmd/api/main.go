package main

import (
"context"
"fmt"
"log"
"net/http"
"os"
"strconv"
"strings"
"time"
"database/sql"
"encoding/json"

"github.com/gorilla/mux"
"github.com/joho/godotenv"
"github.com/rs/zerolog"
zlog "github.com/rs/zerolog/log"
_ "github.com/lib/pq"
"github.com/go-redis/redis/v8"
"github.com/golang-jwt/jwt/v5"
"golang.org/x/crypto/bcrypt"
"github.com/go-playground/validator/v10"
)

var db *sql.DB
var redisClient *redis.Client
var validate = validator.New()

func main() {
zerolog.TimeFieldFormat = zerolog.TimeFormatUnix
zlog.Logger = zlog.Output(zerolog.ConsoleWriter{Out: os.Stderr, TimeFormat: time.RFC3339})

godotenv.Load()

fmt.Println("╔═══════════════════════════════════════════╗")
fmt.Println("║  IOC Labs E-Commerce Platform v1.0.0     ║")
fmt.Println("║  Quality Assured                          ║")
fmt.Println("╚═══════════════════════════════════════════╝")
fmt.Println()

dbURL := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=%s",
getEnv("DATABASE_HOST", "localhost"),
getEnv("DATABASE_PORT", "5432"),
getEnv("DATABASE_USER", "postgres"),
getEnv("DATABASE_PASSWORD", "postgres"),
getEnv("DATABASE_NAME", "ioc_labs_dev"),
getEnv("DATABASE_SSLMODE", "disable"))

var err error
db, err = sql.Open("postgres", dbURL)
if err != nil {
log.Fatal("Database connection failed:", err)
}
defer db.Close()

db.SetMaxOpenConns(25)
db.SetMaxIdleConns(10)
db.SetConnMaxLifetime(5 * time.Minute)

if err := db.Ping(); err != nil {
log.Fatal("Database ping failed:", err)
}
zlog.Info().Msg("✅ Database connected")

redisClient = redis.NewClient(&redis.Options{
Addr: getEnv("REDIS_HOST", "localhost") + ":" + getEnv("REDIS_PORT", "6379"),
Password: getEnv("REDIS_PASSWORD", ""),
DB: 0,
})
zlog.Info().Msg("✅ Redis connected")

router := setupRouter()

port := getEnv("PORT", "8080")
zlog.Info().Str("port", port).Msg("🚀 Server starting")

srv := &http.Server{
Addr: ":" + port,
Handler: router,
ReadTimeout: 15 * time.Second,
WriteTimeout: 15 * time.Second,
}

log.Fatal(srv.ListenAndServe())
}

func setupRouter() *mux.Router {
router := mux.NewRouter()

router.Use(corsMiddleware)
router.Use(loggingMiddleware)

router.HandleFunc("/health", healthCheck).Methods("GET")
router.HandleFunc("/", rootHandler).Methods("GET")

api := router.PathPrefix("/api").Subrouter()

api.HandleFunc("/register", handleRegister).Methods("POST", "OPTIONS")
api.HandleFunc("/login", handleLogin).Methods("POST", "OPTIONS")
api.HandleFunc("/products", handleListProducts).Methods("GET", "OPTIONS")
api.HandleFunc("/products/{id:[0-9]+}", handleGetProduct).Methods("GET", "OPTIONS")
api.HandleFunc("/products/search", handleSearchProducts).Methods("GET", "OPTIONS")

protected := api.PathPrefix("").Subrouter()
protected.Use(authMiddleware)

protected.HandleFunc("/cart", handleGetCart).Methods("GET", "OPTIONS")
protected.HandleFunc("/cart/add", handleAddToCart).Methods("POST", "OPTIONS")
protected.HandleFunc("/cart/remove/{id:[0-9]+}", handleRemoveFromCart).Methods("DELETE", "OPTIONS")
protected.HandleFunc("/cart/clear", handleClearCart).Methods("DELETE", "OPTIONS")

protected.HandleFunc("/orders", handleCreateOrder).Methods("POST", "OPTIONS")
protected.HandleFunc("/orders", handleListOrders).Methods("GET", "OPTIONS")
protected.HandleFunc("/orders/{id:[0-9]+}", handleGetOrder).Methods("GET", "OPTIONS")

return router
}

func corsMiddleware(next http.Handler) http.Handler {
return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
w.Header().Set("Access-Control-Allow-Origin", "*")
w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
w.Header().Set("Access-Control-Max-Age", "3600")

if r.Method == "OPTIONS" {
w.WriteHeader(http.StatusOK)
return
}
next.ServeHTTP(w, r)
})
}

func loggingMiddleware(next http.Handler) http.Handler {
return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
start := time.Now()
next.ServeHTTP(w, r)
zlog.Info().Str("method", r.Method).Str("path", r.URL.Path).Dur("duration", time.Since(start)).Msg("Request")
})
}

func authMiddleware(next http.Handler) http.Handler {
return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
if r.Method == "OPTIONS" {
return
}

authHeader := r.Header.Get("Authorization")
if authHeader == "" {
jsonError(w, http.StatusUnauthorized, "UNAUTHORIZED", "Missing authorization header")
return
}

tokenString := strings.TrimPrefix(authHeader, "Bearer ")
claims := &jwt.RegisteredClaims{}

token, err := jwt.ParseWithClaims(tokenString, claims, func(token *jwt.Token) (interface{}, error) {
return []byte(getEnv("JWT_SECRET", "")), nil
})

if err != nil || !token.Valid {
jsonError(w, http.StatusUnauthorized, "UNAUTHORIZED", "Invalid token")
return
}

userID, _ := strconv.Atoi(claims.Subject)
ctx := context.WithValue(r.Context(), "user_id", userID)
next.ServeHTTP(w, r.WithContext(ctx))
})
}

func healthCheck(w http.ResponseWriter, r *http.Request) {
jsonResponse(w, http.StatusOK, map[string]string{"status": "healthy", "service": "IOC Labs", "version": "1.0.0"})
}

func rootHandler(w http.ResponseWriter, r *http.Request) {
jsonResponse(w, http.StatusOK, map[string]interface{}{
"service": "IOC Labs E-Commerce API",
"version": "1.0.0",
"tagline": "Quality Assured",
})
}

func handleRegister(w http.ResponseWriter, r *http.Request) {
var req struct {
Email     string `json:"email" validate:"required,email"`
Password  string `json:"password" validate:"required,min=8"`
FirstName string `json:"first_name" validate:"required"`
LastName  string `json:"last_name" validate:"required"`
}

if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
jsonError(w, http.StatusBadRequest, "INVALID_REQUEST", "Invalid request body")
return
}

if err := validate.Struct(req); err != nil {
jsonError(w, http.StatusBadRequest, "VALIDATION_ERROR", err.Error())
return
}

var exists bool
db.QueryRow("SELECT EXISTS(SELECT 1 FROM users WHERE email = $1)", req.Email).Scan(&exists)
if exists {
jsonError(w, http.StatusConflict, "EMAIL_EXISTS", "Email already registered")
return
}

hashedPassword, _ := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)

var userID int
err := db.QueryRow(
"INSERT INTO users (email, password_hash, first_name, last_name) VALUES ($1, $2, $3, $4) RETURNING id",
req.Email, string(hashedPassword), req.FirstName, req.LastName,
).Scan(&userID)

if err != nil {
jsonError(w, http.StatusInternalServerError, "SERVER_ERROR", "Failed to create user")
return
}

token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.RegisteredClaims{
Subject: strconv.Itoa(userID),
ExpiresAt: jwt.NewNumericDate(time.Now().Add(24 * time.Hour)),
})
tokenString, _ := token.SignedString([]byte(getEnv("JWT_SECRET", "")))

jsonResponse(w, http.StatusCreated, map[string]interface{}{
"token": tokenString,
"user": map[string]interface{}{
"id": userID,
"email": req.Email,
"first_name": req.FirstName,
"last_name": req.LastName,
},
})
}

func handleLogin(w http.ResponseWriter, r *http.Request) {
var req struct {
Email    string `json:"email" validate:"required,email"`
Password string `json:"password" validate:"required"`
}

if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
jsonError(w, http.StatusBadRequest, "INVALID_REQUEST", "Invalid request body")
return
}

var userID int
var passwordHash, firstName, lastName string
err := db.QueryRow(
"SELECT id, password_hash, first_name, last_name FROM users WHERE email = $1",
req.Email,
).Scan(&userID, &passwordHash, &firstName, &lastName)

if err != nil {
jsonError(w, http.StatusUnauthorized, "INVALID_CREDENTIALS", "Invalid email or password")
return
}

if err := bcrypt.CompareHashAndPassword([]byte(passwordHash), []byte(req.Password)); err != nil {
jsonError(w, http.StatusUnauthorized, "INVALID_CREDENTIALS", "Invalid email or password")
return
}

token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.RegisteredClaims{
Subject: strconv.Itoa(userID),
ExpiresAt: jwt.NewNumericDate(time.Now().Add(24 * time.Hour)),
})
tokenString, _ := token.SignedString([]byte(getEnv("JWT_SECRET", "")))

jsonResponse(w, http.StatusOK, map[string]interface{}{
"token": tokenString,
"user": map[string]interface{}{
"id": userID,
"email": req.Email,
"first_name": firstName,
"last_name": lastName,
},
})
}

func handleListProducts(w http.ResponseWriter, r *http.Request) {
page, _ := strconv.Atoi(r.URL.Query().Get("page"))
perPage, _ := strconv.Atoi(r.URL.Query().Get("per_page"))
if page < 1 { page = 1 }
if perPage < 1 { perPage = 20 }
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
"page": page, "per_page": perPage, "total": total, "total_pages": (total + perPage - 1) / perPage,
},
})
}

func handleGetProduct(w http.ResponseWriter, r *http.Request) {
vars := mux.Vars(r)
id, _ := strconv.Atoi(vars["id"])

var name, description, category, imageURL string
var price float64
var stock int
err := db.QueryRow(
"SELECT name, description, price, category, stock, image_url FROM products WHERE id = $1", id,
).Scan(&name, &description, &price, &category, &stock, &imageURL)

if err != nil {
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
if query == "" {
jsonError(w, http.StatusBadRequest, "MISSING_QUERY", "Search query required")
return
}

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

func handleGetCart(w http.ResponseWriter, r *http.Request) {
userID := r.Context().Value("user_id").(int)

var cartID int
err := db.QueryRow("SELECT id FROM carts WHERE user_id = $1", userID).Scan(&cartID)
if err != nil {
db.QueryRow("INSERT INTO carts (user_id) VALUES ($1) RETURNING id", userID).Scan(&cartID)
}

rows, _ := db.Query(`
SELECT ci.id, ci.product_id, ci.quantity, p.name, p.price, p.image_url
FROM cart_items ci JOIN products p ON ci.product_id = p.id
WHERE ci.cart_id = $1
`, cartID)
defer rows.Close()

items := []map[string]interface{}{}
total := 0.0
for rows.Next() {
var itemID, productID, quantity int
var name, imageURL string
var price float64
rows.Scan(&itemID, &productID, &quantity, &name, &price, &imageURL)
subtotal := float64(quantity) * price
items = append(items, map[string]interface{}{
"id": itemID, "product_id": productID, "quantity": quantity,
"name": name, "price": price, "subtotal": subtotal, "image_url": imageURL,
})
total += subtotal
}

jsonResponse(w, http.StatusOK, map[string]interface{}{
"id": cartID, "user_id": userID, "items": items, "total": total,
})
}

func handleAddToCart(w http.ResponseWriter, r *http.Request) {
userID := r.Context().Value("user_id").(int)

var req struct {
ProductID int `json:"product_id" validate:"required"`
Quantity  int `json:"quantity" validate:"required,min=1"`
}

if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
jsonError(w, http.StatusBadRequest, "INVALID_REQUEST", "Invalid request body")
return
}

var stock int
db.QueryRow("SELECT stock FROM products WHERE id = $1", req.ProductID).Scan(&stock)
if stock < req.Quantity {
jsonError(w, http.StatusBadRequest, "INSUFFICIENT_STOCK", "Not enough stock")
return
}

var cartID int
err := db.QueryRow("SELECT id FROM carts WHERE user_id = $1", userID).Scan(&cartID)
if err != nil {
db.QueryRow("INSERT INTO carts (user_id) VALUES ($1) RETURNING id", userID).Scan(&cartID)
}

db.Exec(`
INSERT INTO cart_items (cart_id, product_id, quantity)
VALUES ($1, $2, $3)
ON CONFLICT (cart_id, product_id) DO UPDATE SET quantity = cart_items.quantity + $3
`, cartID, req.ProductID, req.Quantity)

handleGetCart(w, r)
}

func handleRemoveFromCart(w http.ResponseWriter, r *http.Request) {
vars := mux.Vars(r)
itemID, _ := strconv.Atoi(vars["id"])

db.Exec("DELETE FROM cart_items WHERE id = $1", itemID)
jsonResponse(w, http.StatusOK, map[string]string{"message": "Item removed"})
}

func handleClearCart(w http.ResponseWriter, r *http.Request) {
userID := r.Context().Value("user_id").(int)

var cartID int
db.QueryRow("SELECT id FROM carts WHERE user_id = $1", userID).Scan(&cartID)
db.Exec("DELETE FROM cart_items WHERE cart_id = $1", cartID)

jsonResponse(w, http.StatusOK, map[string]string{"message": "Cart cleared"})
}

func handleCreateOrder(w http.ResponseWriter, r *http.Request) {
userID := r.Context().Value("user_id").(int)

var cartID int
err := db.QueryRow("SELECT id FROM carts WHERE user_id = $1", userID).Scan(&cartID)
if err != nil {
jsonError(w, http.StatusBadRequest, "CART_NOT_FOUND", "Cart not found")
return
}

rows, _ := db.Query(`
SELECT ci.product_id, ci.quantity, p.name, p.price
FROM cart_items ci JOIN products p ON ci.product_id = p.id
WHERE ci.cart_id = $1
`, cartID)
defer rows.Close()

type orderItem struct {
ProductID int
Quantity  int
Name      string
Price     float64
}

items := []orderItem{}
total := 0.0
for rows.Next() {
var item orderItem
rows.Scan(&item.ProductID, &item.Quantity, &item.Name, &item.Price)
items = append(items, item)
total += float64(item.Quantity) * item.Price
}

if len(items) == 0 {
jsonError(w, http.StatusBadRequest, "CART_EMPTY", "Cart is empty")
return
}

var orderID int
db.QueryRow(
"INSERT INTO orders (user_id, total, status) VALUES ($1, $2, 'pending') RETURNING id",
userID, total,
).Scan(&orderID)

for _, item := range items {
db.Exec(
"INSERT INTO order_items (order_id, product_id, product_name, quantity, price, subtotal) VALUES ($1, $2, $3, $4, $5, $6)",
orderID, item.ProductID, item.Name, item.Quantity, item.Price, float64(item.Quantity)*item.Price,
)
db.Exec("UPDATE products SET stock = stock - $1 WHERE id = $2", item.Quantity, item.ProductID)
}

db.Exec("DELETE FROM cart_items WHERE cart_id = $1", cartID)

jsonResponse(w, http.StatusCreated, map[string]interface{}{
"id": orderID, "total": total, "status": "pending",
})
}

func handleListOrders(w http.ResponseWriter, r *http.Request) {
userID := r.Context().Value("user_id").(int)

rows, _ := db.Query(
"SELECT id, total, status, created_at FROM orders WHERE user_id = $1 ORDER BY created_at DESC",
userID,
)
defer rows.Close()

orders := []map[string]interface{}{}
for rows.Next() {
var id int
var total float64
var status string
var createdAt time.Time
rows.Scan(&id, &total, &status, &createdAt)
orders = append(orders, map[string]interface{}{
"id": id, "total": total, "status": status, "created_at": createdAt,
})
}

jsonResponse(w, http.StatusOK, orders)
}

func handleGetOrder(w http.ResponseWriter, r *http.Request) {
userID := r.Context().Value("user_id").(int)
vars := mux.Vars(r)
orderID, _ := strconv.Atoi(vars["id"])

var total float64
var status string
var createdAt time.Time
err := db.QueryRow(
"SELECT total, status, created_at FROM orders WHERE id = $1 AND user_id = $2",
orderID, userID,
).Scan(&total, &status, &createdAt)

if err != nil {
jsonError(w, http.StatusNotFound, "NOT_FOUND", "Order not found")
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
"id": orderID, "total": total, "status": status, "created_at": createdAt, "items": items,
})
}

func jsonResponse(w http.ResponseWriter, status int, data interface{}) {
w.Header().Set("Content-Type", "application/json")
w.WriteHeader(status)
json.NewEncoder(w).Encode(map[string]interface{}{"success": true, "data": data})
}

func jsonError(w http.ResponseWriter, status int, code, message string) {
w.Header().Set("Content-Type", "application/json")
w.WriteHeader(status)
json.NewEncoder(w).Encode(map[string]interface{}{
"success": false,
"error": map[string]string{"code": code, "message": message},
})
}

func getEnv(key, fallback string) string {
if value := os.Getenv(key); value != "" {
return value
}
return fallback
}
