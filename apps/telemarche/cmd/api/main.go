// Télémarché — l'API catalogue et commandes, fil rouge des TP.
//
// Le même binaire fonctionne dans deux modes :
//
//   - sans DB_HOST : catalogue et commandes EN MÉMOIRE (jour 1, aucune base) ;
//   - avec DB_HOST : catalogue et commandes dans PostgreSQL (TP06).
//
// Appelé sous le nom « migrate » (/app/migrate), ou avec l'argument « migrate »,
// il crée le schéma et le catalogue de départ puis se termine : c'est la tâche
// lancée par un conteneur d'initialisation ou un Job.
//
// Avec l'argument « --self-test », il contrôle ce qu'il embarque (version,
// catalogue de départ) sans rien écouter, puis se termine : code 0 si tout est
// cohérent, 1 sinon. C'est le contrôle appelé par le hook post-commit du TP04.
//
// Configuration (variables d'environnement) :
//
//	PORT               port d'écoute (défaut : 8080)
//	LOG_LEVEL          debug, info, warn ou error (défaut : info) ; toute autre
//	                   valeur arrête le programme (exit 1)
//	DB_HOST, DB_PORT   connexion PostgreSQL (DB_HOST vide = mémoire)
//	DB_USER / POSTGRESQL_USER / POSTGRES_USER              utilisateur (le premier défini l'emporte)
//	DB_PASSWORD / POSTGRESQL_PASSWORD / POSTGRES_PASSWORD  mot de passe
//	DB_NAME / POSTGRESQL_DATABASE                          base (défaut : telemarche)
//	CONFIG_FILE        fichier de propriétés optionnel (défaut :
//	                   /etc/api/application.properties)
//	STARTUP_SECONDS    durée du démarrage simulé, pendant laquelle /healthz et
//	                   /ready répondent 503 (défaut : 3)
//	SHUTDOWN_SECONDS   délai de vidange après SIGTERM (défaut : 5)
//	MEMORY_BALLAST_MB  mémoire réservée au démarrage, pour observer un
//	                   OOMKilled (défaut : 0)
//	JOURNAL_DIR        répertoire où tenir un journal des commandes
//	                   (commandes.log). Vide : pas de journal. S'il est
//	                   renseigné et que l'écriture y est refusée, le programme
//	                   s'arrête (exit 1) : c'est la panne du TP02
//
// Points d'entrée : /healthz (vivant), /ready (prêt à recevoir du trafic),
// /version, /metrics (format Prometheus), et l'API métier sous /api/.
package main

