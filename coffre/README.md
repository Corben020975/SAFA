# Coffre

App Android personnelle, privée et hors-ligne : idées, tâches, notes et rappels au même endroit.
Saisie au clavier ou à la voix, rappels fiables sur Samsung, données chiffrées sur le téléphone.

- **Aucun compte, aucun serveur, aucune statistique.** L'APK final n'a pas la permission Internet.
- **Base chiffrée** (SQLite3 Multiple Ciphers, ChaCha20). La clé est générée au premier lancement et reste dans le Keystore Android.
- **Sauvegarde** : export JSON (restaurable) ou CSV (Excel), à l'endroit que tu choisis. ⚠️ Ces fichiers ne sont pas chiffrés.

---

## Installer l'app sur le Galaxy S26 Ultra (guide débutant)

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

## Variante sans PC : APK de test via GitHub

Chaque modification poussée compile l'APK automatiquement : onglet **Actions** du dépôt › « Coffre – APK » › dernier run vert › *Artifacts* › `coffre-apk`.

⚠️ Cet APK est signé avec une clé jetable, différente à chaque compilation. Il sert à **tester**. Pour passer d'un APK GitHub à un autre, il faut désinstaller, donc exporter d'abord ses données en JSON. Pour l'usage quotidien, suis l'étape 5.

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
  services/               notifications (+ isolate snooze), dictée, parseur de dates, pont Android
  ui/screens/             Inbox, Capture, Détail, Réglages, Rappels fiables
  ui/widgets/             sélecteurs, rappel, tags, micro, ligne d'élément
android/app/src/main/     Manifest, MainActivity.kt, widget, icônes
test/                     base de données + chiffrement, parseur de dates, parcours Inbox
```
