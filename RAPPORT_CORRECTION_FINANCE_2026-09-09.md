# Correction Finance — 9 septembre 2026

## État réel

Correction implémentée et tests ciblés réussis. La version contrôlée démarre et répond au health check. Le serveur habituel sur le port 8000 est resté lancé avec son ancienne version : l’activation nécessite son redémarrage et le rechargement de Flutter. Les tarifs réels doivent être renseignés par l’administrateur ; aucun tarif ni paiement fictif n’a été créé.

## 1. Logique Finance

La chaîne reste Élèves → inscription scolaire canonique → projection financière serveur → paiement officiel → reçu. Aucun registre d’inscription parallèle dans Finance. L’ajout porte sur le budget annuel et les tarifs différenciés, sans reconstruction du circuit de paiement existant.

## 2. Inscriptions et budget

Le budget parcourt les inscriptions de l’année sélectionnée aux états `validated` ou `active`, dans le périmètre connecté. Il utilise leur classe actuelle, leur élève et leurs options. Une nouvelle inscription via le vrai endpoint Élèves augmente le budget au prochain chargement. Les recherches de caisse ne réduisent pas le budget annuel.

L’existence d’une inscription active/validée dans une année antérieure distingue réinscription et première inscription ; les deux frais ne sont pas cumulés sur la même inscription courante. Les transferts modifient le contexte tarifaire sans effacer les reçus historiques.

## 3. Tarifs

L’administrateur saisit le libellé et le montant. La fenêtre existante permet la classe ou le niveau ; le serveur conserve aussi les portées cycle et établissement et leurs restrictions de direction. Priorité : classe, niveau, cycle, établissement. À portée égale, un tarif mensuel particulier prime sur le tarif général des mois scolaires.

Le champ JSON facultatif `month` permet par exemple deux tarifs distincts pour octobre et novembre, sans modification de schéma. Les reçus utilisent le libellé administratif ; le mois humain est ajouté pour les tarifs mensuels génériques.

Plusieurs « autres frais » de libellés différents sont possibles et possèdent des soldes distincts. La modification du libellé/montant conserve l’identité du tarif ; elle ne déplace pas silencieusement son année, son contexte ou son mois. Les doublons de même contexte sont refusés.

## 4. TD

Le budget reprend exclusivement `has_td` de l’inscription officielle, avec la validation pédagogique existante des niveaux concernés. Aucune deuxième sélection TD dans Finance. Le test vérifie le montant avec TD et l’absence de montant sans TD.

## 5. Paiement mensuel

Choisir une classe, rechercher l’élève, cliquer sur son nom ou sur Encaisser. La fenêtre présente son nom complet, sa classe, le libellé, le mois, le tarif, le cumul payé et le reste. L’agent saisit le montant reçu et le moyen de paiement. Le serveur contrôle l’inscription, le tarif applicable et le reste avant d’enregistrer.

## 6. Recherche

Le champ est « Rechercher un élève ». La classe filtre immédiatement la liste. La recherche serveur accepte nom, prénom et sous-chaînes, sans exiger de matricule. Le clic sur l’élève ouvre directement l’encaissement lorsqu’un montant reste dû.

## 7. Statuts

Le cumul des paiements actifs de la même échéance détermine IMPAYÉ (zéro), AVANCE / PARTIEL (entre zéro et le tarif) ou PAYÉ (tarif atteint). Un versement ne remplace pas les précédents. Le dépassement du reste est refusé avant encaissement. L’annulation auditée retire le versement du cumul et conserve son historique.

## 8. Budget annuel

Le nouvel endpoint `/api/v1/school/finance/budget`, aussi repris dans la réponse du workspace, calcule attendu, encaissé, reste et excédent, ventilés en inscription, réinscription, mensualités, TD et autres frais. L’encaissé provient des paiements officiels, même si une inscription est ensuite rendue inactive. Le reste est non négatif par catégorie et les excédents restent signalés.

Les périodes scolaires mensuelles actives et datées sont utilisées lorsqu’elles existent ; sinon les mois couvrant les dates de l’année scolaire sont utilisés. Des périodes mensuelles sans date produisent une indisponibilité explicite demandant leur configuration, pas un budget fictif.

Flutter affiche les chiffres fournis par le serveur dans « Budget annuel ». En cas d’erreur, il affiche l’indisponibilité. Des tarifs manquants donnent un avertissement de budget incomplet, distinct d’une erreur serveur.

Lecture de la base réelle : deux inscriptions, neuf mois d’octobre 2026 à juin 2027, aucun tarif financier enregistré. Les montants actuellement nuls sont donc accompagnés du signalement des tarifs manquants ; aucun montant n’a été inventé.