import (
	"bufio"
	"context"
	_ "embed"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Injectée au build : -ldflags "-X main.version=1.0"
var version = "dev"

var (
	log      *slog.Logger
	hostname string
	started  atomic.Bool // vrai une fois le démarrage terminé
	draining atomic.Bool // vrai dès la réception de SIGTERM
)

func main() {
	level, err := parseLevel(env("LOG_LEVEL", "info"))
	if err != nil {
		fmt.Fprintln(os.Stderr, "configuration invalide :", err)
		os.Exit(1)
	}
	log = slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: level}))
	hostname, _ = os.Hostname()

	if err := loadCatalogue(); err != nil {
		log.Error("catalogue embarqué illisible", "err", err)
		os.Exit(1)
	}
	if len(os.Args) > 1 && os.Args[1] == "--self-test" {
		os.Exit(selfTest())
	}

	if filepath.Base(os.Args[0]) == "migrate" || (len(os.Args) > 1 && os.Args[1] == "migrate") {
		os.Exit(migrate())
	}

	if mb := envInt("MEMORY_BALLAST_MB", 0); mb > 0 {
		ballast = make([]byte, mb<<20)
		for i := range ballast { // toucher chaque page : la mémoire est réellement consommée
			ballast[i] = 1
		}
		log.Info("mémoire réservée", "mo", mb)
	}

	if dir := os.Getenv("JOURNAL_DIR"); dir != "" {
		f, err := os.OpenFile(filepath.Join(dir, "commandes.log"), os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o664)
		if err != nil {
			log.Error("journal des commandes", "err", err)
			os.Exit(1)
		}
		journal = f
		log.Info("journal des commandes ouvert", "fichier", f.Name())
	}

	var st store = newMemStore()
	mode := "memoire"
	if os.Getenv("DB_HOST") != "" {
		pg, err := newPgStore(context.Background())
		if err != nil {
			log.Error("DSN PostgreSQL invalide", "err", err)
			os.Exit(1)
		}
		st, mode = pg, "postgresql"
	}

	app := &server{store: st, mode: mode, configFile: env("CONFIG_FILE", "/etc/api/application.properties")}
	port := env("PORT", "8080")
	srv := &http.Server{Addr: ":" + port, Handler: app.routes(), ReadHeaderTimeout: 5 * time.Second}

	log.Info("démarrage", "version", version, "stockage", mode, "port", port)
	go func() {
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Error("serveur HTTP", "err", err)
			os.Exit(1)
		}
	}()

	// Démarrage simulé : une vraie application charge un cache, ouvre ses
	// connexions… Pendant ce temps, elle ne doit recevoir aucun trafic.
	time.Sleep(time.Duration(envInt("STARTUP_SECONDS", 3)) * time.Second)
	started.Store(true)
	log.Info("démarrage terminé")

	// Arrêt propre : /ready passe à 503 pour que le Service retire le pod, on
	// continue de servir pendant SHUTDOWN_SECONDS, puis on termine les requêtes
	// en cours. C'est ce qui rend un rolling update réellement sans coupure.
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGTERM, syscall.SIGINT)
	<-stop
	draining.Store(true)
	delay := time.Duration(envInt("SHUTDOWN_SECONDS", 5)) * time.Second
	log.Info("arrêt demandé, vidange", "delai", delay)
	time.Sleep(delay)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = srv.Shutdown(ctx)
	st.Close()
	log.Info("arrêté")
}

var ballast []byte

// journal : fichier des commandes, ouvert seulement si JOURNAL_DIR est renseigné.
var (
	journal   *os.File
	journalMu sync.Mutex
)

func journaliser(o order) {
	if journal == nil {
		return
	}
	journalMu.Lock()
	defer journalMu.Unlock()
	fmt.Fprintf(journal, "%s commande=%d produit=%d quantite=%d pod=%s\n",
		o.CreatedAt.Format(time.RFC3339), o.ID, o.ProductID, o.Quantity, o.Pod)
}

// ---------------------------------------------------------------------------
// HTTP
// ---------------------------------------------------------------------------

type server struct {
	store store
	mode  string
	// Relu à chaque appel de /api/info : on y voit la mise à jour d'une
	// ConfigMap montée en volume, sans redémarrer le pod.
	configFile string
}

func (s *server) routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", s.healthz)
	mux.HandleFunc("GET /ready", s.ready)
	mux.HandleFunc("GET /version", s.version)
	mux.HandleFunc("GET /metrics", s.metricsHandler)
	mux.HandleFunc("GET /api/info", s.info)
	mux.HandleFunc("GET /api/products", s.products)
	mux.HandleFunc("GET /api/products/{id}", s.product)
	mux.HandleFunc("GET /api/orders", s.orders)
	mux.HandleFunc("POST /api/orders", s.createOrder)
	mux.HandleFunc("GET /api/charge", s.charge)
	return instrument(warmingUp(mux))
}

