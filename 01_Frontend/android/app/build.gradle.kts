import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 카카오 로그인 리다이렉트 스킴(kakao{네이티브앱키}://oauth)에 쓸 앱 키.
// android/local.properties 의 `kakao.nativeAppKey=...` 또는
// 환경변수 KAKAO_NATIVE_APP_KEY 에서 읽는다. 없으면 빈 값(빌드는 성공하되
// 카카오 로그인만 동작하지 않음).
val kakaoNativeAppKey: String = run {
    val props = Properties()
    val file = rootProject.file("local.properties")
    if (file.exists()) {
        FileInputStream(file).use { props.load(it) }
    }
    props.getProperty("kakao.nativeAppKey")
        ?: System.getenv("KAKAO_NATIVE_APP_KEY")
        ?: ""
}

android {
    namespace = "com.example.mysil_project_new"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.mysil_project_new"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // AndroidManifest.xml 의 ${kakaoNativeAppKey} 로 치환된다.
        manifestPlaceholders["kakaoNativeAppKey"] = kakaoNativeAppKey
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
