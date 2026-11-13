# telemach-go-builder

Une image de construction Source-to-Image pour les services Go de Telemach. C'est la référence de ce que l'on fabrique au [TP05](../../tp05-personnaliser-s2i/) (niveau 3 de la personnalisation).

L'image `go-toolset` de Red Hat ne sait construire qu'un programme placé à la racine du dépôt. Celle-ci ajoute une variable, `COMPOSANT`, qui désigne le programme à construire dans `cmd/` : un même dépôt peut donc produire plusieurs images.

```bash
# La construire dans son projet
oc new-build --name=telemach-go-builder --strategy=docker \
  https://github.com/aboigues/openshift-formation --context-dir=builders/telemach-go-builder

# S'en servir
oc new-app --name=web telemach-go-builder~https://github.com/aboigues/openshift-formation \
  --context-dir=apps/telemarche --build-env=COMPOSANT=web
```

| Script | Rôle |
|---|---|
| `s2i/bin/assemble` | construit `cmd/<COMPOSANT>` dans `/opt/app-root/app` ; échoue franchement si rien n'est désigné |
| `s2i/bin/run` | lance l'application, par `exec` |
| `s2i/bin/save-artifacts` | sauvegarde les dépendances pour un build incrémental |
| `s2i/bin/usage` | le mode d'emploi, affiché quand l'image est lancée sans sources |

`./test/run` vérifie l'image sur le poste, avec podman ou docker : elle construit web et api, puis démarre la vitrine sous un UID arbitraire.
