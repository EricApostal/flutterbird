// Only used when this project is built on its own (e.g. `./gradlew` run from
// this directory). When libbird is consumed as a Flutter plugin, the host
// app's settings are used instead and this file is ignored, so the host's
// Android Gradle Plugin is the one that applies.
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
    plugins {
        id("com.android.library") version "9.3.1"
    }
}

dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "ladybird"
