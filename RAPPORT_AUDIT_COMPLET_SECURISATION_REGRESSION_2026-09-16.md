# RAPPORT — AUDIT COMPLET, SÉCURISATION ET RÉGRESSION

Date de clôture : 16 septembre 2026  
Projet : `GODFIRST-SCHOOL-MANAGMENT-SYSTEM`  
Périmètre : FastAPI, PostgreSQL/SQLAlchemy, authentification/JWT, RBAC, multi-établissement, multi-direction, Flutter Web, Finance, Documents, Notes/Résultats, Présence, Comportement, Emploi du temps, Plans, Parent et Élève.

## 1. Résumé exécutif

L’audit de sécurité et la campagne de régression sont terminés. Les vulnérabilités réellement trouvées dans le périmètre ont été corrigées sans reset PostgreSQL, sans reseed, sans suppression de données, sans changement d’un mot de passe existant et sans nouvelle migration.

Résultat final vérifié :

- Backend : **131 tests réussis, 1 test ignoré, 0 échec**.
- Flutter : **235 tests réussis, 3 tests réels ignorés faute d’identifiants injectés, 0 échec**.
- Tests Flutter de sécurité/session ciblés : **36 réussis, 0 échec**.
- Analyse statique finale des fichiers sensibles touchés : **aucun problème**.
- Build Web Release réel : **réussi**, artefacts présents dans `build/web`.
- FastAPI : **actif sur le port 8000**, health check HTTP **200**.
- Compte de démonstration `admin@edupro.com` : **absent de PostgreSQL** et non recréé au démarrage.

## 2. Vulnérabilités trouvées et corrigées

### ÉLEVÉE — Données métier conservées après déconnexion

**Problème** : le jeton et l’utilisateur étaient supprimés, mais des collections métier pouvaient rester en mémoire et dans le cache local. Sur un appareil partagé, un autre utilisateur pouvait théoriquement voir un état résiduel avant rechargement.

**Cause** : la déconnexion ne purgeait pas l’intégralité des clés `edupro_` ni toutes les collections métier du magasin Flutter.

**Correction** : purge centralisée de la mémoire métier et du stockage persistant lors du logout et d’une véritable réponse 401. Le thème et le marqueur d’initialisation non sensible sont conservés.

**Test** : tests de login/logout/restauration de session, vérification que token, utilisateur, enseignants et données sensibles sont vidés. Suite ciblée : 36/36.

### ÉLEVÉE — Espace Parent incomplet et risque de chargement trop large

**Problème** : le Parent ne disposait pas d’un bootstrap relationnel dédié couvrant proprement enfants, inscriptions, classes, cycles et années. Cela créait un risque de dépendre de collections plus larges que son périmètre.

**Cause** : absence d’un endpoint de workspace Parent minimal et strictement construit depuis les relations Guardian → Student.

**Correction** : ajout de `/api/v1/school/parent/workspace`. La réponse ne contient que les enfants actifs liés au responsable authentifié, leurs inscriptions/classes/années, et retire les coordonnées privées des autres responsables.

**Test** : un Parent voit son enfant, sa classe et son année ; un enfant non lié est absent ; l’emploi du temps utilise le périmètre autorisé ; Finance, Présence et Comportement ne sont pas proposés au Parent lorsqu’aucun flux serveur autorisé n’existe.

### MOYENNE — Création/réinitialisation du compte Parent non consolidée

**Problème** : le rattachement d’un responsable à un compte Parent et la synchronisation de son email n’étaient pas entièrement consolidés.

**Cause** : absence d’une action explicite et idempotente de création/réinitialisation de l’accès Parent.

**Correction** : ajout de `/api/v1/school/guardians/{guardian_id}/access`, réservé aux rôles administratifs autorisés, soumis au plan `parents.access`, au tenant, à la direction et à l’existence d’un élève actif lié. Le même compte est réutilisé ; aucun doublon n’est créé. Le mot de passe temporaire suit le mécanisme existant à usage unique et durée limitée.

**Test** : création, réinitialisation du même compte, non-duplication, archivage du profil Parent, login Parent par email et refus lorsque le profil est inactif.

### MOYENNE — Absence de protection locale contre les tentatives répétées de login

**Problème** : l’endpoint de connexion ne limitait pas suffisamment les tentatives répétées.

**Cause** : absence de fenêtre de limitation dans l’application.

