# Rapport de finalisation — état vérifié au 9 septembre 2026

La mission globale reste partiellement réalisée. Les corrections ci-dessous sont implémentées et les contrôles indiqués ont réellement été exécutés. Ce rapport ne certifie pas l'ensemble du SaaS comme terminé.

## 1. Audit de l'existant

Le backend possède déjà les modèles relationnels scolaires, les affectations, les restrictions par établissement/direction, les états des résultats et des modules Présence/Comportement. Finance utilise les ressources existantes avec des endpoints métier pour les frais, les paiements, les soldes et les annulations. Aucun système parallèle n'a été créé.

Problèmes constatés : actions financières locales malgré l'existence des endpoints ; absence de verrou pour les paiements simultanés ; routes génériques permettant de modifier des pièces financières ; résumé Flutter recalculé localement ; bulletin local et détail serveur recalculé séparément ; onze modèles documentaires proposant un aperçu générique et une fausse confirmation d'impression.

## 2. Corrections et fichiers

| Fichier | Modification de ce bloc |
| --- | --- |
| `backend/app/main.py` | Verrous financiers, référence unique même après annulation, annulation du reçu auditée, résumé par année, protection des routes génériques, détails des matières conservés dans le résultat officiel, bulletin consommant ces détails, validation documentaire et détection des archives obsolètes. |
| `backend/tests/test_finance_guards.py` | Frais/affectation, paiements, doublons, soldes, annulation, concurrence, direction, interdiction des contournements génériques. |
| `backend/tests/test_document_guards.py` | Trois périodes, cohérence avec le résultat fourni, métadonnées, refus des résultats non officiels, élève étranger, direction et archive obsolète. |
| `lib/data/models/finance/finance_models.dart` | Statut actif/annulé du reçu, sérialisation compatible avec les anciens reçus. |
| `lib/data/repositories/school_repository.dart` | Contexte établissement/année du résumé et établissement pour l'annulation Super Admin. |
| `lib/data/services/store_service.dart` | Annulation distante, conservation du contexte du reçu, résumé distant, contexte documentaire explicite pour Super Admin. |
| `lib/features/school/finance/finance_page.dart` | Résumé serveur, annulation distante, reçus en consultation, retrait des modifications/suppressions locales de paiements/reçus. |
| `lib/features/school/documents/bulletin_generator.dart` | Périodes réelles, résultat officiel distant, métadonnées, vérification avant impression et générateur PDF partagé. |
| `lib/features/school/documents/documents_page.dart` | Retrait des aperçus fictifs et confirmations d'impression injustifiées ; modèles non raccordés signalés indisponibles. |
| `lib/features/school/documents/pdf_helpers.dart` | Titre humain, marges A4, pagination du bulletin trimestriel et caractères de remplacement compatibles. |
| `test/bulletin_pdf_test.dart` | Vérification du générateur utilisé en production avec les trois périodes. |

Les modifications antérieures déjà présentes dans le dossier de travail ont été conservées. La liste ci-dessus n'attribue pas toutes les modifications Git préexistantes à ce bloc.

## 3. Finance

Les tests PostgreSQL valident la création d'un frais et de son affectation, le paiement avec reçu, les soldes avant/après annulation, le rejet des références réutilisées et la concurrence entre connexions. Paiement et reçu partagent la même transaction. L'annulation conserve l'auteur, la date et le motif ; le reçu devient annulé.

Le résumé de l'écran principal est demandé au serveur pour l'établissement et l'année du contexte. En cas d'erreur, il affiche une indisponibilité au lieu d'un faux zéro. Les autres écrans financiers historiques et leurs calculs locaux ne sont pas tous certifiés dans cette passe.

## 4. Documents

Le bulletin trimestriel consomme désormais le résultat officiel enregistré. Il ne recalcule plus ses moyennes à partir des notes brutes. Le serveur refuse l'archivage d'un résultat waiting, ready ou stale et contrôle classe, élève et période. Les métadonnées conservent la date du calcul source. La consultation d'une archive de résultat signale stale lorsque cette source change.

Les anciens résultats sans détail des matières nécessitent un recalcul explicite avant génération du nouveau bulletin. Aucun recalcul de données réelles n'a été déclenché pendant cette intervention.

## 5. PDF et nomenclature

Le bulletin trimestriel utilise les noms des périodes existantes. Son titre d'archive combine bulletin, période, nom/prénom, classe et année. Le générateur PDF partagé utilise A4, des marges et une pagination. Les tests produisent des octets PDF pour les trois périodes et pour les générateurs historiques trimestriel/annuel.

Cela valide la génération, pas une inspection visuelle exhaustive. Les avertissements généraux Helvetica/Unicode restent présents ; les tirets non pris en charge ont été remplacés. Les PDF annuels historiques et les onze autres modèles ne sont pas certifiés comme documents officiels opérationnels. Les reçus sont conservés et consultables, mais leur export PDF reste à raccorder.

