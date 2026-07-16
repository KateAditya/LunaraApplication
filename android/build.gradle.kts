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
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    val configureNamespace = {
        val android = extensions.findByName("android") as? com.android.build.gradle.BaseExtension
        if (android != null) {
            if (android.namespace == null) {
                android.namespace = "com.example.${name.replace(":", "").replace("-", "_")}"
            }
            val manifestFile = file("src/main/AndroidManifest.xml")
            if (manifestFile.exists()) {
                try {
                    var content = manifestFile.readText()
                    if (content.contains("package=")) {
                        content = content.replace(Regex("""package\s*=\s*"[^"]*""""), "")
                        manifestFile.writeText(content)
                    }
                } catch (e: Exception) {
                    logger.warn("Failed to strip package attribute from ${manifestFile.path}: ${e.message}")
                }
            }
        }
    }
    if (state.executed) {
        configureNamespace()
    } else {
        afterEvaluate {
            configureNamespace()
        }
    }
}



tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}