**Correction** : limite configurable par couple adresse réseau + identifiant et limite globale par adresse réseau. Les identifiants sont hachés dans le limiteur. Une vérification bcrypt factice est exécutée pour les identifiants inconnus afin de réduire l’énumération temporelle.

**Test** : huit réponses 401 puis réponse 429 avec `Retry-After`. Les valeurs sont configurables par variables d’environnement.

**Note d’exploitation** : ce limiteur est adapté au processus unique actuellement exécuté. Pour plusieurs instances distribuées, un limiteur partagé au proxy ou via Redis est recommandé ; aucune infrastructure ou migration supplémentaire n’a été introduite dans cette mission.

### MOYENNE — Gestion Flutter des vraies invalidations 401

**Problème** : une session réellement invalide pouvait laisser une page locale affichée jusqu’à une action suivante.

**Cause** : le client HTTP ne signalait pas globalement les 401 au magasin de session.

**Correction** : fermeture et purge automatiques sur les 401 des routes protégées. Les routes `/auth/login` et `/auth/change-password` sont explicitement exclues : un mauvais mot de passe saisi sur ces routes ne doit pas détruire une session autrement valide.

**Test** : mauvais login sans session, 401 de changement obligatoire conservant le formulaire, 401 protégé purgeant la session, erreur d’un module secondaire ne détruisant pas une session valide.

### MOYENNE — CORS et en-têtes HTTP perfectibles

**Problème** : la liste des méthodes et en-têtes CORS était trop générale et plusieurs en-têtes défensifs n’étaient pas appliqués.

**Cause** : configuration générique adaptée au développement mais trop large pour une exposition Internet.

**Correction** : origines explicites, boucle locale contrôlée, méthodes `GET/POST/PUT/PATCH/DELETE/OPTIONS`, en-têtes `Authorization/Content-Type/Accept`, rejet d’une origine arbitraire. Ajout de `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer`, `Permissions-Policy` restrictive et `Cache-Control: no-store` sur Auth.

**Test** : origine locale autorisée (200), origine arbitraire rejetée (400), en-têtes vérifiés sur le health check réel.

## 3. Authentification

- ✅ Super Admin/Admin : email + mot de passe.
- ✅ Enseignant : matricule + mot de passe et profil enseignant actif obligatoire.
- ✅ Élève : matricule + mot de passe uniquement pour les cycles/configurations autorisés.
- ✅ Parent : email + mot de passe et Guardian actif lié à au moins un élève.
- ✅ `/auth/me` : token, utilisateur actif, établissement/abonnement et profil de rôle revalidés.
- ✅ Mot de passe temporaire : changement obligatoire, accès restreint aux routes de transition, secret affiché une seule fois.
- ✅ Désactivation : utilisateur ou profil inactif refusé.
- ✅ Changement de mot de passe : révision du mot de passe intégrée au JWT ; les anciens jetons deviennent invalides.
- ✅ Logout : suppression du token, du profil, des données métier en mémoire et du cache persistant.
- ✅ Une erreur d’un module secondaire ne détruit pas une session valide.
- ✅ Aucun mot de passe existant n’a été changé pendant l’audit.

## 4. Mots de passe et JWT

- ✅ Longueur minimale de 8 caractères contrôlée dans les flux concernés.
- ✅ 7 caractères rejetés ; 8 et 12 acceptés par les tests existants.
- ✅ Hash bcrypt ; aucun hash placé dans le JWT.
- ✅ Aucun mot de passe en clair stocké dans Flutter.
- ✅ Aucun mot de passe écrit dans les logs ou le rapport.
- ✅ JWT signé HS256 avec secret d’environnement obligatoire.
- ✅ Claims contrôlés : `sub`, rôle, tenant, révision mot de passe, émission et expiration.
- ✅ Expiration actuelle : 8 heures ; aucun mécanisme de refresh implicite.
- ✅ Token malformé, expiré, utilisateur supprimé/désactivé ou révision incorrecte : refus.
- ✅ Issuer/audience ne sont pas utilisés par cette application mono-API ; la signature, l’expiration et la révision utilisateur constituent les validations actives.

## 5. Autorisations et rôles

Le backend reste la source de vérité ; les menus Flutter ne constituent pas une autorisation.

