# Correction Finance — inscription encaissée automatiquement

## Logique finale

- Une inscription scolaire validée/active est la preuve de règlement de son tarif d’inscription.
- Une réinscription est la preuve de règlement de son tarif de réinscription lorsqu’une inscription antérieure existe.
- Les lignes correspondantes affichent immédiatement `attendu = payé`, `reste = 0`, `statut = paid`.
- Aucun paiement cash ou enregistrement `finance-payment` supplémentaire n’est créé : il n’y a donc pas de double encaissement ni de donnée fictive.
- Un reçu officiel virtuel, déterministe et consultable est exposé pour l’inscription/réinscription (`REGREC_...`), avec l’élève, la classe, le libellé, le montant, l’année et la source `school_registration`.
- Une tentative de repayer l’inscription est idempotente : elle retourne le reçu déjà réglé sans ajouter d’argent.

TD, mensualités et autres frais restent entièrement indépendants. Un TD sélectionné dans le dossier scolaire crée une obligation ; son absence de paiement ne bloque pas l’inscription. Les mensualités restent payables mois par mois et les autres frais sont séparés.

## Budget

Le budget annuel serveur réutilise les inscriptions canoniques, les tarifs configurés et les paiements officiels. Il ajoute les montants d’inscription/réinscription automatiquement encaissés au total `paid`, additionne les paiements réels de TD, mensualités et autres, puis calcule `remaining = max(expected - paid, 0)`. La ventilation et les compteurs restent limités à l’établissement/direction autorisé.

## Interface

Finance conserve la vue d’ensemble, la ventilation par type, la caisse mensuelle, la recherche nom/prénom, les frais TD/autres et les reçus. La ligne d’inscription n’offre plus une seconde encaissement normal puisqu’elle est déjà PAYÉE ; le reçu est accessible dans Reçus et via l’API officielle.

## Fichiers modifiés

- `backend/app/finance.py` : règlement automatique des lignes inscription/réinscription, reçus virtuels officiels et consultation directe.
- `backend/tests/test_school_finance.py` : tests métier inscription encaissée, TD séparé, budget et reçu sans paiement cash.

Aucune migration, suppression de table, suppression de donnée réelle ou modification des autres modules n’a été effectuée.

## Tests

- 34 tests backend Finance réussis.
- 17 tests backend Présence réussis dans la dernière suite disponible.
- 19 tests Flutter ciblés Finance, Documents, enseignant et Présence réussis.
- 4 tests Documents et 4 tests Inscriptions réussis lors des suites précédentes.

Les tests utilisent les fixtures transactionnelles avec rollback. Aucun tarif, paiement ou élève de test n’est conservé.

## Reste réel

Les tarifs réels doivent être configurés par l’administration. Le serveur habituel doit être redémarré pour charger cette version. Le test manuel à effectuer est : Élèves → inscrire → Finance → vérifier inscription PAYÉE et budget encaissé → Reçus → consulter le reçu ; puis Finance → TD → payer séparément.
