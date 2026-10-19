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

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
