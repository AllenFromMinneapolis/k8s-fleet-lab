// shop-api: a small product-search API used to practice secure delivery on GCP.
// Security points: API key from Secret Manager (secret.go), constant-time key check,
// parameterized SQL, server timeouts. Telemetry: OpenTelemetry (telemetry.go).
package main

import (
	"context"
	"crypto/subtle"
	"database/sql"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/metric"
	"go.opentelemetry.io/otel/trace"
	_ "modernc.org/sqlite"
)

var (
	tracer = otel.Tracer("shop-api")
	meter  = otel.Meter("shop-api")
)

type product struct {
	ID    int     `json:"id"`
	Name  string  `json:"name"`
	Price float64 `json:"price"`
}

type server struct {
	db       *sql.DB
	apiKey   []byte
	searches metric.Int64Counter
}

func main() {
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, nil)))
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	shutdownTelemetry, err := setupTelemetry(ctx)
	if err != nil {
		fatal("telemetry setup failed", err)
	}
	defer func() {
		if err := shutdownTelemetry(context.Background()); err != nil {
			slog.Error("telemetry shutdown failed", "err", err)
		}
	}()

	key, err := loadAPIKey(ctx)
	if err != nil {
		fatal("could not load API key", err)
	}
	slog.Info("API key loaded") // never log the value itself

	db, err := openDB()
	if err != nil {
		fatal("database setup failed", err)
	}
	searches, err := meter.Int64Counter("product_searches",
		metric.WithDescription("Product searches, by whether anything was found"))
	if err != nil {
		fatal("metric setup failed", err)
	}
	s := &server{db: db, apiKey: []byte(key), searches: searches}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) })
	mux.Handle("GET /products", s.requireAPIKey(http.HandlerFunc(s.searchProducts)))

	// otelhttp is the Go "auto-instrumentation": a span and metrics for every request.
	handler := otelhttp.NewHandler(mux, "shop-api",
		otelhttp.WithSpanNameFormatter(func(_ string, r *http.Request) string { return r.Method + " " + r.URL.Path }),
		otelhttp.WithFilter(func(r *http.Request) bool { return r.URL.Path != "/healthz" }))

	// Timeouts stop slow clients from tying up the server (Slowloris).
	srv := &http.Server{
		Addr:              ":8080",
		Handler:           handler,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
	}
	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err := srv.Shutdown(shutdownCtx); err != nil {
			slog.Error("shutdown failed", "err", err)
		}
	}()
	slog.Info("listening", "addr", srv.Addr)
	if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		fatal("server failed", err)
	}
}

func (s *server) requireAPIKey(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		got := []byte(r.Header.Get("X-API-Key"))
		// Constant-time compare: response time doesn't reveal how much of the key matched.
		if subtle.ConstantTimeCompare(got, s.apiKey) != 1 {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (s *server) searchProducts(w http.ResponseWriter, r *http.Request) {
	name := r.URL.Query().Get("name")
	if len(name) > 50 {
		http.Error(w, "name too long", http.StatusBadRequest)
		return
	}

	ctx, span := tracer.Start(r.Context(), "db.search_products")
	defer span.End()

	// The "?" placeholder sends name to the database as data, never as SQL,
	// so input like  ' OR '1'='1  can't change the query (no SQL injection).
	rows, err := s.db.QueryContext(ctx, "SELECT id, name, price FROM products WHERE name LIKE ?", "%"+name+"%")
	if err != nil {
		s.fail(w, span, err)
		return
	}
	defer rows.Close()

	products := []product{}
	for rows.Next() {
		var p product
		if err := rows.Scan(&p.ID, &p.Name, &p.Price); err != nil {
			s.fail(w, span, err)
			return
		}
		products = append(products, p)
	}
	if err := rows.Err(); err != nil {
		s.fail(w, span, err)
		return
	}

	span.SetAttributes(attribute.Int("db.rows_returned", len(products)))
	s.searches.Add(ctx, 1, metric.WithAttributes(attribute.Bool("found", len(products) > 0)))
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(products); err != nil {
		slog.Error("encode failed", "err", err)
	}
}

// fail records the real error in the trace but tells the caller nothing about internals.
func (s *server) fail(w http.ResponseWriter, span trace.Span, err error) {
	span.RecordError(err)
	span.SetStatus(codes.Error, "query failed")
	http.Error(w, "internal error", http.StatusInternalServerError)
}

func openDB() (*sql.DB, error) {
	db, err := sql.Open("sqlite", ":memory:")
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1) // an in-memory database lives inside one connection
	_, err = db.Exec(`CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT, price REAL);
		INSERT INTO products (name, price) VALUES ('coffee', 3.50), ('sandwich', 8.25), ('salad', 9.75), ('cookie', 2.00);`)
	return db, err
}

func fatal(msg string, err error) {
	slog.Error(msg, "err", err)
	os.Exit(1)
}
