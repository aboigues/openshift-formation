# La gate « okd » : les TP rejoués sur un vrai OKD avant chaque fusion

Le check `okd` (workflow [okd.yml](../.github/workflows/okd.yml)) rejoue `verify.sh solution` de chaque TP (`scripts/test-all.sh`) sur le CRC d'un poste. Il tourne **dans GitHub Actions**, mais sur une machine à nous : un runner auto-hébergé, au label `okd`. Son résultat est un check comme les autres, obligatoire pour fusionner dans `main`.

| Événement | Ce qui se passe |
|---|---|
| PR qui touche `tp*/`, `apps/`, `builders/`, `scripts/` ou `okd.yml` | répétition complète sur le poste (environ 20 min) |
| PR qui ne touche rien de tout ça (doc, CI…) | `okd` est *skipped*, ce qui satisfait la gate |
| PR venue d'un fork qui touche les TP | échec immédiat sur un runner GitHub : le code d'un fork ne s'exécute **jamais** sur le poste. On reprend ses commits dans une branche du dépôt |
| lundi 7 h (UTC), ou *Run workflow* | répétition complète : une dérive (image, OKD, CRC) se voit sans attendre une PR |

Poste éteint : le job attend en file, jusqu'à 24 h, et part au retour du poste. CRC arrêté : le job échoue tout de suite, avec la marche à suivre.

## Mise en place (une fois)

### 1. WSL en réseau miroir

Le runner tourne dans WSL et joint CRC sur `127.0.0.1`. Dans `%USERPROFILE%\.wslconfig` :

```ini
[wsl2]
memory=6GB
networkingMode=mirrored
```

Puis, dans PowerShell : quittez les terminaux WSL, `wsl --shutdown`, et vérifiez que `wsl --list --running` ne liste plus rien (Docker Desktop relance parfois WSL : quittez-le). Rouvrez un terminal WSL : `wslinfo --networking-mode` doit répondre `mirrored`.

WSL ne recopie pas dans `/etc/hosts` les noms que CRC ajoute au fichier `hosts` de Windows, et régénère `/etc/hosts` à chaque démarrage. On lui demande de ne plus le faire, puis on ajoute les deux noms dont `oc login` a besoin :

```bash
sudo sed -i 's/^\[network\]$/[network]\ngenerateHosts = false/' /etc/wsl.conf   # ou ajoutez la section [network]
echo "127.0.0.1 api.crc.testing oauth-openshift.apps-crc.testing" | sudo tee -a /etc/hosts
curl -sk https://api.crc.testing:6443/healthz; echo     # ok, CRC démarré
```

Les noms des Routes créées pendant les TP ne sont pas dans le DNS de WSL : le workflow pose `ROUTEUR=127.0.0.1`, qui fait envoyer par `curl` ces noms au routeur de CRC (voir [environnements.md](environnements.md)).

### 2. Le secret du compte `developer`

GitHub, dépôt, **Settings > Secrets and variables** :

- **Actions** > *New repository secret* : `OKD_PASSWORD` = le mot de passe de `developer` (`crc console --credentials`, `developer` par défaut) ;
- **Dependabot** > le même secret : les PR de Dependabot n'ont accès qu'aux secrets Dependabot.

### 3. Le runner

Dans WSL, à la racine du dépôt :

```bash
./scripts/installer-runner-okd.sh
```

Le script vérifie que CRC répond, télécharge le runner (somme SHA-256 contrôlée), l'enregistre sous le nom `okd-<machine>` avec le label `okd`, et l'installe comme service systemd : il redémarre avec WSL. Il utilise `gh`, qui doit être connecté avec les droits d'administration du dépôt, et demande `sudo` pour le service.

Le runner apparaît dans **Settings > Actions > Runners**, état *Idle*.

### 4. Un premier passage

**Actions > OKD > Run workflow**, sur `main`. Le résumé du job affiche le bilan des huit TP ; le journal complet est en artefact (`test-all-okd`).

### 5. Rendre le check obligatoire

Une fois ce premier passage vert, ajoutez `okd` aux checks obligatoires de `main` (**Settings > Branches > main**, ou) :

```bash
gh api -X POST repos/aboigues/openshift-formation/branches/main/protection/required_status_checks/contexts \
  -f 'contexts[]=okd'
```

## Au quotidien

- Pendant un passage, le workflow empêche Windows de se mettre en veille pour inactivité (`scripts/eveil-windows.ps1`). Capot fermé, la veille l'emporte : laissez le portable ouvert, ou réglez Windows pour qu'il ne se mette pas en veille sur secteur.

- Avant de pousser une PR qui touche les TP : `crc start`. Le check part tout seul.
- Le check a échoué parce que CRC était arrêté : `crc start`, puis **Re-run jobs** dans la PR.
- `main` a bougé pendant que la PR attendait : la protection exige une branche à jour. *Update branch*, et la répétition repart.
- Retirer le runner : `./scripts/installer-runner-okd.sh --retirer`.

## Suivre le runner

```bash
gh api repos/aboigues/openshift-formation/actions/runners --jq '.runners[] | "\(.name) \(.status) occupé=\(.busy)"'
gh run list --workflow okd.yml -L 5            # les derniers passages ; gh run watch pour en suivre un
systemctl status 'actions.runner.*' --no-pager # le service, dans WSL
journalctl -u 'actions.runner.*' -f            # Connected, Running job, completed
tail -f ~/actions-runner-okd/_diag/Worker_*.log   # le job en cours, en détail
```

| Symptôme | Cause probable | Que faire |
|---|---|---|
| runner *Offline* | WSL arrêté (aucun terminal ouvert), Windows en veille | ouvrir un terminal WSL, réveiller le poste |
| job *queued*, runner *Idle* | attribution du job par GitHub | patienter une à deux minutes |
| « lost communication with the server » | veille de Windows, coupure réseau | **Re-run jobs** |
| échec à « CRC joignable ? » | CRC arrêté, ou nom absent de `/etc/hosts` | `crc start`, ou étape 1 |

## Sécurité

Un runner auto-hébergé exécute le code du dépôt sur le poste. Les garde-fous :

- jamais le code d'un fork (voir le tableau) ; seules les branches du dépôt, donc de ses collaborateurs, et les PR de Dependabot, qui ne changent que des versions de dépendances ;
- un kubeconfig propre à chaque passage, effacé avec le dossier temporaire du job ; le compte `developer` n'a aucun droit d'administration du cluster ;
- le runner est réservé à ce dépôt et tourne sous votre compte WSL, sans droits root.
