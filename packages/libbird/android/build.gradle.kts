group = "dev.flutterbird.ladybird"
version = "1.0-SNAPSHOT"

var buildDir = layout.buildDirectory.get()
var cacheDir = System.getenv("LADYBIRD_CACHE_DIR") ?: "$buildDir/caches"
var sourceDir = layout.projectDirectory.dir("../third_party/ladybird").toString()

data class Sdl3JavaInputs(val jar: File?, val sourceDirs: List<File>)

fun Project.resolveSdl3JavaInputs(sourceDir: String): Sdl3JavaInputs {
    val jar =
            fileTree("$sourceDir/Build/vcpkg/packages") {
                include("**/SDL3.jar")
                include("**/SDL3-*.jar")
                exclude("**/*-sources.jar")
            }
                    .files
                    .minByOrNull { it.path }

    val sourceDirs =
            if (jar == null) {
                fileTree("$sourceDir/Build/vcpkg/buildtrees/sdl3") {
                    include("**/android-project/app/src/main/java/**/*.java")
                }
                        .files
                        .mapNotNull { file ->
                            var current: File? = file
                            while (current != null && current.name != "java") {
                                current = current.parentFile
                            }
                            current
                        }
                        .distinct()
                        .sortedBy { it.path }
            } else {
                emptyList()
            }

    return Sdl3JavaInputs(jar = jar, sourceDirs = sourceDirs)
}

fun verifySdl3JavaInputs(inputs: Sdl3JavaInputs) {
    check(inputs.jar != null || inputs.sourceDirs.isNotEmpty()) {
        "Unable to locate SDL Android Java sources. Expected either packaged SDL3 Java artifacts or unpacked SDL buildtree sources under Build/vcpkg."
    }
}


var hostToolsTask =
        tasks.register<Exec>("buildLagomTools") {
            commandLine = listOf("./BuildLagomTools.sh")
            environment =
                    mapOf(
                            "BUILD_DIR" to buildDir,
                            "CACHE_DIR" to cacheDir,
                            "PATH" to System.getenv("PATH")!!
                    )
        }

tasks.named("preBuild").dependsOn(hostToolsTask)

tasks.named("prepareKotlinBuildScriptModel").dependsOn(hostToolsTask)

// unsure sounds problematic
// kotlin { compilerOptions { jvmTarget = JvmTarget.fromTarget("11") } }

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
}
