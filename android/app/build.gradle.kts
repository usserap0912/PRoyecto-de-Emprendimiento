plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ============================================================
// FIRMA DE PRODUCCIÓN (keystore generado con OpenSSL)
// ============================================================
// El archivo key.properties contiene las credenciales del
// keystore release-key.p12. NO incluir key.properties ni
// release-key.p12 en el control de versiones.
// ============================================================
import java.util.Properties

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { stream ->
        keystoreProperties.load(stream)
    }
}

android {
    namespace = "com.safezone.safezone"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.safezone.safezone"
        // ==========================================================
        // API KEY DE GOOGLE MAPS (Maps SDK for Android)
        // ==========================================================
        // Se lee de la variable de entorno MAPS_API_KEY (o de la propiedad
        // de Gradle mapsApiKey) y se inyecta en el AndroidManifest como
        // ${MAPS_API_KEY}. NO escribir la key aqui ni en el manifest.
        // Ejemplos:
        //   PowerShell:   $env:MAPS_API_KEY="AIza..."; flutter run
        //   Bash/WSL:     MAPS_API_KEY=AIza... flutter run
        // Si esta vacia, la app compila pero el mapa se ve en blanco.
        // ==========================================================
        val apiKey = System.getenv("MAPS_API_KEY")
            ?: (project.findProperty("mapsApiKey") as String?)
            ?: ""
        manifestPlaceholders["MAPS_API_KEY"] = apiKey
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.0"
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                storeFile = rootProject.file(keystoreProperties["storeFile"]!!)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Firma de producción con keystore propio
            signingConfig = signingConfigs.getByName("release")
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

