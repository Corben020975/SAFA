import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Signature, par ordre de priorité :
// 1. android/key.properties (clé créée sur un PC, jamais versionnée) ;
// 2. android/signing/coffre-release.p12 + variable COFFRE_KEY_PASSWORD
//    (compilation GitHub : la clé est chiffrée, le mot de passe est un secret GitHub) ;
// 3. clé de debug de la machine (tests uniquement).
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) load(FileInputStream(keystorePropertiesFile))
}
val ciKeystore = rootProject.file("signing/coffre-release.p12")
val ciKeyPassword: String? = System.getenv("COFFRE_KEY_PASSWORD")?.takeIf { it.isNotBlank() }

android {
    namespace = "be.perso.coffre"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Requis par flutter_local_notifications (API java.time sur anciens Android).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "be.perso.coffre"
        // Android 8+ : canaux de notification natifs, icônes adaptatives.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        } else if (ciKeyPassword != null && ciKeystore.exists()) {
            create("release") {
                storeFile = ciKeystore
                storeType = "pkcs12"
                storePassword = ciKeyPassword
                keyAlias = "coffre"
                keyPassword = ciKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    // Gemini Nano sur le téléphone (ML Kit GenAI, via AICore).
    implementation("com.google.mlkit:genai-prompt:1.0.0-beta4")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
}

flutter {
    source = "../.."
}
