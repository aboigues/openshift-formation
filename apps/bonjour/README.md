# Bonjour

La plus petite application du dépôt : un seul fichier Go, à la racine, sans dépendance. Elle sert à découvrir Source-to-Image (module 1, puis module 4) : l'image de construction `go-toolset` la compile sans Dockerfile ni script.

```bash
oc new-app --name=bonjour \
  registry.access.redhat.com/ubi10/go-toolset:10.3~https://github.com/aboigues/openshift-formation \
  --context-dir=apps/bonjour
oc logs -f buildconfig/bonjour
oc create route edge bonjour --service=bonjour
```

| Variable | Défaut | Effet |
|---|---|---|
| `PORT` | `8080` | port d'écoute |
| `MESSAGE` | `Bonjour depuis OpenShift` | le texte renvoyé |

La réponse affiche l'UID sous lequel tourne le processus : de quoi constater l'UID arbitraire d'OpenShift.
