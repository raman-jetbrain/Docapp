allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
// Do not force evaluation of the ':app' project here — forcing evaluation can cause plugins
// to be applied twice and lead to the "Plugin with id 'com.android.application' was already requested" error.
// If you need ordering or task wiring, express it via task dependencies or lazy configuration instead.
    delete(rootProject.layout.buildDirectory)
}
