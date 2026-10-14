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
    ├── B01 - Session et connexion   extraction sessionId et accessToken
    ├── B02 - Recherche
    ├── B03 - Fiche produit          extraction du produit (JSON complet) et de son prix
    ├── Header Manager               Authorization: ${accessToken}
    ├── B04 - Ajout au panier        corps JSON construit avec ${sessionId} et ${product}
    ├── Si PAYMENT_MOCK=true
    │   └── B05 - Paiement (mock)    montant = ${price}, assertion ACCEPTED
    └── B06 - Commande               assertion « Checkout completed »
```

Points de conception :

- **Transaction Controllers** sans les timers : le temps mesuré est celui de l'application, pas des pauses.
- **Pas de listener** dans le plan : les résultats sont écrits dans un `.jtl` et le rapport est généré
  à la fin, comme il se doit en mode non-GUI.
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
  -l results/charge/result.jtl -e -o results/charge/report
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

**Phase 1 – de 0 à 135 s : 0 erreur** sur 1 265 requêtes HTTP (9,4 req/s en moyenne).

| Transaction | Nb | Erreurs | Médiane | p95 | p99 |
|---|---|---|---|---|---|
| T01 - Session | 351 | 0 | 174 ms | 278 ms | 728 ms |
| T02 - Recherche | 343 | 0 | 42 ms | 88 ms | 264 ms |
| T03 - Fiche produit | 339 | 0 | 41 ms | 90 ms | 143 ms |
| B01 - Session et connexion | 45 | 0 | 224 ms | 311 ms | 343 ms |
| B04 - Ajout au panier | 41 | 0 | 257 ms | 431 ms | 4 096 ms |
| B06 - Commande | 41 | 0 | 248 ms | 381 ms | 4 055 ms |

**Phase 2 – à partir de 138 s : toutes les requêtes en `403 Forbidden`.**

Analyse :

- Les réponses portent l'en-tête `x-amzn-ErrorType: ForbiddenException` : c'est la passerelle AWS API Gateway
  qui protège la démo, pas l'application qui tombe. Le blocage survient quand le débit atteint environ
  12 req/s depuis une même adresse IP, et persiste plusieurs minutes après l'arrêt du tir.
- Le rapport global affiche 60 % d'erreurs et un débit moyen de 10,9 req/s, **plus élevé** qu'en phase 1 :
  les erreurs 403 répondent immédiatement, les threads bouclent plus vite. Un débit qui monte en même temps
  que le taux d'erreur est un signal classique de « fausses » transactions rapides, à ne pas lire comme une
  amélioration.
- Sur le panier et la commande, le p99 à 4 s alors que le p95 reste sous 450 ms indique quelques requêtes
  isolées très lentes (démarrage à froid côté serveur probable) : à surveiller sur un tir plus long avant de conclure.
- Conclusion : la démo publique convient pour valider le script, pas pour un vrai tir de charge. Pour un
  tir significatif, `HOST` doit pointer vers un environnement dont on a la maîtrise et l'autorisation.

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
