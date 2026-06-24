import com.android.build.api.dsl.LibraryExtension
import java.io.ByteArrayOutputStream

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
val generatedSdl3JavaDir = layout.buildDirectory.dir("generated/sdl3Java").get().asFile.absolutePath
val lagomToolsInstallDir = layout.buildDirectory.dir("lagom-tools-install")
val ladybirdVersionFile = layout.projectDirectory.file("../third_party/ladybird.version").asFile
val ensureLadybirdSourceStamp = layout.buildDirectory.file("generated/ensureLadybirdSource.stamp")
val lagomToolsStamp = layout.buildDirectory.file("generated/lagom-tools.stamp")

data class Sdl3JavaInputs(val jar: File?, val sourceDirs: List<File>)

fun Project.resolveSdl3JavaInputs(sourceDir: String): Sdl3JavaInputs {
    val jar = fileTree("$sourceDir/Build/vcpkg/packages") {
        include("**/SDL3.jar")
        include("**/SDL3-*.jar")
        exclude("**/*-sources.jar")
    }.files.minByOrNull { it.path }

    val sourceDirs = if (jar == null) {
        fileTree("$sourceDir/Build/vcpkg/buildtrees/sdl3") {
            include("**/android-project/app/src/main/java/**/*.java")
        }.files.mapNotNull { file ->
            var current: File? = file
            while (current != null && current.name != "java") {
                current = current.parentFile
            }
            current
        }.distinct().sortedBy { it.path }
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

fun computeLagomToolsFingerprint(
    sourceDir: String,
    cacheDir: String,
    buildScript: File,
    versionFile: File,
): String {
    val ladybirdHead = runCatching {
        ProcessBuilder("git", "rev-parse", "HEAD")
            .directory(File(sourceDir))
            .start()
            .inputStream.bufferedReader().readText().trim()
    }.getOrElse { "unknown" }

    val ladybirdDirty = runCatching {
        ProcessBuilder("git", "status", "--porcelain", "--untracked-files=no")
            .directory(File(sourceDir))
            .start()
            .inputStream.bufferedReader().readText().trim()
    }.getOrElse { "unknown" }

    return buildString {
        appendLine("ladybirdVersionFile=${versionFile.readText().trim()}")
        appendLine("buildScriptMtime=${buildScript.lastModified()}")
        appendLine("buildScriptSize=${buildScript.length()}")
        appendLine("cacheDir=$cacheDir")
        appendLine("ladybirdHead=$ladybirdHead")
        appendLine("ladybirdDirty=$ladybirdDirty")
    }
}

val ensureLadybirdSource = tasks.register<Exec>("ensureLadybirdSource") {
    workingDir = layout.projectDirectory.asFile
    commandLine = listOf("bash", "../tool/ensure_ladybird_source.sh")

    inputs.file(layout.projectDirectory.file("../tool/ensure_ladybird_source.sh"))
    inputs.file(layout.projectDirectory.file("../third_party/ladybird.version"))
    outputs.file(ensureLadybirdSourceStamp)
    outputs.upToDateWhen {
        ensureLadybirdSourceStamp.get().asFile.exists() &&
                layout.projectDirectory.file("../third_party/ladybird/Meta/ladybird.py").asFile.exists()
    }

    doLast {
        val stampFile = ensureLadybirdSourceStamp.get().asFile
        stampFile.parentFile.mkdirs()
        stampFile.writeText(ladybirdVersionFile.readText())
    }
}

val buildLagomTools = tasks.register<Exec>("buildLagomTools") {
    workingDir = layout.projectDirectory.asFile
    commandLine = listOf("bash", "./BuildLagomTools.sh")
    environment = mapOf(
        "BUILD_DIR" to packageBuildDir.absolutePath,
        "CACHE_DIR" to cacheDir,
        "PATH" to System.getenv("PATH")!!
    )

    val buildScriptFile = layout.projectDirectory.file("BuildLagomTools.sh").asFile

    inputs.file(layout.projectDirectory.file("BuildLagomTools.sh"))
    inputs.file(layout.projectDirectory.file("../third_party/ladybird.version"))
    inputs.property("cacheDir", cacheDir)
    outputs.file(lagomToolsStamp)

    outputs.upToDateWhen {
        val installDir = lagomToolsInstallDir.get().asFile
        val stampFile = lagomToolsStamp.get().asFile
        if (!stampFile.exists() || !installDir.resolve("bin").exists()) {
            return@upToDateWhen false
        }

        val currentFingerprint = computeLagomToolsFingerprint(
                sourceDir = sourceDir,
                cacheDir = cacheDir,
                buildScript = buildScriptFile,
                versionFile = ladybirdVersionFile,
        )
        stampFile.readText() == currentFingerprint
    }

    doLast {
        val stampFile = lagomToolsStamp.get().asFile
        stampFile.parentFile.mkdirs()
        stampFile.writeText(
                computeLagomToolsFingerprint(
                        sourceDir = sourceDir,
                        cacheDir = cacheDir,
                        buildScript = buildScriptFile,
                        versionFile = ladybirdVersionFile,
                )
        )
    }
}

val packageLadybirdAssets = tasks.register<Zip>("packageLadybirdAssets") {
    from("$sourceDir/Base/res")
    archiveFileName.set("ladybird-assets.zip")
    destinationDirectory.set(layout.buildDirectory.dir("generated/ladybirdAssets"))
}

fun javaCompileVariantName(taskName: String): String? {
    if (!taskName.startsWith("compile") || !taskName.endsWith("JavaWithJavac")) {
        return null
    }

    val variantName = taskName
            .removePrefix("compile")
            .removeSuffix("JavaWithJavac")

    return variantName.takeIf { it.isNotEmpty() }
}

val prepareSdl3Java = tasks.register("prepareSdl3Java") {
    doLast {
        val inputs = resolveSdl3JavaInputs(sourceDir)
        verifySdl3JavaInputs(inputs)
        if (inputs.sourceDirs.isNotEmpty()) {
            copy {
                from(inputs.sourceDirs)
                into(generatedSdl3JavaDir)
            }
        }
    }
}

val verifySdl3JavaInputsTask = tasks.register("verifySdl3JavaInputs") {
    group = "verification"
    description = "Verifies SDL Android Java inputs exist after externalNativeBuild."

    doLast { verifySdl3JavaInputs(resolveSdl3JavaInputs(sourceDir)) }
}

tasks.matching { it.name == "preBuild" }.configureEach {
    // dependsOn(buildLagomTools)
    dependsOn(packageLadybirdAssets)
}

tasks.matching { it.name.startsWith("merge") && it.name.endsWith("Assets") }.configureEach {
    dependsOn(packageLadybirdAssets)
}

tasks.withType<JavaCompile>().configureEach {
    dependsOn(prepareSdl3Java)

    val variantName = javaCompileVariantName(name) ?: return@configureEach
    dependsOn(tasks.matching {
        it.name == "generateJsonModel$variantName" ||
                it.name == "externalNativeBuild$variantName"
    })
}

tasks.matching { it.name.startsWith("buildCMake") || it.name.startsWith("externalNativeBuild") }.configureEach {
    finalizedBy(verifySdl3JavaInputsTask)
}

configure<LibraryExtension> {
    namespace = "dev.flutterbird.ladybird"
    compileSdk = 35
    ndkVersion = "29.0.13599879"

    defaultConfig {
        minSdk = 30
        consumerProguardFiles("consumer-rules.pro")
        externalNativeBuild {
            cmake {
                cppFlags += "-std=c++23"
                arguments +=
                        listOf(
                                "-DANDROID_STL=c++_shared",
                                "-DLADYBIRD_CACHE_DIR=$cacheDir",
                                "-DVCPKG_ROOT=$sourceDir/Build/vcpkg",
                                "-DVCPKG_TARGET_ANDROID=ON",
                                // "-DCMAKE_SHARED_LINKER_FLAGS=-fuse-ld=mold", 
                                // "-DCMAKE_EXE_LINKER_FLAGS=-fuse-ld=mold"
                        )
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
            assets.directories.add(layout.buildDirectory.dir("generated/ladybirdAssets").get().asFile.absolutePath)
            java.directories.add(generatedSdl3JavaDir)
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
            keepDebugSymbols.add("**/libWebContent.so")
        }
    }
}

dependencies {
    implementation(fileTree("$sourceDir/Build/vcpkg/packages") {
        include("**/SDL3.jar")
        include("**/SDL3-*.jar")
        exclude("**/*-sources.jar")
    })
}
