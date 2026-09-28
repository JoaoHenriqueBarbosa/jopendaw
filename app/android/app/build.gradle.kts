import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "tech.johnenrique.jopendaw"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "tech.johnenrique.jopendaw"
        // O motor de áudio nativo (libjopendaw_engine.so) toca e grava pelo AAudio, que chegou no
        // Android 8.0 (API 26). O Flutter aceita menos; vale o maior dos dois, para um plugin que
        // um dia peça mais não ser rebaixado aqui.
        minSdk = maxOf(flutter.minSdkVersion, 26)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // As ABIs em que o motor é compilado (engine/build-android.sh) e que o Flutter também traz:
        // um aparelho x86 de 32 bits não teria nenhum dos dois, e sem o filtro uma dependência com
        // .so de x86 faria a loja oferecer o app a ele. Os .so ficam commitados no lugar padrão
        // (src/main/jniLibs/<abi>/), como o engine.wasm da web, para o build não precisar de Rust.
        // Com --split-per-abi quem separa é o Flutter, e um filtro aqui daria conflito com o dele.
        if (project.findProperty("split-per-abi")?.toString()?.toBoolean() != true) {
            ndk {
                abiFilters.addAll(listOf("arm64-v8a", "armeabi-v7a", "x86_64"))
            }
        }
        // O id do app do Discord (o mesmo DISCORD_CLIENT_ID do servidor): a volta da autorização
        // feita no app do Discord chega pelo esquema `discord-{id}:` (AndroidManifest.xml). Vem de
        // `-PdiscordClientId=` ou de android/gradle.properties.
        manifestPlaceholders["discordClientId"] = (project.findProperty("discordClientId") as String?) ?: "0"
    }

    // A chave de release fica fora do repositório (android/key.properties aponta para ela; o
    // padrão é ~/.config/jopendaw/android-release.properties). Sem ela, o release sai com a chave
    // de debug, que serve para testar mas não abre os links dos emails (o assetlinks.json do
    // domínio só confia na de release).
    val keyProps = Properties().apply {
        val local = rootProject.file("key.properties")
        val home = File(System.getProperty("user.home"), ".config/jopendaw/android-release.properties")
        val file = if (local.exists()) local else home
        if (file.exists()) file.inputStream().use { load(it) }
    }
    signingConfigs {
        if (keyProps.getProperty("storeFile") != null) {
            create("release") {
                storeFile = file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
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
