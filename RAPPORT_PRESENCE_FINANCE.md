# Présence et Finance — mission prioritaire du 9 septembre 2026

## Présence

La règle appliquée au serveur est : date locale de la séance = date locale du jour, et heure courante supérieure ou égale à l'heure de début. L'heure de fin ne ferme pas l'appel. Avant le début, la veille et le lendemain sont refusés. Les contrôles enseignant, affectation, classe, matière, année, direction, élèves, concurrence et verrouillage restent en place.

Flutter utilise l'autorisation renvoyée par le serveur. Une actualisation est programmée à l'heure d'ouverture ou à minuit, selon l'heure serveur, afin qu'un écran ouvert avant le début puisse ensuite proposer l'appel. Le serveur valide toujours l'enregistrement.

Fichiers : `backend/app/attendance.py`, `backend/app/main.py`, `lib/features/school/attendance/attendance_page.dart`, `backend/tests/test_attendance_foundations.py`.

Tests : 16 tests PostgreSQL Présence réussis, dont avant/début/pendant/fin/après/tard, autres dates, mauvais enseignant/classe/matière, doublons, concurrence et historique. Le test Flutter ciblé de l'appel enseignant réussit également.

## Finance

L'écran comporte Paiement mensuel, Tarifs, Impayés et Reçus. Le formulaire d'inscription financière manuelle a été retiré. L'accès au compte financier d'un élève ouvre le même parcours.

La source des élèves est `StudentAcademicRegistration`, reliée à `Student` et `SchoolClass`. La liste financière est une lecture des inscriptions scolaires validées/actives ; elle n'insère aucun second registre d'élèves. Une inscription effectuée par les endpoints du module Élèves est immédiatement retrouvée par le serveur Finance. Un changement de classe est pris en compte pour la même année.

Les tarifs existants `finance-fees` sont réutilisés. L'interface configure et modifie des montants par classe ou niveau, année et nature : inscription, réinscription, mensualité, TD et autres frais. Les portées cycle/établissement déjà présentes restent reconnues. Un tarif de classe est prioritaire sur un tarif de niveau, puis cycle et établissement. Les doublons dans un même contexte sont refusés.

La réinscription est déterminée par l'existence d'une inscription scolaire validée/active dans une année antérieure. Le TD utilise l'option scolaire `has_td` et la validation de niveau déjà utilisée par le module Élèves. Il ne crée pas une nouvelle éligibilité indépendante.

Le parcours de paiement propose la classe, le mois, la recherche nom/prénom, les élèves inscrits, le tarif, le cumul payé et le reste. Le serveur utilise les ressources de paiements/reçus et la fonction de solde déjà existantes. L'identifiant d'échéance dépend de l'inscription scolaire, de la nature et du mois, ce qui évite de perdre les versements lors d'un changement de classe ou de tarif.

Les états sont IMPAYÉ, AVANCE / PARTIEL et PAYÉ selon le cumul des versements actifs. L'annulation restaure le solde et invalide le reçu, en conservant auteur/date/motif. Les opérations partagent les verrous d'affectation financière ; les références sont uniques, y compris après annulation. Les mutations financières génériques sont bloquées afin de passer par les endpoints contrôlés.

Un montant supérieur au reste est refusé avant tout encaissement. Aucun montant n'est tronqué. Si un changement de tarif produit un excédent sur des versements antérieurs, le serveur le retourne et l'interface l'affiche ; aucune affectation automatique de crédit à un autre mois n'est inventée.

Les impayés utilisent les mêmes données serveur et les mêmes filtres. Un tarif absent est signalé « Tarif à configurer », et non présenté comme un tarif nul. Une erreur serveur affiche une indisponibilité, sans remplacer le résumé par zéro.

## Reçus et PDF

Chaque paiement officiel génère son reçu dans la même transaction. Les quatre natures prioritaires sont prises en charge, avec un libellé mensuel explicite, par exemple « Frais du mois d'octobre 2026 ».

Le reçu contient établissement, direction lorsque disponible, numéro, date, élève, matricule, classe, nature/libellé, montant du versement, cumul et reste à l'émission, moyen de paiement, auteur et statut. La consultation et l'impression rechargent le reçu autorisé depuis le serveur. Un reçu annulé reste consultable et imprimable avec la mention « ANNULÉ - justificatif non valable ».

