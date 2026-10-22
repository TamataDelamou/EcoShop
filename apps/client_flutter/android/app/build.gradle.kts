import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Notifications push (Firebase Cloud Messaging) : actives dès que le fichier
// google-services.json, téléchargé depuis la console Firebase, est déposé
// dans android/app/. Sans lui, l'application se construit et fonctionne
// normalement, sans notifications push.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

val proprietesCle = Properties().apply {
    val fichier = rootProject.file("key.properties")
    if (fichier.exists()) fichier.inputStream().use { load(it) }
}

android {
    namespace = "com.gsg.ecoshop_client"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.gsg.ecoshop_client"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Signature de publication (Play Store) : clé de GSG décrite par
    // android/key.properties, créé par scripts/construire_android.ps1 et
    // jamais versionné. Sans lui (poste de développement), la clé de
    // débogage permet toujours `flutter run --release`.
    signingConfigs {
        if (proprietesCle.isNotEmpty()) {
            create("publication") {
                keyAlias = proprietesCle.getProperty("keyAlias")
                keyPassword = proprietesCle.getProperty("keyPassword")
                storeFile = file(proprietesCle.getProperty("storeFile"))
                storePassword = proprietesCle.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (proprietesCle.isNotEmpty()) {
                signingConfigs.getByName("publication")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
