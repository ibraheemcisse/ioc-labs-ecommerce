package middleware

import (
	"net/http"
	"sync"
	"time"

	"github.com/ibraheemcisse/ioc-labs-ecommerce/pkg/response"
)

type rateLimiter struct {
	requests map[string]*clientInfo
	mu       sync.RWMutex
	limit    int
	window   time.Duration
}

type clientInfo struct {
	count      int
	resetAt    time.Time
	lastAccess time.Time
}

func NewRateLimiter(requestsPerWindow int, window time.Duration) *rateLimiter {
	rl := &rateLimiter{
		requests: make(map[string]*clientInfo),
		limit:    requestsPerWindow,
		window:   window,
	}

	go rl.cleanup()
	return rl
}

func (rl *rateLimiter) cleanup() {
	ticker := time.NewTicker(time.Minute)
	defer ticker.Stop()

	for range ticker.C {
		rl.mu.Lock()
		now := time.Now()
		for ip, info := range rl.requests {
			if now.Sub(info.lastAccess) > 5*time.Minute {
				delete(rl.requests, ip)
			}
		}
		rl.mu.Unlock()
	}
}

func (rl *rateLimiter) allow(ip string) bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	now := time.Now()
	info, exists := rl.requests[ip]

	if !exists || now.After(info.resetAt) {
		rl.requests[ip] = &clientInfo{
			count:      1,
			resetAt:    now.Add(rl.window),
			lastAccess: now,
		}
		return true
	}

	info.lastAccess = now

	if info.count >= rl.limit {
		return false
	}

	info.count++
	return true
}

func (rl *rateLimiter) Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ip := r.RemoteAddr

		if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
			ip = xff
		} else if xri := r.Header.Get("X-Real-IP"); xri != "" {
			ip = xri
		}

		if !rl.allow(ip) {
			response.Error(w, http.StatusTooManyRequests, "RATE_LIMIT_EXCEEDED", "Too many requests. Please try again later.")
			return
		}

		next.ServeHTTP(w, r)
	})
}
