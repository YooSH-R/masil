allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// kakao_map_plugin 0.4.0 은 자기 android/build.gradle 에 compileSdk 35 를 하드코딩해
// 두었는데, 이 플러그인이 의존하는 webview_flutter_android 는 compileSdk 를
// flutter.compileSdkVersion(=36) 으로 잡는다. 그러면 AAR 메타데이터 검사에서
//   "Dependency ':webview_flutter_android' requires ... compile against version 36
//    or later. :kakao_map_plugin is currently compiled against android-35"
// 로 빌드가 깨진다. 플러그인 쪽을 고칠 수 없으니 여기서 서브프로젝트의 compileSdk 를
// 끌어올린다. 플러그인이 36 으로 올라오면 이 블록은 지워도 된다.
//
// 주의: 아래 evaluationDependsOn(":app") 보다 먼저 등록해야 한다. 그 뒤에 두면
// 이미 평가가 끝난 프로젝트에 afterEvaluate 를 걸게 되어 빌드가 실패한다.
// AGP 타입을 루트 스크립트 classpath 에 올리지 않으려고 리플렉션으로 호출한다.
subprojects {
    afterEvaluate {
        val androidExtension = extensions.findByName("android") ?: return@afterEvaluate
        runCatching {
            androidExtension.javaClass
                .getMethod("setCompileSdkVersion", Int::class.javaPrimitiveType)
                .invoke(androidExtension, 36)
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