- ✅ Super Admin : administration globale, établissements, directions, plans et comptes ; pas de réintroduction des accès Présence/Comportement interdits par les règles existantes.
- ✅ Admin : données de son établissement et de sa direction uniquement.
- ✅ Enseignant : classes, matières, affectations, notes, présence, comportement et emploi du temps correspondant à ses affectations ; Finance/Documents/administration globale refusés.
- ✅ Parent : enfants liés uniquement et fonctions explicitement prévues par le plan.
- ✅ Élève : profil propre, résultats publiés et emploi du temps autorisé ; aucune modification scolaire.
- ✅ Actions sensibles : rôles, comptes, reset, plans, publication, finance, établissement et direction protégés côté serveur.
- ✅ Contrainte combinée : rôle + capacité du plan + scope du tenant/de la direction.

## 6. Multi-établissement, multi-direction et IDOR

- ✅ Les helpers de scope vérifient l’établissement avant lecture ou modification.
- ✅ L’Admin doit être rattaché à une direction active.
- ✅ Cycles, niveaux, classes, matières, élèves, enseignants et affectations sont vérifiés dans leur chaîne relationnelle.
- ✅ Les identifiants fournis par le client ne remplacent jamais le tenant de l’utilisateur authentifié.
- ✅ Tests d’isolation entre établissements et directions pour les modules scolaires majeurs.
- ✅ Parent : relation Guardian/Student vérifiée ; un autre identifiant élève n’élargit pas le périmètre.
- ✅ Enseignant : affectation classe/matière vérifiée avant notes, présence ou comportement.
- ✅ Documents, reçus et bulletins proviennent de données déjà filtrées par utilisateur/établissement/direction.
- ✅ Les payloads sensibles (`role`, `school_id`, `direction_id`, `owner`, statut) sont validés ou déterminés par le serveur dans les actions concernées.

## 7. Finance

- ✅ Inscription/réinscription, tarifs, mensualités, autres frais et TD couverts par les tests.
- ✅ Paiements partiels et allocation contrôlés.
- ✅ Montants négatifs et plans/prix invalides refusés.
- ✅ Absence de tarif non présentée comme un paiement gratuit à zéro.
- ✅ Génération des reçus à partir des données réelles : élève, classe, nature, date, montant, établissement, direction et référence.
- ✅ Annulation clairement visible sur le PDF.
- ✅ Isolation tenant/direction appliquée côté serveur.
- ✅ Aucune transaction réelle ni donnée financière n’a été modifiée par la campagne ; les tests Flutter utilisent des doubles/magasins isolés.

## 8. Documents et bulletins

- ✅ Historique, recherche, filtres et pagination serveur.
- ✅ Limite Documents maintenue à 100 éléments par page maximum.
- ✅ Les cinq documents récents restent pris en charge par l’interface.
- ✅ Bulletins Maternelle/Primaire sur 10, Collège/Lycée sur 20.
- ✅ Génération PDF Maternelle, Primaire et Lycée via le moteur partagé.
- ✅ Fichier réel sauvegardé et ouvrable par les tests.
- ✅ Les données d’un bulletin sont issues du contexte officiel élève/classe/période.
- ✅ Aucun endpoint d’upload ou serveur de fichiers arbitraire n’existe actuellement ; la surface upload dangereuse est donc absente.

## 9. Notes et résultats

- ✅ Brouillon modifiable uniquement dans le contexte enseignant autorisé.
- ✅ Soumission, validation, demande de correction et verrouillage couverts.
- ✅ Une autre classe, matière, affectation ou direction ne peut pas être injectée pour élargir l’accès.
- ✅ Les évaluations non validées sont ignorées dans les calculs officiels.
- ✅ États prêt/en attente/officiel et publication vérifiés.
- ✅ Classements avec égalités et isolation entre établissements testés.
- ✅ Décision annuelle et réinscription testées.

## 10. Présence, comportement et emploi du temps

- ✅ Présence liée à une séance, une classe, une matière, une date, une année et une affectation enseignant.
- ✅ Règle conservée : avant le début refusé ; dès le début et jusqu’à la fin de la journée locale autorisé ; hier/demain refusés.
- ✅ Statistiques de présence dérivées et consultation Admin testées.
- ✅ Comportement limité au relevé de l’enseignant, note de 1 à 5, commentaire et verrouillage.
- ✅ Plusieurs contributions et calcul officiel préservés.
- ✅ Emploi du temps enseignant en lecture seule et filtré ; espaces Élève/Parent chargés selon leur contexte.

## 11. Parent et Élève

