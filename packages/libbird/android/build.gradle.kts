group = "dev.flutterbird.ladybird"
version = "1.0-SNAPSHOT"

var buildDir = layout.buildDirectory.get()
var cacheDir = System.getenv("LADYBIRD_CACHE_DIR") ?: "$buildDir/caches"
var sourceDir = layout.projectDirectory.dir("../third_party/ladybird").toString()

buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:8.1.0")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

val ensureLadybirdSource = tasks.register<Exec>("ensureLadybirdSource") {
    workingDir = layout.projectDirectory.asFile
    commandLine = listOf("bash", "../tool/ensure_ladybird_source.sh")
}

val buildLagomTools = tasks.register<Exec>("buildLagomTools") {
    dependsOn(ensureLadybirdSource)
    workingDir = file(sourceDir)
    commandLine = listOf("Meta/ladybird.py", "install", "--preset", "Host_Tools")
    environment = mapOf(
        "PATH" to System.getenv("PATH")!!
    )
}
tasks.named("preBuild") {
    dependsOn(ensureLadybirdSource)
    dependsOn(buildLagomTools)
}
tasks.matching { it.name == "prepareKotlinBuildScriptModel" }.configureEach {
    dependsOn(ensureLadybirdSource)
    dependsOn(buildLagomTools)
}

android {
    namespace = "dev.flutterbird.ladybird"
    compileSdk = 35
    ndkVersion = "29.0.13599879"

    defaultConfig {
        minSdk = 30
        externalNativeBuild {
            cmake {
                cppFlags += "-std=c++2b -frtti -fexceptions -D__ANDROID_API__=30 -D__GCC_DESTRUCTIVE_SIZE=64 -Wno-invalid-constexpr"
                arguments += listOf(
                    "-DLagomTools_DIR=$buildDir/host-tools/share/LagomTools",
                    "-DANDROID_STL=c++_shared",
                    "-DLADYBIRD_CACHE_DIR=$cacheDir",
                    "-DVCPKG_ROOT=$sourceDir/Build/vcpkg",
                    "-DVCPKG_TARGET_ANDROID=ON"
                )
            }
        }
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    externalNativeBuild {
        cmake {
            path("CMakeLists.txt")
            version = "3.25.0+"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
