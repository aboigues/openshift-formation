// Bonjour — la plus petite application possible, pour découvrir Source-to-Image.
//
// Un seul programme, à la racine du dépôt, sans dépendance : l'image de
// construction go-toolset sait la compiler telle quelle, sans Dockerfile.
//
//	oc new-app --name=bonjour \
//	  registry.access.redhat.com/ubi10/go-toolset:10.3~https://github.com/aboigues/openshift-formation \
//	  --context-dir=apps/bonjour
//
// Configuration : PORT (8080), MESSAGE (« Bonjour depuis OpenShift »).
package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
)

func env(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func main() {
	hote, _ := os.Hostname()
	message := env("MESSAGE", "Bonjour depuis OpenShift")
	http.HandleFunc("/", func(w http.ResponseWriter, _ *http.Request) {
		fmt.Fprintf(w, "%s (pod %s, uid %d)\n", message, hote, os.Getuid())
	})
	http.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) { fmt.Fprintln(w, "ok") })
	port := env("PORT", "8080")
	log.Printf("bonjour : écoute sur le port %s", port)
	log.Fatal(http.ListenAndServe(":"+port, nil))
}
