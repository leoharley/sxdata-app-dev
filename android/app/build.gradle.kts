import java.io.FileInputStream
import java.util.Properties

// Assinatura da Play Store: android/key.properties (fora do git) aponta para a
// keystore de upload. Sem o arquivo, o release sai com a chave de debug, como
// antes -- serve para APK de teste, mas a Play Store recusa.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.sxdata"
    // Android 16 (API 36): o Play Protect bloqueia a instalação de apps com
    // targetSdk abaixo do exigido pela versão do sistema ("app criado para
    // uma versão mais antiga do Android"). compileSdk acompanha o targetSdk.
    compileSdk = 36
    // Versão exigida pelos plugins (sqflite_android, wakelock_plus e outros);
    // maior que a default do Flutter e retrocompatível.
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // O ID do app na Play Store (play.google.com/store/apps/details?id=br.com.sxdata.app).
        // Precisa ser EXATAMENTE este: com outro ID o build vira um segundo
        // app no celular, que não enxerga as coletas pendentes do app da loja.
        // O namespace e o pacote Kotlin (com.example.sxdata) não precisam mudar.
        applicationId = "br.com.sxdata.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 23
        // Fixado em 36 em vez de flutter.targetSdkVersion (que nesta versão
        // do Flutter ainda é 35) para não ser bloqueado no Android 16.
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("upload") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("upload")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