// warmingUp refuse le trafic métier (/api/…) tant que le démarrage n'est pas
// terminé, comme une application qui charge encore son cache. Sans readiness
// probe, un pod tout juste créé reçoit pourtant ce trafic : d'où les erreurs
// pendant un rolling update mal configuré.
func warmingUp(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !started.Load() && strings.HasPrefix(r.URL.Path, "/api/") {
			http.Error(w, "démarrage en cours", http.StatusServiceUnavailable)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// /healthz répond à la question « le processus est-il vivant ? ». Il ne dépend
// volontairement PAS de la base : si la base tombe, redémarrer l'API n'y
// changerait rien.
func (s *server) healthz(w http.ResponseWriter, _ *http.Request) {
	if !started.Load() {
		http.Error(w, "démarrage en cours", http.StatusServiceUnavailable)
		return
	}
	fmt.Fprintln(w, "ok")
}

// /ready répond à « puis-je recevoir du trafic maintenant ? » : démarrage
// terminé, pas en cours d'arrêt, et stockage joignable.
func (s *server) ready(w http.ResponseWriter, r *http.Request) {
	switch {
	case !started.Load():
		http.Error(w, "démarrage en cours", http.StatusServiceUnavailable)
	case draining.Load():
		http.Error(w, "arrêt en cours", http.StatusServiceUnavailable)
	default:
		// Moins que le timeoutSeconds par défaut d'une probe (1 s) : sinon le
		// kubelet abandonne d'abord, et le journal ne dit que « context canceled »
		// au lieu de la vraie cause.
		ctx, cancel := context.WithTimeout(context.Background(), 800*time.Millisecond)
		defer cancel()
		if err := s.store.Ready(ctx); err != nil {
			if errors.Is(err, context.DeadlineExceeded) {
				err = errors.New("base injoignable (pas de réponse en 800 ms)")
			}
			log.Warn("pas prêt", "err", err)
			http.Error(w, "stockage indisponible : "+err.Error(), http.StatusServiceUnavailable)
			return
		}
		fmt.Fprintln(w, "ready")
	}
}

func (s *server) version(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"service": "api", "version": version})
}

func (s *server) info(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"service":  "api",
		"version":  version,
		"pod":      hostname,
		"stockage": s.mode,
		"config":   readConfig(s.configFile),
	})
}

func (s *server) products(w http.ResponseWriter, r *http.Request) {
	ps, err := s.store.Products(r.Context())
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, ps)
}

func (s *server) product(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.Atoi(r.PathValue("id"))
	if err != nil {
		http.Error(w, "identifiant invalide", http.StatusBadRequest)
		return
	}
	p, err := s.store.Product(r.Context(), id)
	if errors.Is(err, errNotFound) {
		http.Error(w, "produit introuvable", http.StatusNotFound)
		return
	}
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, p)
}

func (s *server) orders(w http.ResponseWriter, r *http.Request) {
	list, err := s.store.Orders(r.Context())
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, list)
}

