buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:9.0.1")
    }
}

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

    afterEvaluate {
        project.extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.let {
            it.compileSdkVersion(36)
        }
    }

    // Sustituir la dependencia privada play-services-tapandpay (no disponible públicamente)
    // por una dependencia pública equivalente para que la compilación y el lint no fallen.
    configurations.all {
        resolutionStrategy {
            dependencySubstitution {
                substitute(module("com.google.android.gms:play-services-tapandpay"))
                    .using(module("com.google.android.gms:play-services-base:18.5.0"))
                    .because("play-services-tapandpay es un SDK privado de Google no disponible en repositorios públicos")
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
