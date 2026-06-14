import java.util.Properties

plugins {
    id("com.google.gms.google-services")
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.master_taxi_gurlan"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    val keyPropsFile = rootProject.file("../../key.properties")
    val keyProps = Properties()
    if (keyPropsFile.exists()) keyProps.load(keyPropsFile.inputStream())

    signingConfigs {
        create("release") {
            storeFile     = file(keyProps["storeFile"] as String)
            storePassword = keyProps["storePassword"] as String
            keyAlias      = keyProps["keyAlias"] as String
            keyPassword   = keyProps["keyPassword"] as String
        }
    }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.master_taxi_gurlan"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

// ── dependencies android {} ТАШҚАРИСИДА ──
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}

