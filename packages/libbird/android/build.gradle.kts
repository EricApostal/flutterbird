group = "dev.flutterbird.ladybird"
version = "1.0-SNAPSHOT"

buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:9.1.0")
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

val packageBuildDir = layout.buildDirectory.get().asFile
val cacheDir = System.getenv("LADYBIRD_CACHE_DIR") ?: "$packageBuildDir/caches"
val sourceDir = layout.projectDirectory.dir("../third_party/ladybird").asFile.absolutePath

val ensureLadybirdSource = tasks.register<Exec>("ensureLadybirdSource") {
    workingDir = layout.projectDirectory.asFile
    commandLine = listOf("bash", "../tool/ensure_ladybird_source.sh")
}

val buildLagomTools = tasks.register<Exec>("buildLagomTools") {
    dependsOn(ensureLadybirdSource)
    workingDir = layout.projectDirectory.asFile
    commandLine = listOf("bash", "./BuildLagomTools.sh")
    environment = mapOf(
        "BUILD_DIR" to packageBuildDir.absolutePath,
        "CACHE_DIR" to cacheDir,
        "PATH" to System.getenv("PATH")!!
    )
}

val packageLadybirdAssets = tasks.register<Zip>("packageLadybirdAssets") {
    dependsOn(ensureLadybirdSource)
    from("$sourceDir/Base/res")
    archiveFileName.set("ladybird-assets.zip")
    destinationDirectory.set(layout.buildDirectory.dir("generated/ladybirdAssets"))
}

tasks.matching { it.name == "preBuild" }.configureEach {
    dependsOn(buildLagomTools)
    dependsOn(packageLadybirdAssets)
}

tasks.matching { it.name.startsWith("merge") && it.name.endsWith("Assets") }.configureEach {
    dependsOn(packageLadybirdAssets)
}


android {
    namespace = "dev.flutterbird.ladybird"
    compileSdk = 35
    ndkVersion = "29.0.13599879"

    defaultConfig {
        minSdk = 30
        externalNativeBuild {
            cmake {
                cppFlags += "-std=c++23"
                arguments +=
                        listOf(
                                "-DANDROID_STL=c++_shared",
                                "-DLADYBIRD_CACHE_DIR=$cacheDir",
                                "-DVCPKG_ROOT=$sourceDir/Build/vcpkg",
                                "-DVCPKG_TARGET_ANDROID=ON"
                        )
                /*
                This is arguably a hack, and is questionable architecture overall. `ladybird` is fine because
                it's linked, but this is "true", unix-like multiprocess, whereas android wants executables you
                plan on running to be defined at startup in the manifest. For now I do like this because it means
                that android processes run the exact same as linux ones, but it exposes us to the possibility
                of android stepping in and doing whatever it wants, since this is sort of undefined behavior.
                Maybe we're only allowed on efficency cores? Maybe android just decides to kill the process?
                Who knows, you aren't really supposed to do this.

                Now, there are advantages, assuming that android doesn't try to kill the processes at will.
                1. No pooling processes like chromium. We don't need to spawn 12 or so processes on boot
                2. Better security, because we never have to have tabs share processes
                3. Implicity aligned with the desktop implementations
                4. 

                 */
                targets +=
                        listOf(
                        "ladybird_plugin",
                        "engine",
                                "ladybird",
                                "Compositor",
                                "ImageDecoder",
                                "RequestServer",
                                "WebContent",
                                "WebWorker"
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

    sourceSets {
        getByName("main") {
            assets.srcDir(layout.buildDirectory.dir("generated/ladybirdAssets"))
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
            keepDebugSymbols.add("**/libWebContent.so")
        }
    }
}
