group = "com.example.ladybird"
version = "1.0-SNAPSHOT"

var buildDir = layout.buildDirectory.get()
var cacheDir = System.getenv("LADYBIRD_CACHE_DIR") ?: "$buildDir/caches"
var sourceDir = layout.projectDirectory.dir("../third_party/ladybird").toString()
var ladybirdAndroidDir = layout.projectDirectory.dir("../third_party/ladybird/UI/Android").toString()

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

val buildLagomTools = tasks.register<Exec>("buildLagomTools") {
    workingDir = file(ladybirdAndroidDir)
    commandLine = listOf("./BuildLagomTools.sh")
    environment = mapOf(
        "BUILD_DIR" to buildDir,
        "CACHE_DIR" to cacheDir,
        "PATH" to System.getenv("PATH")!!
    )

    // Make this task incremental so Gradle does not rebuild Lagom tools on
    // every Android build when inputs are unchanged.
    val ladybirdSource = file(sourceDir)
    val lagomInstallDir = file("$buildDir/lagom-tools-install")
    inputs.file(file("$ladybirdAndroidDir/BuildLagomTools.sh"))
    inputs.file(file("$sourceDir/CMakeLists.txt"))
    inputs.file(file("$sourceDir/Meta/Lagom/CMakeLists.txt"))
    inputs.file(file("$sourceDir/vcpkg.json"))
    inputs.file(file("$sourceDir/vcpkg-configuration.json"))
    inputs.dir(file("$sourceDir/Meta/Lagom"))
    inputs.dir(file("$sourceDir/AK"))
    inputs.dir(file("$sourceDir/Libraries"))
    // Ignore generated/build artifacts under Ladybird so timestamp churn there
    // does not invalidate this task.
    inputs.files(fileTree(ladybirdSource) {
        include("**/*.cmake", "**/CMakeLists.txt", "**/*.h", "**/*.hpp", "**/*.cpp", "**/*.c", "**/*.rs", "**/*.json", "**/*.toml", "**/*.sh")
        exclude("Build/**", "UI/Android/.cxx/**", "UI/Android/build/**", ".git/**")
    })
    outputs.dir(lagomInstallDir)
}
tasks.named("preBuild") {
    dependsOn(buildLagomTools)
}
tasks.matching { it.name == "prepareKotlinBuildScriptModel" }.configureEach {
    dependsOn(buildLagomTools)
}

android {
    namespace = "com.example.ladybird"
    compileSdk = 35
    ndkVersion = "29.0.13599879"

    defaultConfig {
        minSdk = 30
        externalNativeBuild {
            cmake {
                cppFlags += "-std=c++2b -frtti -fexceptions -D__GCC_DESTRUCTIVE_SIZE=64 -Wno-invalid-constexpr"
                arguments += listOf(
                    "-DLagomTools_DIR=$buildDir/lagom-tools-install/share/LagomTools",
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