## 9. Reçus

Le circuit officiel paiement/reçu et le générateur PDF existant sont conservés. Le reçu reprend la transaction, son contexte scolaire, son libellé administratif, son cumul et son reste au moment de l’émission. Les tests couvrent inscription, réinscription, mensualité, TD et reçu annulé ; un autre frais distinct est également testé côté serveur.

## 10. Directions et sécurité

La projection annuelle réutilise le filtrage des classes et des ressources financières. Les tests parcourent Maternelle, Primaire, Collège et Lycée, couvrant les trois directions. Ils vérifient le budget autorisé et le budget hors périmètre, ainsi que les accès directs aux identifiants, paiements et reçus. Les enseignants restent interdits de Finance. Les verrous, références uniques, transactions et annulations auditées sont conservés.

## 11. Nombre de tests

56 cas automatisés distincts exécutés pendant cette intervention, sans compter leurs répétitions :

- 26 tests de projection Finance et budget ;
- 6 tests de protections financières existantes ;
- 2 tests Flutter caisse/budget/erreur serveur ;
- 5 tests de reçus PDF ;
- 16 tests backend Présence ;
- 1 test Flutter Présence ciblé.

## 12. Résultats

56 réussis, zéro échec automatisé restant. Dernière exécution Finance : 32 backend + 7 Flutter/PDF réussis. Analyse statique des deux fichiers Flutter Finance concernés : aucune anomalie. Les tests PDF émettent l’avertissement générique Helvetica/Unicode du générateur existant ; aucun changement de mise en page PDF n’a été effectué ici.

Démarrage temporaire de la version corrigée sur le port 8001 : `/health` → `{"status":"ok"}` et route budget présente dans OpenAPI. Cette instance de contrôle a ensuite été arrêtée. Aucun redémarrage du serveur habituel effectué.

Un diagnostic supplémentaire avec un enseignant réel a échoué à la validation de date scolaire, et non à la règle horaire : voir ci-dessous. Aucun enregistrement réel d’appel n’est présenté comme réussi.

## 13. Fichiers concernés par cette correction

- `backend/app/main.py` : contrat de tarif avec mois facultatif, validation, unicité et stockage JSON.
- `backend/app/finance.py` : budget annuel, périodes mensuelles, sélection des tarifs et autres frais, libellés et encaissements.
- `lib/features/school/finance/finance_page.dart` : budget annuel, tarif mensuel, recherche, sélection de classe et ouverture de caisse par clic élève.
- `backend/tests/test_school_finance.py` : six tests supplémentaires et adaptation des assertions aux libellés administratifs ; vérifications budget par direction.
- `test/school_finance_workspace_test.dart` : parcours classe → clic élève → paiement → reçu → tarif → budget.
- Le présent rapport.

Les autres modifications déjà présentes dans l’espace de travail sont conservées. Aucun reset Git/PostgreSQL, aucune suppression de table, aucune nouvelle migration. La migration 0022 est toujours présente, de même que les migrations 0023 et 0024 préexistantes. Aucune restauration de données effectuée.

Après tests : 7 utilisateurs, 2 élèves, 3 enseignants, 6 ressources ; zéro ressource Finance, zéro utilisateur `@rollback.invalid`, zéro compte `admin@edupro.com`. Les transactions de test ont été annulées.

## 14. Reste à faire et diagnostic Présence

Activer la version corrigée en redémarrant le backend habituel, recharger Flutter et configurer les tarifs réels. Les tests ne constituent pas un test de charge à grande volumétrie ni une validation manuelle exhaustive de toutes les plateformes Flutter.

Pour Présence, les trois séances réelles du mercredi sont bien retrouvées en Terminale C1 : Parfait MBAN, MBONGA Evan et Konaté Moussa. Elles dépendent de l’année « 2026-2027 », du **03/10/2026 au 20/06/2027**, alors que le jour local vérifié était le **09/09/2026**, UTC+1. La résolution JWT du compte réel de Parfait MBAN et la récupération serveur de sa séance ont été exercées ; la validation de séance précédant l’ouverture/enregistrement refuse la date hors année scolaire. Le diagnostic s’est arrêté à ce contrôle, sans soumettre de feuille réelle.

L’utilisateur a confirmé que ces dates sont correctes et demandé de ne pas les modifier. Les dates et les règles Présence sont donc conservées, sans correction métier de contournement et sans appel fictif. L’essai d’enregistrement complet avec cet enseignant aujourd’hui n’a pas été forcé. Les modifications exploratoires d’interface Présence de cette intervention ont été retirées pour conserver son fonctionnement antérieur.
