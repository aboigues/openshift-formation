# TP07 — Santé et stratégies de déploiement

> Durée estimée : 1 h 15 · Module 7 · Projet de travail : le vôtre

**Avant de commencer, faites place nette** : `../scripts/place-nette.sh`.

## 🎬 Le contexte

La nouvelle API charge un cache au démarrage : **20 secondes** avant de pouvoir répondre. Depuis, chaque mise en production coupe la boutique quelques instants, et une première tentative de surveillance a fait pire : OpenShift redémarre l'API en boucle.

Vous allez apprendre à OpenShift à **lire la santé** de l'API (trois sondes, trois questions), à la mettre à jour **sans perdre une requête**, puis à essayer la version 1.1 **sur une requête sur dix** avant de la généraliser.

| Sonde | Question | Si elle échoue |
|---|---|---|
| `startupProbe` | as-tu fini de démarrer ? | on attend ; au-delà de `failureThreshold`, redémarrage |
| `readinessProbe` | puis-je t'envoyer du trafic ? | le pod sort du Service, **sans redémarrer** |
| `livenessProbe` | es-tu bloquée ? | le conteneur est **redémarré** |

## 🎯 Objectif vérifiable

`./verify.sh` contrôle vos sondes, attend un démarrage lent **sans aucun redémarrage**, relance un déploiement sous un trafic continu et exige **zéro requête en échec**, contrôle le budget de perturbation, puis mesure le canari : environ 10 requêtes sur 100 en 1.1.

---

## Étape 1 — Le piège : une sonde de vie trop pressée

```bash
oc new-app --name=api --image=docker.io/telemachlearning/telemarche-api:1.0 \
  --labels=app.kubernetes.io/part-of=telemarche
oc set env deployment/api STARTUP_SECONDS=20
oc set probe deployment/api --liveness --get-url=http://:8080/healthz --period-seconds=5 --failure-threshold=2
```

> 🎯 **Avant de regarder, prédis :** l'API met 20 s à démarrer ; la sonde de vie tolère 2 échecs espacés de 5 s. Que va-t-il se passer ?

```bash
oc get pods -l deployment=api -w          # Ctrl+C au bout d'une minute
oc describe pod -l deployment=api | grep -A3 -i liveness
oc get events --field-selector reason=Unhealthy | tail -3
```

<details>
<summary>💡 Vérifie ta prédiction</summary>

Au bout de 10 s, la sonde de vie a échoué deux fois : le conteneur est tué et redémarré. Il recommence à zéro ses 20 s de démarrage… et n'y arrive jamais. `RESTARTS` grimpe, puis `CrashLoopBackOff`. La sonde n'a rien de faux : elle interroge simplement trop tôt.
</details>

## Étape 2 — La sonde de démarrage

```bash
oc set probe deployment/api --startup --get-url=http://:8080/healthz --period-seconds=2 --failure-threshold=30
oc get pods -l deployment=api -w          # Ctrl+C quand le pod est 1/1
```

Tant que la sonde de démarrage n'a pas réussi, la sonde de vie ne s'exécute pas. Elle laisse ici jusqu'à 60 s (30 × 2 s), et dès que l'API est prête, la surveillance normale prend le relais.

## Étape 3 — Une mise à jour qui coupe

```bash
oc scale deployment/api --replicas=2
oc expose service/api
API="http://$(oc get route api -o jsonpath='{.spec.host}')"
```

Dans un **second terminal**, envoyez des requêtes en continu :

```bash
while true; do curl -s -o /dev/null -m 2 -w '%{http_code} ' "$API/version"; sleep 0.2; done
```

> 🎯 **Prédis :** dans le premier terminal, `oc rollout restart deployment/api`. Que montre le second ?

<details>
<summary>💡 Vérifie ta prédiction</summary>

Des `503` (le routeur ne trouve aucun pod prêt) et des `000` (connexion coupée). Sans sonde de disponibilité, un pod reçoit du trafic dès qu'il est `Running`, donc 20 s trop tôt. Et par défaut, un ancien pod peut s'arrêter avant que son remplaçant soit prêt.
</details>

Laissez tourner la boucle et faites place nette : `oc delete all -l app=api`.

## Étape 4 — L'API, bien décrite

Complétez `starter/api.yaml` (`# TODO 1` à `7`). Les chemins sont dans [apps/telemarche/README.md](../apps/telemarche/README.md) : `/healthz` ne dépend jamais de la base, `/ready` si.