func (s *server) createOrder(w http.ResponseWriter, r *http.Request) {
	var in struct {
		ProductID int `json:"product_id"`
		Quantity  int `json:"quantity"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&in); err != nil || in.Quantity < 1 {
		http.Error(w, `corps attendu : {"product_id": 1, "quantity": 2}`, http.StatusBadRequest)
		return
	}
	o, err := s.store.CreateOrder(r.Context(), in.ProductID, in.Quantity)
	if errors.Is(err, errNotFound) {
		http.Error(w, "produit introuvable", http.StatusNotFound)
		return
	}
	if err != nil {
		s.fail(w, err)
		return
	}
	ordersTotal.Add(1)
	journaliser(o)
	writeJSON(w, http.StatusCreated, o)
}

// /api/charge?ms=200 occupe un cœur pendant la durée demandée (1 s au plus) :
// de quoi faire monter la consommation CPU et déclencher un HPA.
func (s *server) charge(w http.ResponseWriter, r *http.Request) {
	ms, err := strconv.Atoi(r.URL.Query().Get("ms"))
	if err != nil || ms < 1 {
		ms = 100
	}
	ms = min(ms, 1000)
	end := time.Now().Add(time.Duration(ms) * time.Millisecond)
	n := 0
	for time.Now().Before(end) {
		n++
	}
	writeJSON(w, http.StatusOK, map[string]any{"pod": hostname, "ms": ms, "iterations": n})
}

func (s *server) fail(w http.ResponseWriter, err error) {
	log.Error("requête en échec", "err", err)
	http.Error(w, "erreur interne", http.StatusInternalServerError)
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

// ---------------------------------------------------------------------------
// Métriques Prometheus (format texte, sans dépendance)
// ---------------------------------------------------------------------------

var (
	reqMu       sync.Mutex
	reqCount    = map[[3]string]int64{} // méthode, route, code
	ordersTotal atomic.Int64
)

type statusWriter struct {
	http.ResponseWriter
	code int
}

func (s *statusWriter) WriteHeader(code int) { s.code = code; s.ResponseWriter.WriteHeader(code) }

func instrument(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		sw := &statusWriter{ResponseWriter: w, code: http.StatusOK}
		next.ServeHTTP(sw, r)
		route := r.Pattern
		if route == "" {
			route = "inconnue"
		}
		reqMu.Lock()
		reqCount[[3]string{r.Method, route, strconv.Itoa(sw.code)}]++
		reqMu.Unlock()
		log.Debug("requête", "methode", r.Method, "chemin", r.URL.Path, "code", sw.code)
	})
}

func (s *server) metricsHandler(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "text/plain; version=0.0.4")
	fmt.Fprintln(w, "# HELP telemarche_build_info Version de l'API.")
	fmt.Fprintln(w, "# TYPE telemarche_build_info gauge")
	fmt.Fprintf(w, "telemarche_build_info{version=%q,stockage=%q} 1\n", version, s.mode)
	fmt.Fprintln(w, "# HELP telemarche_orders_total Commandes créées par ce pod.")
	fmt.Fprintln(w, "# TYPE telemarche_orders_total counter")
	fmt.Fprintf(w, "telemarche_orders_total %d\n", ordersTotal.Load())
	fmt.Fprintln(w, "# HELP telemarche_http_requests_total Requêtes HTTP traitées.")
	fmt.Fprintln(w, "# TYPE telemarche_http_requests_total counter")
	reqMu.Lock()
	keys := make([][3]string, 0, len(reqCount))
	for k := range reqCount {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool { return fmt.Sprint(keys[i]) < fmt.Sprint(keys[j]) })
	for _, k := range keys {
		fmt.Fprintf(w, "telemarche_http_requests_total{method=%q,route=%q,code=%q} %d\n", k[0], k[1], k[2], reqCount[k])
	}
	reqMu.Unlock()
}

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

func env(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func envInt(k string, def int) int {
	v, err := strconv.Atoi(os.Getenv(k))
	if err != nil {
		return def
	}
	return v
}

func parseLevel(s string) (slog.Level, error) {
	switch strings.ToLower(s) {
	case "debug":
		return slog.LevelDebug, nil
	case "info":
		return slog.LevelInfo, nil
	case "warn":
		return slog.LevelWarn, nil
	case "error":
		return slog.LevelError, nil
	}
	return 0, fmt.Errorf("LOG_LEVEL=%q (valeurs acceptées : debug, info, warn, error)", s)
}

// readConfig lit un fichier « clé=valeur » (lignes vides et # ignorées). Son
// absence n'est pas une erreur : le fichier n'existe que si une ConfigMap est
// montée.
func readConfig(path string) map[string]string {
	cfg := map[string]string{}
	f, err := os.Open(path)
	if err != nil {
		return cfg
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if k, v, ok := strings.Cut(line, "="); ok {
			cfg[strings.TrimSpace(k)] = strings.TrimSpace(v)
		}
	}
	return cfg
}

// ---------------------------------------------------------------------------
// Stockage
// ---------------------------------------------------------------------------

type product struct {
	ID    int    `json:"id"`
	Name  string `json:"nom"`
	Price int    `json:"prix_centimes"`
}

type order struct {
	ID        int       `json:"id"`
	ProductID int       `json:"product_id"`
	Quantity  int       `json:"quantity"`
	Pod       string    `json:"pod"`
	CreatedAt time.Time `json:"created_at"`
}

var errNotFound = errors.New("introuvable")

// Le catalogue de départ est un fichier de données embarqué dans le binaire.
// Une faute dans ce fichier ne casse pas la compilation : c'est exactement le
// genre d'erreur qu'un contrôle avant publication (--self-test) doit attraper.
//
//go:embed catalogue.json
var catalogueJSON []byte

var catalogue []product

func loadCatalogue() error {
	return json.Unmarshal(catalogueJSON, &catalogue)
}

// selfTest contrôle ce que le binaire embarque. Il n'ouvre aucun port et ne
// dépend d'aucun service : il peut tourner dans le conteneur isolé d'un hook
// post-commit.
func selfTest() int {
	var fautes []string
	if version == "" {
		fautes = append(fautes, "version vide")
	}
	if len(catalogue) == 0 {
		fautes = append(fautes, "catalogue vide")
	}
	vus := map[int]bool{}
	for _, p := range catalogue {
		switch {
		case p.ID < 1:
			fautes = append(fautes, fmt.Sprintf("produit %q : identifiant invalide (%d)", p.Name, p.ID))
		case vus[p.ID]:
			fautes = append(fautes, fmt.Sprintf("produit %d : identifiant en double", p.ID))
		}
		vus[p.ID] = true
		if strings.TrimSpace(p.Name) == "" {
			fautes = append(fautes, fmt.Sprintf("produit %d : nom vide", p.ID))
		}
		if p.Price <= 0 {
			fautes = append(fautes, fmt.Sprintf("produit %d « %s » : prix invalide (%d)", p.ID, p.Name, p.Price))
		}
	}
	if len(fautes) > 0 {
		for _, f := range fautes {
			fmt.Println("self-test : ÉCHEC :", f)
		}
		return 1
	}
	fmt.Printf("self-test : OK (version %s, %d produits)\n", version, len(catalogue))
	return 0
}

type store interface {
	Ready(ctx context.Context) error
	Products(ctx context.Context) ([]product, error)
	Product(ctx context.Context, id int) (product, error)
	Orders(ctx context.Context) ([]order, error)
	CreateOrder(ctx context.Context, productID, qty int) (order, error)
	Close()
}

// memStore : tout est perdu au redémarrage du pod, et chaque réplica a SES
// commandes. C'est précisément le problème que résout la base du TP06.
type memStore struct {
	mu     sync.Mutex
	orders []order
}

func newMemStore() *memStore                    { return &memStore{} }
func (m *memStore) Ready(context.Context) error { return nil }
func (m *memStore) Close()                      {}

func (m *memStore) Products(context.Context) ([]product, error) { return catalogue, nil }

func (m *memStore) Product(_ context.Context, id int) (product, error) {
	for _, p := range catalogue {
		if p.ID == id {
			return p, nil
		}
	}
	return product{}, errNotFound
}

func (m *memStore) Orders(context.Context) ([]order, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	return append([]order{}, m.orders...), nil
}

func (m *memStore) CreateOrder(ctx context.Context, productID, qty int) (order, error) {
	if _, err := m.Product(ctx, productID); err != nil {
		return order{}, err
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	o := order{ID: len(m.orders) + 1, ProductID: productID, Quantity: qty, Pod: hostname, CreatedAt: time.Now().UTC()}
	m.orders = append(m.orders, o)
	return o, nil
}

type pgStore struct{ db *pgxpool.Pool }

func dsn() string {
	// Trois familles de noms sont acceptées, pour qu'un même Secret serve à la
	// base et à l'API : DB_*, POSTGRESQL_* (images Red Hat) et POSTGRES_*
	// (image de Docker Hub).
	user := env("DB_USER", env("POSTGRESQL_USER", env("POSTGRES_USER", "telemarche")))
	pass := env("DB_PASSWORD", env("POSTGRESQL_PASSWORD", os.Getenv("POSTGRES_PASSWORD")))
	name := env("DB_NAME", env("POSTGRESQL_DATABASE", "telemarche"))
	u := url.URL{
		Scheme:   "postgres",
		User:     url.UserPassword(user, pass),
		Host:     env("DB_HOST", "db") + ":" + env("DB_PORT", "5432"),
		Path:     "/" + name,
		RawQuery: "sslmode=disable&connect_timeout=3",
	}
	return u.String()
}

// newPgStore ne se connecte pas : le pool ouvre ses connexions à la demande.
// L'API démarre donc même si la base n'est pas encore là ; c'est /ready qui
// le signale.
func newPgStore(ctx context.Context) (*pgStore, error) {
	cfg, err := pgxpool.ParseConfig(dsn())
	if err != nil {
		return nil, err
	}
	cfg.MaxConns = 5
	db, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		return nil, err
	}
	return &pgStore{db: db}, nil
}

func (p *pgStore) Close() { p.db.Close() }

func (p *pgStore) Ready(ctx context.Context) error {
	var ok bool
	if err := p.db.QueryRow(ctx, "SELECT to_regclass('public.products') IS NOT NULL").Scan(&ok); err != nil {
		return err
	}
	if !ok {
		return errors.New("schéma absent : lancer la migration (/app/migrate)")
	}
	return nil
}

func (p *pgStore) Products(ctx context.Context) ([]product, error) {
	rows, err := p.db.Query(ctx, "SELECT id, name, price_cents FROM products ORDER BY id")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	ps := []product{}
	for rows.Next() {
		var x product
		if err := rows.Scan(&x.ID, &x.Name, &x.Price); err != nil {
			return nil, err
		}
		ps = append(ps, x)
	}
	return ps, rows.Err()
}

func (p *pgStore) Product(ctx context.Context, id int) (product, error) {
	var x product
	err := p.db.QueryRow(ctx, "SELECT id, name, price_cents FROM products WHERE id=$1", id).Scan(&x.ID, &x.Name, &x.Price)
	if errors.Is(err, pgx.ErrNoRows) {
		return x, errNotFound
	}
	return x, err
}

func (p *pgStore) Orders(ctx context.Context) ([]order, error) {
	rows, err := p.db.Query(ctx, "SELECT id, product_id, quantity, pod, created_at FROM orders ORDER BY id")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	list := []order{}
	for rows.Next() {
		var o order
		if err := rows.Scan(&o.ID, &o.ProductID, &o.Quantity, &o.Pod, &o.CreatedAt); err != nil {
			return nil, err
		}
		list = append(list, o)
	}
	return list, rows.Err()
}

func (p *pgStore) CreateOrder(ctx context.Context, productID, qty int) (order, error) {
	if _, err := p.Product(ctx, productID); err != nil {
		return order{}, err
	}
	o := order{ProductID: productID, Quantity: qty, Pod: hostname}
	err := p.db.QueryRow(ctx,
		"INSERT INTO orders (product_id, quantity, pod) VALUES ($1, $2, $3) RETURNING id, created_at",
		productID, qty, hostname).Scan(&o.ID, &o.CreatedAt)
	return o, err
}

// migrate crée le schéma et le catalogue de départ. Idempotente : on peut la
// relancer sans risque, ce qu'exige un Job (qui peut réessayer).
func migrate() int {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	st, err := newPgStore(ctx)
	if err != nil {
		log.Error("DSN PostgreSQL invalide", "err", err)
		return 1
	}
	defer st.Close()

	for {
		if err = st.db.Ping(ctx); err == nil {
			break
		}
		log.Warn("base pas encore joignable, nouvel essai", "err", err)
		select {
		case <-ctx.Done():
			log.Error("base injoignable", "err", err)
			return 1
		case <-time.After(2 * time.Second):
		}
	}

	stmts := []string{
		`CREATE TABLE IF NOT EXISTS products (
			id INTEGER PRIMARY KEY,
			name TEXT NOT NULL,
			price_cents INTEGER NOT NULL)`,
		`CREATE TABLE IF NOT EXISTS orders (
			id SERIAL PRIMARY KEY,
			product_id INTEGER NOT NULL REFERENCES products(id),
			quantity INTEGER NOT NULL,
			pod TEXT NOT NULL,
			created_at TIMESTAMPTZ NOT NULL DEFAULT now())`,
	}
	for _, s := range stmts {
		if _, err := st.db.Exec(ctx, s); err != nil {
			log.Error("migration", "err", err)
			return 1
		}
	}
	for _, p := range catalogue {
		if _, err := st.db.Exec(ctx,
			"INSERT INTO products (id, name, price_cents) VALUES ($1, $2, $3) ON CONFLICT (id) DO NOTHING",
			p.ID, p.Name, p.Price); err != nil {
			log.Error("catalogue", "err", err)
			return 1
		}
	}
	log.Info("migration terminée", "version", version, "produits", len(catalogue))
	return 0
}
