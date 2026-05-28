import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Load keystore properties if the file exists
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// Keep this constant name — it's referenced below as `minSdk = pinnedMinSdk`.
// Using a constant (rather than a literal int at the `minSdk =` site) prevents
// flutter_tools' MinSdkVersionMigration from silently rewriting our pin, which
// would raise minSdk to Flutter's default and strand existing users.
val pinnedMinSdk = 23

android {
    // Match Kotlin package (MainActivity, NotesWidgetProvider)
    namespace = "com.aistickynotes.app"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.aistickynotes.app"
        // Pin minSdk explicitly so a Flutter SDK upgrade can't silently raise it
        // and cut off existing users on older devices (which blocks Play rollouts
        // with "this release doesn't allow any existing users to upgrade").
        // 23 matches the min_sdk_android used by flutter_launcher_icons in pubspec.yaml.
        //
        // NOTE: flutter_tools ships a MinSdkVersionMigration that rewrites any
        // literal `minSdk = 16..23` back to `flutter.minSdkVersion` on every build
        // (see min_sdk_version_migration.dart). We dodge that regex by routing the
        // value through a named constant — the migration only matches literal ints.
        minSdk = pinnedMinSdk
        targetSdk = 36       // Android 16 — required for new Play Store uploads (2026)
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        getByName("debug") {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
            isDebuggable = true
            isShrinkResources = false
            isMinifyEnabled = false
        }
        getByName("release") {
            signingConfig = if (keystorePropertiesFile.exists())
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")

            // R8 shrinks, obfuscates, and optimises the native code.
            isShrinkResources = true
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

// ──────────────────────────────────────────────────────────────────────
// Supply-chain pinning.
//
// Some Flutter plugins (notably home_widget) pull in androidx.glance
// transitively without pinning a major version. Google released
// `androidx.glance:glance-appwidget:1.3.0-alpha01` on 19 May 2026 which
// requires compileSdk 37 and Android Gradle Plugin 9.1.0+ — neither of
// which the Flutter 3.41 stack supports yet.
//
// Forcing the stable 1.1.1 line also removes the alpha
// `androidx.compose.remote:remote-creation-android` transitive that
// ships with glance 1.3.0-alpha01.
//
// Remove these `force(...)` lines once Flutter ships an AGP-9-compatible
// toolchain and we're ready to bump compileSdk to 37+.
// ──────────────────────────────────────────────────────────────────────
configurations.configureEach {
    resolutionStrategy {
        force("androidx.glance:glance:1.1.1")
        force("androidx.glance:glance-appwidget:1.1.1")
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