## 6. Enseignant

Les travaux déjà présents permettent l'accès aux résultats officiels des classes affectées, l'appel pendant toute la journée prévue et les contributions comportementales indépendantes/verrouillées. Les tests serveur Présence/Comportement ont été relancés avec succès. Cette passe n'a pas autorisé les enseignants à générer les bulletins administratifs complets.

## 7. Directions

Les tests Finance/Documents exercent les quatre cycles relevant des trois directions et refusent l'accès par identifiant hors cycle autorisé. Présence dispose aussi d'un test des trois directions réelles. Ces vérifications ne constituent pas un audit exhaustif de tous les exports, statistiques et écrans du SaaS ; aucune affirmation globale supplémentaire n'est faite.

## 8. Backend

Routes concernées : `/school/finance/fees`, `/school/finance/payments`, `/school/finance/payments/{id}/cancel`, `/school/finance/summary`, `/school/students/{id}/bulletin`, `/school/documents` et routes génériques de ressources, sous le préfixe `/api/v1`.

Les créations/modifications/suppressions génériques de paiements, reçus et documents sont refusées : les opérations passent par leurs workflows contrôlés. Les imports et la compilation Python passent. Aucun changement JWT ou du mécanisme d'authentification n'a été requis dans ce bloc.

## 9. Flutter

L'analyse ciblée des pages/services concernés termine sans erreur ni avertissement bloquant, avec des informations de style restantes. Le groupe connexion/Finance/PDF a réussi : 18 tests. Après la dernière correction PDF, ses trois tests ont été relancés et réussissent.

Les tests Finance Flutter historiques exercent surtout le service existant ; ils ne suffisent pas à certifier toutes les interactions réelles de caisse. Aucune grande campagne UI/E2E n'a été lancée.

## 10. Base de données et démarrage

Aucune nouvelle migration de ce bloc. Les fichiers 0021, 0022 et 0023 sont présents et n'ont pas été réécrits ; 0024 préexistait également à ce bloc. Leurs changements Git antérieurs restent en place. Aucun reset, DROP, restauration ou suppression de données réelles.

Le code modifié a démarré temporairement sur `127.0.0.1:8001`, puis ce serveur de validation a été arrêté. Son health check répondait `ok`. Avant/après ce démarrage : 7 utilisateurs, 2 élèves, 3 enseignants, 6 ressources. Aucun compte `admin@edupro.com` et aucun utilisateur de test `@rollback.invalid` subsistant. Le serveur existant sur 8000 répond aussi `ok` ; il n'a pas été redémarré et ne constitue pas une preuve que les dernières modifications y sont chargées.

Empreintes SHA256 constatées :

- 0021 : `C7A250F8530B0BB4B6EB7CF45668C5DDC0C09EE59CB15C8DEFD8B283E6517B03`
- 0022 : `B09E4B4947EB91EFA29DD3C0CF654F734CB1FDE03F0BDEE29B0BB5F4471E8463`
- 0023 : `D6054D63F7A218A6A23B348A9248C7A1A94E4F3E94259DF8D4C4741336E1A7EE`

## 11. Tests réellement exécutés

- Suite backend : 39 tests, 38 réussis, 1 ignoré car le contexte réel requis était indisponible. Les écritures des fixtures sont annulées par transaction externe.
- Après les derniers ajouts Finance/Documents : 10 tests ciblés réussis, incluant les deux nouveaux cas d'affectation/résumé et d'archive stale.
- Flutter connexion/Finance/PDF : 18 réussis.
- Dernière passe PDF : 3 réussis, dont les trois périodes dans un même test.
- Analyse Flutter ciblée : aucune erreur ni warning ; informations de style restantes.
- Compilation Python/imports, démarrage temporaire, health checks et `git diff --check` : réussis. Git signale seulement la normalisation LF/CRLF.
- Les tests documentaires injectent le résultat officiel pour vérifier sa consommation et les gardes. Ils ne testent pas un scénario académique complet de programmation jusqu'au PDF.

## 12. Travail restant

La mission entière n'est pas finalisée. Restent notamment : génération réelle des autres documents administratifs/financiers ; export PDF des reçus ; raccordement du bulletin annuel historique au résultat serveur ; détail des notes par événement, appréciations et comportement dans le bulletin ; validation visuelle PDF et polices couvrant les noms Unicode ; audit de toutes les actions financières historiques, échéances et écrans de comptes ; vérification exhaustive du scope des statistiques/exports ; validation des parcours réels administrateur/enseignant sur les trois directions.

Le chargement des modifications dans le serveur habituel nécessitera son redémarrage contrôlé. Aucun mot de passe réel ni compte de démonstration n'a été ajouté par les corrections décrites ici.
