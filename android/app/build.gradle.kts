import java.util.Properties
import java.io.FileInputStream

// Firma permanente. Las credenciales viven en android/key.properties,
// que esta en .gitignore: el repo no puede llevarlas.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val tieneFirmaPropia = keystorePropertiesFile.exists()
if (tieneFirmaPropia) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
} else {
    // Aviso ruidoso a proposito: firmar con la clave de depuracion sin
    // darse cuenta produce un APK que obliga a DESINSTALAR para
    // actualizar, y eso no se nota hasta que alguien esta parado al
    // lado del pinpad del cliente.
    println(
        "AVISO: no se encontro android/key.properties. El build de " +
        "release usara la clave de DEPURACION y no se podra instalar " +
        "encima de una version anterior."
    )
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "pe.techbot.payment_tester"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "pe.techbot.payment_tester"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (tieneFirmaPropia) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (tieneFirmaPropia) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
