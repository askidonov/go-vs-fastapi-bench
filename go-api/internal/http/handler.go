package http

import (
	"encoding/json"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/kiril/bench-frameworks/go-api/internal/db"
	"github.com/kiril/bench-frameworks/go-api/internal/model"
)

type Handler struct {
	repo *db.Repository
}

func NewHandler(pool *pgxpool.Pool) http.Handler {
	h := &Handler{
		repo: db.NewRepository(pool),
	}

	r := chi.NewRouter()

	// Middleware - minimal for performance
	r.Use(middleware.Recoverer)

	// Routes
	r.Get("/healthz", h.Health)
	r.Get("/users/{id}", h.GetUser)
	r.Get("/users", h.ListUsers)

	return r
}

func (h *Handler) Health(w http.ResponseWriter, r *http.Request) {
	respondJSON(w, http.StatusOK, model.HealthResponse{Status: "ok"})
}

func (h *Handler) GetUser(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	if id == "" {
		respondJSON(w, http.StatusBadRequest, model.ErrorResponse{Error: "missing_id"})
		return
	}

	user, err := h.repo.GetUserByID(r.Context(), id)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, model.ErrorResponse{Error: "internal_error"})
		return
	}

	if user == nil {
		respondJSON(w, http.StatusNotFound, model.ErrorResponse{Error: "not_found"})
		return
	}

	respondJSON(w, http.StatusOK, user)
}

func (h *Handler) ListUsers(w http.ResponseWriter, r *http.Request) {
	// Parse query parameters
	limit := 50
	offset := 0

	if limitStr := r.URL.Query().Get("limit"); limitStr != "" {
		if l, err := strconv.Atoi(limitStr); err == nil {
			limit = l
			if limit > 200 {
				limit = 200
			}
			if limit < 1 {
				limit = 1
			}
		}
	}

	if offsetStr := r.URL.Query().Get("offset"); offsetStr != "" {
		if o, err := strconv.Atoi(offsetStr); err == nil && o >= 0 {
			offset = o
		}
	}

	// Get users
	users, err := h.repo.ListUsers(r.Context(), limit, offset)
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, model.ErrorResponse{Error: "internal_error"})
		return
	}

	// Get total count
	total, err := h.repo.CountUsers(r.Context())
	if err != nil {
		respondJSON(w, http.StatusInternalServerError, model.ErrorResponse{Error: "internal_error"})
		return
	}

	response := model.UserListResponse{
		Items:  users,
		Limit:  limit,
		Offset: offset,
		Total:  total,
	}

	respondJSON(w, http.StatusOK, response)
}

func respondJSON(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}
