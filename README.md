# jmeter-ecommerce-performance

[![JMeter](https://github.com/tazibt/jmeter-ecommerce-performance/actions/workflows/jmeter.yml/badge.svg)](https://github.com/tazibt/jmeter-ecommerce-performance/actions/workflows/jmeter.yml)

Plan de test **JMeter** d'un site e-commerce : deux populations (visiteurs et acheteurs), parcours
d'achat complet, corrélation, jeux de données, profils de tir externalisés et exécution en mode non-GUI
avec rapport HTML.

La cible est l'API de démonstration publique de Gatling (`api-ecomm.gatling.io`), prévue pour
s'entraîner aux tests de charge. L'étape de paiement peut être envoyée sur
[mock-payment-sap](https://github.com/tazibt/mock-payment-sap).

## Le plan de test

```
Ecommerce - Visiteurs et Acheteurs
├── HTTP Request Defaults        protocole, hôte, timeouts en propriétés ${__P()}
├── HTTP Header Manager          Accept: application/json
├── HTTP Cookie Manager          vidé à chaque itération (nouvel utilisateur)
├── CSV - Recherches             data/search.csv
│
├── TG - Visiteurs               ${__P(VISITORS)} threads, think time aléatoire
│   ├── T01 - Session            extraction sessionId
│   ├── T02 - Recherche          extraction d'un productId au hasard dans les résultats
│   └── Si produit trouvé
│       └── T03 - Fiche produit  assertion JSON : le bon produit est retourné
│
└── TG - Acheteurs               ${__P(BUYERS)} threads, itération suivante si erreur
    ├── B01 - Session et connexion   extraction sessionId et accessToken, assertion « jeton reçu »
    ├── B02 - Recherche              assertion « au moins un produit »
    ├── B03 - Fiche produit          extraction du produit (JSON complet) et de son prix
    ├── B04 - Ajout au panier        corps JSON construit avec ${sessionId} et ${product}
    │   └── Header Manager           Authorization: ${accessToken} (enfant du sampler)
    ├── Si PAYMENT_MOCK=true
    │   └── B05 - Paiement (mock)    montant = ${price}, assertion ACCEPTED
    └── B06 - Commande               assertion « Checkout completed »
        └── Header Manager           Authorization: ${accessToken}
```

Points de conception :

- **Transaction Controllers** sans les timers : le temps mesuré est celui de l'application, pas des pauses.
- **Pas de listener** dans le plan : les résultats sont écrits dans un `.jtl` et le rapport est généré
  à la fin, comme il se doit en mode non-GUI.
- Le Header Manager `Authorization` est placé **sous** les samplers qui en ont besoin : dans JMeter,
  un élément de configuration s'applique à tous les samplers de son niveau, quelle que soit sa position
  dans l'arbre. Placé au niveau du Thread Group, il partirait aussi sur `/session` et `/login`.
- Les visiteurs continuent sur erreur, les acheteurs passent à l'itération suivante : inutile de tenter
  une commande si l'ajout au panier a échoué.

## Lancer un tir

Prérequis : Java 17+ et JMeter 5.6.3.

```bash
./run.sh validation                       # 1 visiteur + 1 acheteur, 20 s
./run.sh charge -JHOST=mon-env.example   # 20 visiteurs + 5 acheteurs, 5 min (voir Résultats)
./run.sh validation -JPAYMENT_MOCK=true   # avec le paiement sur le mock (localhost:8085)
```

Sous Windows : `run.bat validation` (variable `JMETER_HOME` si JMeter n'est pas dans `C:\apache-jmeter-5.6.3`).

Ce qui est exécuté :

```bash
jmeter -n -t tests/ecommerce.jmx -q config/charge.properties \
  -l results/charge/result.jtl -j results/charge/jmeter.log -e -o results/charge/report
```

Le rapport HTML est dans `results/<profil>/report/index.html`.

## Paramètres

Chaque profil est un fichier de `config/`. Toute valeur peut aussi être surchargée avec `-J` :

| Propriété | Défaut | Rôle |
|---|---|---|
| `HOST` / `PROTOCOL` / `PORT` | `api-ecomm.gatling.io` / `https` / – | Cible |
| `VISITORS` | `5` | Threads du groupe Visiteurs |
| `BUYERS` | `2` | Threads du groupe Acheteurs |
| `RAMP_UP` | `30` | Montée en charge (s) |
| `DURATION` | `120` | Durée du tir (s) |
| `THINK_MIN` / `THINK_RANGE` | `1000` / `2000` | Think time : entre MIN et MIN + RANGE ms |
| `USERNAME` / `PASSWORD` | compte de démo | Connexion des acheteurs |
| `PAYMENT_MOCK` | `false` | Active l'étape de paiement sur le mock |
| `PAYMENT_HOST` / `PAYMENT_PORT` | `localhost` / `8085` | Adresse du mock |
| `SEARCH_CSV` | `../data/search.csv` | Termes de recherche (chemin relatif au `.jmx`) |

## Résultats

Tir `./run.sh charge` (20 visiteurs + 5 acheteurs, 5 min) lancé depuis un poste local.
Statistiques complètes du rapport : [docs/charge-statistics.json](docs/charge-statistics.json).

**Phase 1 – de 0 à 135 s : 0 erreur** sur 1 265 requêtes HTTP.

| Transaction | Nb | Erreurs | Médiane | p90 | Max |
|---|---|---|---|---|---|
| T01 - Session | 351 | 0 | 174 ms | 246 ms | 1 231 ms |
| T02 - Recherche | 343 | 0 | 42 ms | 67 ms | 1 413 ms |
| T03 - Fiche produit | 339 | 0 | 41 ms | 72 ms | 354 ms |
| B01 - Session et connexion | 45 | 0 | 224 ms | 303 ms | 343 ms |
| B04 - Ajout au panier | 41 | 0 | 257 ms | 353 ms | 4 096 ms |
| B06 - Commande | 41 | 0 | 248 ms | 326 ms | 4 055 ms |

**Phase 2 – à partir de 138 s : toutes les requêtes en `403 Forbidden`.**

Analyse :

- Les 403 viennent de la passerelle qui protège la démo publique (réponse `{"message":"Forbidden"}`
  sur toutes les routes, y compris `/session`), pas d'une défaillance de l'application. Le seuil exact
  n'est pas connu : le blocage est arrivé après environ 1 300 requêtes en 2 min 20, ce qui ressemble
  à un quota sur une fenêtre de temps plutôt qu'à une limite de débit instantané. Il a duré plusieurs
  minutes après l'arrêt du tir.
- Le débit est resté stable autour de 12 req/s de 60 s à la fin, avant comme après le blocage.
  Il est piloté par le think time (placé avant chaque requête) : 25 threads / ~2,1 s ≈ 12 req/s.
  Le débit moyen global (10,9 req/s) est plus bas à cause de la montée en charge des 60 premières secondes.
- Sur les acheteurs, 41 à 45 échantillons ne suffisent pas pour lire un p95 ou un p99 : le maximum
  à 4 s sur le panier et la commande correspond à **une seule** requête lente. À confirmer sur un tir
  plus long avant d'en tirer une conclusion.
- Conclusion : la démo publique convient pour valider le script, pas pour un vrai tir de charge. Pour un
  tir significatif, `HOST` doit pointer vers un environnement maîtrisé et autorisé.

## Intégration continue

À chaque push, GitHub Actions installe JMeter, lance le tir de **validation** et échoue s'il y a la
moindre erreur. Le rapport HTML est publié en artefact. Le tir de charge, lui, se lance à la main :
on ne génère pas de charge sur un service public à chaque commit.

## Voir aussi

- [gatling-performance-tests](https://github.com/tazibt/gatling-performance-tests) : le même type de
  parcours écrit avec Gatling.
- [qa-test-strategy](https://github.com/tazibt/qa-test-strategy/blob/main/docs/05-performance.md) :
  démarche de test de performance (recueil du besoin, loi de Little, analyse).

## Licence

MIT – voir [LICENSE](LICENSE).