- ✅ Plusieurs enfants supportés par le workspace Parent.
- ✅ Enfant non lié invisible.
- ✅ Les coordonnées privées des autres responsables ne sont pas exposées.
- ✅ Accès Parent explicite, idempotent, contrôlé par rôle, plan et scope.
- ✅ Synchronisation sécurisée de l’email du responsable et du compte lié.
- ✅ Menus Parent limités aux flux réellement supportés : tableau de bord, notes, emploi du temps, messages.
- ✅ Maternelle/Primaire : pas de compte élève autonome.
- ✅ Collège/Lycée : compte selon configuration et accès en lecture à son propre périmètre.

## 12. Plans et abonnements

- ✅ Capacités contrôlées côté backend, pas uniquement dans Flutter.
- ✅ Plan inférieur : refus des fonctions premium.
- ✅ Plan supérieur : autorisation si le rôle et le scope l’autorisent aussi.
- ✅ `parents.access` contrôle la création/réinitialisation de l’espace Parent.
- ✅ Prix négatif et durée invalide bloqués.
- ✅ Désactivation d’un plan sans altération arbitraire des abonnements existants.

## 13. Formulaires, matricules et configuration établissement

- ✅ Formulaires d’établissement, direction, élève, parent, enseignant, matière, niveau, série, classe, affectation, année, tarif et plan couverts par la régression existante.
- ✅ Préremplissage, validations, sauvegarde et persistance vérifiés sur les parcours représentatifs.
- ✅ Matricule permanent conservé lors d’une réinscription.
- ✅ Recherche et login par matricule couverts.
- ✅ Configuration de base respecte le choix de création du référentiel ; elle ne crée pas automatiquement direction, classe, enseignant, élève, parent, finance, présence, document ou résultat.
- ✅ Aucun mécanisme de démarrage ne crée `admin@edupro.com`, un établissement fictif ou des données métier fictives.

## 14. Validation des entrées, SQL, pagination et concurrence

- ✅ UUID/IDs invalides traités sans exposition d’erreur interne.
- ✅ Dates et montants validés dans les flux concernés.
- ✅ Pagination Documents : page ≥ 1, taille entre 1 et 100.
- ✅ Requêtes ORM paramétrées ; aucune concaténation SQL utilisateur dangereuse trouvée.
- ✅ Contraintes d’unicité et transactions existantes conservées pour matricules, affectations, paiements et ressources uniques.
- ✅ Aucun moteur parallèle de calcul, PDF ou paiement introduit.

## 15. Secrets, erreurs, logs et sécurité Web

- ✅ `DATABASE_URL` et `JWT_SECRET` obligatoires via environnement.
- ✅ Aucun secret réel recopié dans ce rapport.
- ✅ `.env` non versionné ; `.env.example` ne contient que des valeurs factices/documentaires.
- ✅ Les messages HTTP ne renvoient pas de stack trace, SQL, chemin local ou secret.
- ✅ Le client Flutter masque les détails techniques inattendus.
- ✅ CORS restrictif et en-têtes de sécurité vérifiés en HTTP réel.
- ✅ Health check final : `200 {"status":"ok"}`.
- ✅ Logs du serveur final : démarrage complet, health checks, tests CORS et rate limit attendus ; aucune exception ou erreur 500.

## 16. Performance

- ✅ Aucun chargement global ajouté au Parent ; le workspace est relationnel et minimal.
- ✅ Aucun appel supplémentaire inutile sur les parcours existants.
- ✅ Pagination Documents conservée.
- ✅ Limiteur de login borné et nettoyé par fenêtre temporelle.
- ✅ Build optimisé avec tree-shaking des polices.

## 17. Tests exécutés

### Backend

- Suite complète : **131 passed, 1 skipped, 0 failed**.
- Couverture : auth, mots de passe, scopes, IDOR, plans, Parent, Élève, Finance, Documents, Notes/Résultats, Présence, Comportement, emploi du temps et configuration.
- Compilation Python des fichiers touchés : réussie.

### Sécurité HTTP réelle

- Health check : 200.
- CORS local : 200.
- CORS origine arbitraire : 400.
- Login erroné : 401.
- Huit échecs successifs puis limitation : 429.
- En-têtes `nosniff`, `DENY`, `no-referrer` : présents.
- `admin@edupro.com` : réponse 401 et **0 ligne** dans PostgreSQL.

### Flutter ciblé

- Auth/session/Parent : **36/36 réussis**.
- Analyse finale des fichiers sensibles : **No issues found**.

### Flutter global

