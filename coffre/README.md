# Coffre

App Android personnelle, privée, hors-ligne par défaut : idées, tâches, notes et rappels au même endroit.
Saisie au clavier ou à la voix, rappels fiables sur Samsung, données chiffrées sur le téléphone.

- **Jour** : ce qui compte maintenant, aujourd'hui, cette semaine, plus une idée récente à ne pas perdre.
- **Flux** : tout le contenu, avec filtres, recherche, tri et gestes de balayage.
- **Barre de capture** toujours en bas : tu écris ou dictes, Coffre devine le type, la date, la priorité
  et le contexte (Travail, Santé, Admin…), tu relis l'aperçu, tu envoies. Le texte d'origine est gardé.
- **Plus tard** sur chaque carte, **pré-alerte** 1 h 30 avant un rendez-vous, report 5/15/60 min depuis la notification.
- **Rappel réglable** : date et heure modifiables séparément, heures « matin » et « soir » par défaut au choix (Réglages).
- **Rappels répétés** : chaque jour, en semaine, chaque semaine, toutes les 2 semaines, chaque mois, tous les 3 mois, chaque année. Se dicte (« réunion d'équipe chaque lundi à 9h », « tous les soirs »). « Fait » renvoie l'élément à sa prochaine date.
- **Partager › Coffre** depuis Gmail, WhatsApp, Notes… : le texte arrive dans l'écran de capture.
- **Verrouillage par empreinte** (ou code du téléphone), à l'ouverture et après 1 minute en arrière-plan (*Réglages › Confidentialité*).
- **Assistant IA** : synthétiser, développer, découper en tâches, reformuler, rédiger un message, brief du jour.
  Au choix : **Gemini** (Google, clé gratuite) ou **Claude** (Anthropic, payant à l'usage).
- **Agenda Google** : rendez-vous du jour dans *Jour*, ajout d'un rappel à l'agenda (via l'agenda du téléphone, sans connexion Google).
- **Notion** (optionnel) : envoyer un élément dans une base Notion.

- **Aucun compte, aucun serveur, aucune statistique.** Internet sert uniquement à l'IA et à Notion, quand tu le demandes.
- **Base chiffrée** (SQLite3 Multiple Ciphers, ChaCha20). La clé est générée au premier lancement et reste dans le Keystore Android.
- **Sauvegarde** : export JSON (restaurable) ou CSV (Excel), à l'endroit que tu choisis. ⚠️ Ces fichiers ne sont pas chiffrés.

---

## Installer depuis le téléphone uniquement (sans PC)

GitHub compile l'app à chaque modification, la signe avec ta clé personnelle et la publie à une adresse fixe.

**Une seule fois : le secret de signature**
1. Sur le téléphone, ouvrir dans le navigateur (connecté à GitHub) :
   https://github.com/Corben020975/SAFA/settings/secrets/actions/new
2. *Name* : `COFFRE_KEY_PASSWORD`. *Secret* : le mot de passe de 32 caractères donné par Claude. Puis **Add secret**.
3. Noter aussi ce mot de passe dans ton gestionnaire de mots de passe.
4. Lancer une compilation : onglet *Actions* › « Coffre – APK » › *Run workflow* (environ 6 minutes).

**Installer ou mettre à jour**
1. Ouvrir https://github.com/Corben020975/SAFA/releases/latest/download/coffre.apk (à mettre en favori).
2. Ouvrir le fichier téléchargé › autoriser le navigateur à « installer des applis inconnues » › **Installer**.
   - Si Samsung bloque : *Paramètres › Sécurité et confidentialité › Blocage automatique* › désactiver le temps de l'installation.
   - Si Play Protect avertit : *Plus de détails › Installer quand même*.
3. Mise à jour : même lien, installer par-dessus. Les données sont conservées.

Ensuite, suivre l'étape 7 ci-dessous (réglages Samsung).

La clé (`android/signing/coffre-release.p12`) est chiffrée en AES-256. Sans le mot de passe, elle est inutilisable. L'APK publié ne contient aucune donnée personnelle.

---

## Installer avec un PC (alternative)

Compte environ 1 h la première fois, surtout du téléchargement. Les exemples sont pour **Windows**. Sur Mac, c'est la même chose avec le Terminal.

### 1. Installer les outils

1. **Git** : https://git-scm.com/download/win → installer avec les options par défaut.
2. **Android Studio** : https://developer.android.com/studio → installer avec les options par défaut, lancer une fois, laisser l'assistant télécharger le SDK Android.
   - Dans Android Studio : *More Actions › SDK Manager › SDK Tools*, cocher **Android SDK Command-line Tools** et **NDK (Side by side)**, puis *Apply*.
   - *Plugins* : installer **Flutter** (Dart vient avec).
3. **Flutter 3.47** : https://docs.flutter.dev/get-started/install/windows/mobile
   - Dézipper dans `C:\dev\flutter`. Pas dans `Program Files`, car les espaces et les droits posent problème.
   - Ajouter `C:\dev\flutter\bin` au PATH : touche Windows › « variables d'environnement » › *Path* › *Modifier* › *Nouveau*.
4. Ouvrir un **nouveau** terminal (PowerShell) :
   ```powershell
   flutter doctor --android-licenses   # répondre y à tout
   flutter doctor                      # « Android toolchain » doit être vert
   ```

### 2. Récupérer et ouvrir le projet

```powershell
cd C:\dev
git clone https://github.com/Corben020975/SAFA.git
cd SAFA
git checkout claude/coffre-flutter-app-9p9qa7
```

Dans Android Studio : *File › Open* › choisir le dossier **`SAFA\coffre`**, pas `SAFA`.

### 3. Préparer le téléphone (mode développeur)

1. *Paramètres › À propos du téléphone › Informations sur le logiciel* › toucher **7 fois « Numéro de version »**, puis entrer ton code.
2. *Paramètres › Options de développement* › activer **Débogage USB**.
3. Brancher le téléphone en USB-C au PC. Accepter la fenêtre « Autoriser le débogage USB ? » en cochant *Toujours autoriser*.
4. Vérifier : `flutter devices` doit lister le S26 Ultra.

### 4. Premier lancement (version de test)

```powershell
cd C:\dev\SAFA\coffre
flutter pub get
flutter run
```

La première compilation prend 5 à 15 minutes (Gradle, NDK, SQLite chiffré). **Une connexion Internet est nécessaire pour compiler**, pas pour utiliser l'app.

### 5. Construire l'APK définitif (avec ta propre clé)

Ta clé signe l'app. Garde-la précieusement : sans elle, impossible de mettre l'app à jour sans la désinstaller.

1. Créer la clé, une seule fois :
   ```powershell
   & "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -genkey -v `
     -keystore C:\Users\$env:USERNAME\coffre-cle.jks -keyalg RSA -keysize 2048 `
     -validity 10000 -alias coffre
   ```
   Note le mot de passe dans ton gestionnaire de mots de passe. Sauvegarde le fichier `.jks` (clé USB par exemple).
2. Créer le fichier `coffre\android\key.properties` (il n'est jamais envoyé sur GitHub) :
   ```properties
   storePassword=TON_MOT_DE_PASSE
   keyPassword=TON_MOT_DE_PASSE
   keyAlias=coffre
   storeFile=C:/Users/TON_NOM/coffre-cle.jks
   ```
   Utilise des `/` dans le chemin, pas des `\`.
3. Construire :
   ```powershell
   flutter build apk --release --target-platform android-arm64
   ```
   Le fichier obtenu : `coffre\build\app\outputs\flutter-apk\app-release.apk`.

### 6. Installer l'APK

- **Par câble (le plus simple)** : `flutter install --release`
- **Sans câble** : copier `app-release.apk` sur le téléphone, l'ouvrir dans *Mes fichiers* › autoriser « Installer des applis inconnues » pour *Mes fichiers*.
  - Si Samsung refuse : *Paramètres › Sécurité et confidentialité › Blocage automatique* › désactiver le temps de l'installation, puis réactiver.
  - Si Play Protect avertit « application inconnue » : *Plus de détails › Installer quand même*.

**Mises à jour** : augmenter `version:` dans `pubspec.yaml` (par ex. `1.0.1+2`), reconstruire, réinstaller par-dessus. Tes données sont conservées si la clé est la même.

### 7. Réglages Samsung pour des rappels fiables

L'assistant « Rappels fiables » s'ouvre au premier lancement. Il est aussi accessible dans *Réglages › Vérifier la fiabilité des rappels*. À la main :

| Réglage | Chemin | Valeur |
|---|---|---|
| Notifications | *Paramètres › Applications › Coffre › Notifications* | Autorisées. Catégorie « Rappels » : son + fenêtre contextuelle |
| Batterie | *Paramètres › Applications › Coffre › Batterie* | **Non restreinte** |
| Jamais en veille | *Paramètres › Batterie › Limites d'utilisation en arrière-plan › Applications jamais en veille* | Ajouter **Coffre** |
| Veille profonde | Même écran, *Applications en veille profonde* | Coffre **absent** |
| Ne pas déranger | *Paramètres › Notifications › Ne pas déranger › Applis* | Ajouter Coffre si tu veux les rappels même en mode DND |
| Dictée hors-ligne | *Paramètres › Gestion globale › Langue et saisie* (moteur Google ou Samsung) | Télécharger **Français** hors-ligne |

**Widget** : appui long sur l'écran d'accueil › *Widgets* › *Coffre* › glisser « Coffre – Ajouter ».

**Test final** : *Réglages › Notification de test dans 1 minute*. Balaie l'app hors des récentes, verrouille l'écran, attends.

---

## Connecter l'IA, l'agenda et Notion

Tout est optionnel et se règle dans *Réglages*. Les clés restent dans le Keystore du téléphone et ne sont jamais exportées.

**Assistant IA avec Gemini (gratuit, par défaut)**
1. Sur [aistudio.google.com](https://aistudio.google.com) (compte Google, sans carte bancaire) : *Get API key* › *Créer une clé API*, copier la clé (`AIza…`).
2. *Réglages › Assistant IA* › *Gemini (gratuit)* › *Clé API Gemini* : coller la clé, puis *Tester*.
3. Limites de l'offre gratuite : quelques demandes par minute et un plafond par jour. Google peut conserver et relire les textes de l'offre gratuite : garder le masquage activé.

**Assistant IA avec Claude (payant, optionnel)**
1. Sur [console.anthropic.com](https://console.anthropic.com) : créer un compte, ajouter du crédit (paiement à l'usage), *API Keys › Create Key*.
2. *Réglages › Assistant IA* › *Claude (payant)* › *Clé API Claude* : coller la clé, puis *Tester*.
3. Dans un élément : bouton ✦ ou *Assistant IA*. Dans *Jour* : icône ✦ pour le brief du jour.

Avant chaque envoi, Coffre masque les noms précédés d'une civilité (Mme, M., Dr…), n° de registre national, téléphones, e-mails et IBAN, puis les remet dans la réponse. Le masquage ne détecte pas tout : pas d'information sensible sur un bénéficiaire (secret professionnel).

**Agenda Google**
1. Le compte Google doit être synchronisé dans l'app *Agenda* du téléphone (Samsung Calendar ou Google Agenda).
2. *Réglages › Agenda Google › Afficher mon agenda dans Jour* : activer, autoriser l'accès. L'agenda Google principal est choisi automatiquement (modifiable).
3. *Jour* affiche les rendez-vous d'aujourd'hui et demain ; dans un élément avec rappel : *Ajouter à l'agenda*.

**Notion**
1. Sur [notion.so/my-integrations](https://www.notion.so/my-integrations) : *Nouvelle intégration* (interne), copier le jeton.
2. Dans Notion, ouvrir la base cible › `•••` › *Connexions* › ajouter l'intégration.
3. *Réglages › Notion › Jeton d'intégration* : coller le jeton, puis *Base de destination*.
4. Dans un élément : *Envoyer vers Notion* (titre, date du rappel si la base a une colonne date, texte complet).
5. **Import (Grokbot…)** : *Réglages › Notion › Base à importer*, puis le contexte des tâches (ex. Travail). La base doit aussi être partagée avec l'intégration (••• › Connexions).
   - À chaque ouverture de Coffre, les nouvelles tâches arrivent dans l'Inbox : titre, notes et contenu de la page, échéance → rappel (9 h sans heure), P1/P2/P3 → priorité, listes (Contexte, Domaine…) → tags, Bloqué / Délégué → tags.
   - Une tâche passée à « Fait » dans Notion se ferme dans Coffre ; « Fait » dans Coffre la passe à « Fait » dans Notion (après le délai d'annulation).
   - Sans doublon : le lien de la page est gardé.

---

## Si ça ne compile pas

| Message | Cause | Correctif |
|---|---|---|
| `'flutter' n'est pas reconnu…` | PATH non configuré | Ajouter `C:\dev\flutter\bin` au PATH, **fermer et rouvrir** le terminal |
| `Android license status unknown` / `licences not accepted` | Licences SDK non acceptées | `flutter doctor --android-licenses`, répondre `y` |
| `Unsupported class file major version` / `requires JVM 17` | Mauvais Java | `flutter config --jdk-dir "C:\Program Files\Android\Android Studio\jbr"` |
| `NDK … did not have a source.properties file` / `NDK not configured` | NDK absent ou téléchargement interrompu | SDK Manager › SDK Tools › *Show Package Details* › NDK `28.2.13676358` ; supprimer le dossier `ndk\…` abîmé et réinstaller |
| `Failed to download … sqlite3mc` / erreur de hook `sqlite3` | GitHub bloqué (réseau pro, proxy) | Compiler depuis un autre réseau (maison, partage 4G), puis `flutter clean` et relancer |
| `Could not reserve enough space for object heap` | PC avec peu de RAM | Dans `android/gradle.properties`, remplacer `-Xmx4G` par `-Xmx2G` |

Réflexe général après un changement de version : `flutter clean` puis `flutter pub get`.
À l'installation, `INSTALL_FAILED_UPDATE_INCOMPATIBLE` (« conflit avec un package existant ») signifie que la clé est différente : exporter en JSON, désinstaller, réinstaller, importer.

---

## Personnaliser

- **Nom** : `android/app/src/main/res/values/strings.xml` (`app_name`) et `lib/app.dart` (`title`).
- **Couleur** : `_seed` dans `lib/ui/theme.dart` et `ic_launcher_background` dans `res/values/colors.xml`.
- **Schéma de base** modifié (`lib/data/database.dart`) : `dart run build_runner build`, puis incrémenter `schemaVersion` et écrire la migration.

## Structure

```
lib/
  main.dart               démarrage, ouverture de la base, resynchronisation des rappels
  app.dart                MaterialApp, thème, routes
  core/                   services partagés, normalisation texte, formats de date
  data/                   Drift (tables, requêtes), chiffrement, réglages, sauvegarde
  services/               notifications (+ isolate snooze), dictée, analyse de saisie, dates, vue Jour, pont Android
  services/ai/            clients Gemini et Claude (HTTP), assistant, masquage des données
  services/notion_service.dart   API Notion (jeton d'intégration)
  ui/screens/             accueil (Jour + Flux), Capture, Détail, Réglages, Rappels fiables
  ui/views/               vues Jour et Flux, agenda du jour, bandeaux d'alerte
  ui/widgets/             carte, ligne, barre de capture, sélecteurs, rappel, tags, micro, assistant IA
android/app/src/main/     Manifest, MainActivity.kt, widget, icônes
test/                     base + chiffrement, parseur de dates, parcours Inbox, IA, Notion, masquage
```
