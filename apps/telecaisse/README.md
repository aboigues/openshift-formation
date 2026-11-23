# Télécaisse — la caisse des magasins

Une application Jakarta EE 11 (JAX-RS, CDI, JDBC) servie par WildFly. Construite sur OpenShift par l'image `quay.io/wildfly/wildfly-s2i` : `mvn package` y assemble, avec `wildfly-maven-plugin`, un serveur réduit aux couches `jaxrs-server` et `postgresql-datasource`, l'application déployée à la racine.

| Chemin | Rôle |
|---|---|
| `GET /api/info` | version, caisse (nom du pod), adresse de Télémarché |
| `GET /api/tickets` | les tickets, lus dans la base de la caisse |
| `POST /api/ventes` `{"produit":2,"quantite":3}` | demande le prix à Télémarché, enregistre le ticket |
| `GET /api/sante/vivant` | le serveur répond ; ne dépend de rien |
| `GET /api/sante/prete` | la base de la caisse répond |

| Variable | Effet |
|---|---|
| `POSTGRESQL_HOST`, `POSTGRESQL_PORT` (5432) | la base de la caisse |
| `POSTGRESQL_DATABASE`, `POSTGRESQL_USER`, `POSTGRESQL_PASSWORD` | ses identifiants |
| `TELEMARCHE_API_URL` | l'API de Télémarché (`http://api:8080`) |

La base n'est pas créée par l'application : elle existe déjà dans le système d'information. `sql/schema.sql` la décrit, historique compris.

Attention : une variable `POSTGRESQL_SERVICE_HOST` l'emporte sur `POSTGRESQL_HOST`. Kubernetes la pose d'office dans les pods si le projet contient un Service nommé `postgresql`.