- 54 fichiers de tests parcourus.
- **235 réussis, 3 ignorés, 0 échec**.
- Les 3 tests ignorés nécessitent volontairement `TEST_LOGIN_EMAIL` et `TEST_LOGIN_PASSWORD`; aucun identifiant réel n’a été injecté ou exposé.

### Build Web

- Commande : `flutter build web --release`.
- Résultat : **réussi en 324,1 s**.
- Wasm dry run : réussi.
- `build/web/index.html` : 1 570 octets.
- `build/web/main.dart.js` : 4 777 170 octets.

## 18. Checklist finale

### Authentification

- ✅ Login Super Admin/Admin
- ✅ Login Enseignant
- ✅ Login Parent
- ✅ Login Élève
- ✅ Logout et purge
- ✅ Restauration de session
- ✅ `/auth/me`
- ✅ Expiration/invalidation JWT
- ✅ Changement et reset de mot de passe
- ✅ Accès temporaire
- ✅ Compte/profil désactivé
- ✅ Limitation des tentatives

### RBAC et plans

- ✅ Super Admin
- ✅ Admin
- ✅ Enseignant
- ✅ Parent
- ✅ Élève
- ✅ Rôle + plan + scope
- ✅ Actions sensibles backend

### Isolation

- ✅ Établissement
- ✅ Direction
- ✅ Classe/matière/affectation
- ✅ Parent/enfant
- ✅ Élève
- ✅ IDOR
- ✅ Mass assignment sensible

### Modules métier

- ✅ Finance et reçus
- ✅ Documents et pagination
- ✅ Bulletins et PDF A5
- ✅ Notes et résultats
- ✅ Présence
- ✅ Comportement
- ✅ Emploi du temps
- ✅ Plans/abonnements
- ✅ Configuration établissement
- ✅ Formulaires transversaux
- ✅ Matricules/réinscription

### Plateforme

- ✅ Validation des entrées
- ✅ SQL/ORM
- ✅ CORS
- ✅ Secrets/configuration
- ✅ Logs/erreurs
- ✅ Cache/local storage
- ✅ Données personnelles
- ✅ Sécurité Web
- ✅ Performance
- ✅ Build Web Release
- ✅ Régression backend
- ✅ Régression Flutter

Il ne reste aucun élément `⬜ NON AUDITÉ` et aucun blocage nécessitant une migration ou une opération destructive.

## 19. Données, migrations et fichiers de travail

- Migration créée pendant cet audit : **NON**.
- Modification de schéma : **NON**.
- Reset PostgreSQL : **NON**.
- Reseed : **NON**.
- Suppression de table : **NON**.
- Suppression d’utilisateur/document/finance/résultat : **NON**.
- Modification d’un mot de passe existant : **NON**.
- Restauration de données prétendue ou effectuée : **NON**.
- Modifications destructives : **NON**.

Intégrité vérifiée des migrations de travail :

- `0022_finalize_teacher_direction_and_assignment_uniqueness.sql` — SHA-256 `B09E4B4947EB91EFA29DD3C0CF654F734CB1FDE03F0BDEE29B0BB5F4471E8463`
- `0023_behavior_teacher_sheets.sql` — SHA-256 `D6054D63F7A218A6A23B348A9248C7A1A94E4F3E94259DF8D4C4741336E1A7EE`
- `0024_attendance_sheets_and_schedule_history.sql` — SHA-256 `66409BBCCA6C97718B040D2C488BBE1CB6B5E5072A57B61337474E24028D065E`

Les nombreux changements préexistants du répertoire de travail, y compris l’environnement virtuel versionné, ont été laissés intacts. Aucun nettoyage Git destructif n’a été exécuté.

## 20. Fichiers fonctionnels concernés par les corrections de cet audit

- `backend/app/main.py`
- `backend/.env.example`
- `backend/tests/test_auth_guards.py`
- `backend/tests/test_plan_capabilities.py`
- `lib/data/datasources/api_client.dart`
- `lib/data/repositories/school_repository.dart`
- `lib/data/services/store_service.dart`
- `lib/features/school/students/students_page.dart`
- `lib/navigation/nav_items.dart`
- `test/authentication_completion_test.dart`
- `test/login_flow_test.dart`
- `test/parent_workspace_test.dart`

Le serveur final reste lancé avec le processus Python PID `17072`, à l’écoute sur `0.0.0.0:8000`.

**AUDIT COMPLET + SÉCURISATION + RÉGRESSION — TERMINÉ**
