pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

// Lets Gradle download the JDK it needs rather than failing when the machine's
// default JDK is the wrong version. With gradle/gradle-daemon-jvm.properties
// this makes `./gradlew` work on a clean checkout regardless of what is on PATH.
plugins {
    id("org.gradle.toolchains.foojay-resolver-convention") version "0.9.0"
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "DiffuseAndroid"
include(":app")
