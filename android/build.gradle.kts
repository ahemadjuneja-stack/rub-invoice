allprojects {
    repositories {
        google()
        mavenCentral()
        // CDN mirror of Maven Central, used as fallback on HTTP 429 throttling.
        maven("https://repo1.maven.org/maven2")
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
subprojects {
    project.evaluationDependsOn(":app")
}

// Some vendor plugins (e.g. file_picker 8.x) pin their own older compileSdk
// (android-34). Their transitive AAR metadata (flutter_plugin_android_lifecycle)
// requires consumers to compile against API 36+, which fails
// :plugin:checkReleaseAarMetadata. Align every Android subproject up to the
// app's compileSdk (36) after evaluation.
fun Project.alignCompileSdkTo(minApi: Int) {
    val androidExt = extensions.findByName("android") ?: return
    val getCompileSdk = androidExt.javaClass.methods.firstOrNull { it.name == "getCompileSdk" } ?: return
    val setCompileSdk = androidExt.javaClass.methods.firstOrNull { it.name == "setCompileSdk" } ?: return
    val current = (getCompileSdk.invoke(androidExt) as? Int) ?: 0
    if (current < minApi) {
        setCompileSdk.invoke(androidExt, minApi)
    }
}

subprojects {
    // :app is force-evaluated earlier via evaluationDependsOn above, so it is
    // already executed here; the rest register an afterEvaluate hook.
    if (state.executed) {
        alignCompileSdkTo(36)
    } else {
        afterEvaluate { alignCompileSdkTo(36) }
    }
    // AGP 9: some vendor plugins (file_picker 8.x) register through
    // com.android.internal.library; attach the alignment at plugin
    // application time as well so the hook can never miss them.
    listOf(
        "com.android.library",
        "com.android.internal.library",
        "com.android.application",
    ).forEach { pluginId ->
        plugins.withId(pluginId) {
            afterEvaluate { alignCompileSdkTo(36) }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
