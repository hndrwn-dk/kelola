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
// Register before evaluationDependsOn so file_picker's compileSdk 34 is
// rewritten after its android {} block. Lifecycle 2.0.35 needs 36.
subprojects {
    afterEvaluate {
        if (name == "app") {
            return@afterEvaluate
        }
        val android = extensions.findByName("android") ?: return@afterEvaluate
        if (android is com.android.build.api.dsl.LibraryExtension) {
            android.compileSdk = 36
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
