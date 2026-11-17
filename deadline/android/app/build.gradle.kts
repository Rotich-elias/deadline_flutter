import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasSigningConfig = keystorePropertiesFile.exists()
if (hasSigningConfig) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "com.deadline.app.deadline"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.deadline.app.deadline"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasSigningConfig) {
                val storePath = keystoreProperties["storeFile"] as String?
                val storePasswordValue = keystoreProperties["storePassword"] as String?
                val keyAliasValue = keystoreProperties["keyAlias"] as String?
                val keyPasswordValue = keystoreProperties["keyPassword"] as String?
                val store = storePath?.let { rootProject.file(it) }

                if (store == null || !store.exists() ||
                    storePasswordValue.isNullOrBlank() ||
                    keyAliasValue.isNullOrBlank() ||
                    keyPasswordValue.isNullOrBlank()
                ) {
                    throw GradleException(
                        "Release signing is not configured. Create android/key.properties " +
                            "with storeFile, storePassword, keyAlias and keyPassword, " +
                            "and make sure the keystore exists.",
                    )
                }

                storeFile = store
                storePassword = storePasswordValue
                keyAlias = keyAliasValue
                keyPassword = keyPasswordValue
            }
        }
    }

    buildTypes {
        release {
            if (!hasSigningConfig) {
                throw GradleException(
                    "Missing android/key.properties: refusing to build a release " +
                        "signed with the debug key. See PLAY_STORE_DEPLOYMENT.md.",
                )
            }
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // local_auth requires a Theme.AppCompat parent for the biometric dialog.
    implementation("androidx.appcompat:appcompat:1.7.0")
}