```bash
oc apply -f starter/api.yaml
oc get pods -l app=api -w                 # Ctrl+C quand les deux pods sont 1/1
oc create route edge api --service=api --insecure-policy=Redirect
API="https://$(oc get route api -o jsonpath='{.spec.host}')"
```

Relancez la boucle du second terminal, avec `-k` (le certificat du cluster n'est pas reconnu par votre poste), puis :

```bash
oc rollout restart deployment/api
oc rollout status deployment/api
```

Plus une seule erreur. Trois réglages y contribuent :

- `maxUnavailable: 0` : un ancien pod ne s'arrête qu'une fois son remplaçant **prêt** ;
- la sonde de disponibilité : un pod ne reçoit du trafic qu'une fois prêt ;
- la vidange : à l'arrêt, l'API répond `503` sur `/ready` et continue de servir 10 s, le temps que le Service et le routeur l'oublient. `terminationGracePeriodSeconds` doit lui en laisser le temps.

## Étape 5 — Le budget de perturbation

```bash
oc get poddisruptionbudget api
```

> 🎯 **Prédis :** `oc delete pod -l app=api` supprime-t-il les deux pods, malgré le budget ?

<details>
<summary>💡 Vérifie ta prédiction</summary>

Oui. Le budget ne protège que des **évictions**, celles d'une maintenance (`oc adm drain`, mise à jour du cluster), pas d'une suppression volontaire. Pendant la mise à jour d'OKD, les nœuds sont vidés un par un, et le budget garantit qu'il reste toujours un pod de l'API.
</details>

## Étape 6 — La version 1.1 en canari

Complétez `starter/canari.yaml` (`# TODO 8` à `10`) : un Deployment `api-canari` en 1.1, son Service, et une Route `api` qui répartit entre les deux Services.

```bash
oc delete route api
oc apply -f starter/canari.yaml
for i in $(seq 1 40); do curl -sk "$API/version"; echo; done | sort | uniq -c
```

Le canari se comporte bien ? Augmentez sa part, puis généralisez :

```bash
oc set route-backends api api=50 api-canari=50
oc set image deployment/api api=docker.io/telemachlearning/telemarche-api:1.1
oc set route-backends api api=100 api-canari=0
```

> 🎯 **Prédis :** et si le canari avait mal tourné, combien de commandes pour revenir en arrière ?

<details>
<summary>💡 Vérifie ta prédiction</summary>

Une : `oc set route-backends api api=100 api-canari=0`. Aucun pod n'est redéployé, le routeur cesse simplement d'envoyer du trafic au canari. Avec les poids `0` et `100` d'un coup, c'est un déploiement **bleu-vert** : deux versions complètes, une bascule instantanée.
</details>

## Étape 7 — Validez

```bash
./verify.sh              # teste VOTRE travail (dossier starter/)
./verify.sh solution     # (option) rejoue la solution de référence
```

---

## 💡 Indices

<details>
<summary>Les pods restent <code>0/1</code>, sans redémarrer</summary>

La sonde de disponibilité échoue : `oc describe pod <nom>`, section `Events`. Vérifiez le chemin et le port.
</details>

<details>
<summary>Le canari ne reçoit jamais rien</summary>

`oc describe route api` : le Service `api-canari` a-t-il un pod prêt ? Depuis un navigateur, le routeur colle chaque visiteur à un pod par un cookie : l'annotation `haproxy.router.openshift.io/disable_cookies` le désactive.
</details>

<details>
<summary><code>verify.sh</code> compte quelques requêtes en échec pendant la mise à jour</summary>

Regardez `maxUnavailable`, la sonde de disponibilité et `terminationGracePeriodSeconds` : il les faut tous les trois.
</details>

## 🚀 Pour aller plus loin

- Pointez la sonde de vie sur `/ready`, avec une base (TP06), puis arrêtez la base. Que fait OpenShift de l'API ? Pourquoi est-ce une erreur ?
- `oc set env deployment/api MEMORY_BALLAST_MB=100` : la limite de mémoire est de 64 Mi. Que dit `oc get pods` ? Et `oc describe pod`, à la ligne `Last State` ?
- Passez la stratégie en `Recreate` et relancez la boucle de trafic : quand l'utiliser malgré tout ? (Indice : TP06, la base.)