Le reçu PDF est au format A4 avec marges, tableau et pagination. Cinq tests PDF réussissent : inscription, réinscription, mensualité, TD et annulation. Un reçu de test a aussi été rendu en image puis inspecté selon le workflow PDF : les accents, montants, informations et pagination sont lisibles. Le fichier de test n'est pas une pièce métier et n'est pas conservé dans PostgreSQL.

## Fichiers Finance

| Fichier | Rôle |
| --- | --- |
| `backend/app/finance.py` | Projection des inscriptions scolaires, sélection des tarifs, échéances mensuelles, paiement via le mécanisme existant, consultation sécurisée des reçus, modification des tarifs. |
| `backend/app/main.py` | Enregistrement des routes, nature réinscription, garde de contexte des tarifs, unicité, verrous et refus des mutations génériques financières. |
| `lib/data/repositories/school_repository.dart` | Appels des endpoints Finance. |
| `lib/data/services/store_service.dart` | Accès aux opérations serveur sans ajouter de registre local parallèle. |
| `lib/features/school/finance/finance_page.dart` | Nouveau parcours classe/élèves/mois/paiement, tarifs, impayés et reçus. |
| `lib/features/school/finance/student_account_page.dart` | Utilisation du même parcours financier pour l'élève choisi. |
| `lib/features/school/documents/receipt_pdf.dart` | Consultation textuelle et rendu PDF des reçus officiels. |
| `backend/tests/test_school_finance.py` | Tests du parcours Élèves → Finance, tarifs, versements, transfert, reçus, HTTP et scopes. |
| `backend/tests/test_finance_guards.py` | Tests des garanties financières existantes et des contournements interdits. |
| `test/school_finance_workspace_test.dart` | Parcours Flutter paiement/reçu/tarif et gestion d'erreur. |
| `test/finance_receipt_pdf_test.dart` | Génération PDF des quatre natures et d'un reçu annulé. |

## Directions et sécurité

Les tests vérifient l'autorisation dans chaque cycle des trois directions et le refus hors scope pour élève/inscription, tarif, paiement et reçu, y compris par identifiant. La classe et l'année choisies sont contrôlées. Le Super Admin conserve le choix de contexte dans la navigation globale. Les enseignants ne peuvent pas utiliser ces opérations administratives Finance.

## Tests et données

- Présence serveur : **16 réussis**.
- Finance serveur : **26 réussis** (20 nouveaux parcours scolaires et 6 tests des garanties existantes).
- Flutter Finance/PDF : **7 réussis** (2 parcours UI et 5 PDF).
- Flutter appel enseignant : **1 réussi**.
- Total des tests ciblés distincts de cette mission : **50 réussis**, aucun ignoré.
- Analyse Flutter ciblée : **aucune erreur ni warning**, 88 informations de style restantes dans les fichiers analysés.
- Compilation Python, imports, démarrage temporaire sur 8001, health check et présence des nouvelles routes dans OpenAPI : réussis.
- `git diff --check` : réussi ; avertissements LF/CRLF uniquement.

Les tests PostgreSQL utilisent des transactions externes avec rollback. Le contrôle après tests/démarrage constate 7 utilisateurs, 2 élèves, 3 enseignants et 6 ressources, comme avant. Zéro compte `admin@edupro.com`, zéro utilisateur `@rollback.invalid`, zéro ressource financière réelle ou de test persistante. Aucun reset, aucune table ni donnée métier supprimée.

Aucune migration créée ni schéma modifié. Les empreintes des migrations 0021, 0022 et 0023 sont identiques au contrôle précédent. Les modifications préexistantes du dossier de travail sont conservées.

## Activation restante

Le serveur habituel sur 8000 utilise encore l'ancienne version : son OpenAPI ne contient pas `/api/v1/school/finance/roster`. Il doit être redémarré pour charger ces modifications ; le serveur temporaire de validation a été arrêté. Flutter doit également charger les nouveaux écrans.

Après arrêt de l'ancien processus dans sa console, commande de démarrage depuis le projet :

```powershell
Set-Location 'C:\Users\bouak\Desktop\GODFIRST-SCHOOL-MANAGMENT-SYSTEM-\backend'
& '..\.runtime\python311\python.exe' -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Les montants réels restent à configurer par l'administration dans Tarifs. Aucun montant fictif ni tarif codé en dur n'a été ajouté. Les autres travaux de finalisation générale Documents ne font pas partie de cette mission prioritaire.
