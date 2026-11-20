import com.android.build.api.dsl.LibraryExtension
import com.android.build.api.variant.LibraryAndroidComponentsExtension
import java.io.ByteArrayOutputStream

group = "dev.flutterbird.ladybird"
version = "1.0-SNAPSHOT"

plugins {
    id("com.android.library")
}

val packageBuildDir = layout.buildDirectory.get().asFile
val cacheDir = System.getenv("LADYBIRD_CACHE_DIR") ?: "$packageBuildDir/caches"
val sourceDir = layout.projectDirectory.dir("../third_party/ladybird").asFile.absolutePath
val generatedSdl3JavaDir = layout.buildDirectory.dir("generated/sdl3Java").get().asFile.absolutePath
val lagomToolsInstallDir = layout.buildDirectory.dir("lagom-tools-install")
val ladybirdHelperJniDir = layout.buildDirectory.dir("generated/ladybirdHelperJniLibs")
val ladybirdVersionFile = layout.projectDirectory.file("../third_party/ladybird.version").asFile
val ensureLadybirdSourceStamp = layout.buildDirectory.file("generated/ensureLadybirdSource.stamp")
val lagomToolsStamp = layout.buildDirectory.file("generated/lagom-tools.stamp")

// Whether the native code (Ladybird and the engine) is compiled here or comes as
// a prebuilt copy built by CI for exactly this source. tool/libbird_native.sh
// decides, from LIBBIRD_NATIVE_MODE or packages/libbird/native_mode.local, so
// that every platform makes the choice the same way (see the README).
val libbirdNativeTool = layout.projectDirectory.file("../tool/libbird_native.sh").asFile
val libbirdNativePlatform = "android-arm64-v8a"
val usePrebuiltNative: Boolean = run {
    val process = ProcessBuilder("bash", libbirdNativeTool.absolutePath, "mode", libbirdNativePlatform)
        .directory(layout.projectDirectory.asFile)
        .redirectError(ProcessBuilder.Redirect.INHERIT)
        .start()
    val output = process.inputStream.bufferedReader().readText().trim()
    if (process.waitFor() != 0) {
        throw GradleException(
            "tool/libbird_native.sh could not decide between a prebuilt and a locally compiled native build."
        )
    }
    output == "prebuilt"
}
logger.lifecycle(
    "libbird: " + if (usePrebuiltNative) "using the prebuilt native code"
    else "compiling the native code locally"
)

// A prebuilt copy is unpacked into the generated directories that a local build
// fills (the helper processes and engine libraries, the assets, the SDL3 Java
// sources), so everything after this point treats the two alike.
val fetchPrebuiltNative = tasks.register<Exec>("fetchPrebuiltNative") {
    group = "libbird"
    description = "Unpacks the prebuilt native copy that matches this source."
    workingDir = layout.projectDirectory.asFile
    commandLine = listOf(
        "bash",
        libbirdNativeTool.absolutePath,
        "fetch",
        libbirdNativePlatform,
        layout.buildDirectory.dir("generated").get().asFile.absolutePath,
    )
    inputs.file(libbirdNativeTool)
    inputs.file(layout.projectDirectory.file("../third_party/ladybird.version"))
    // The script knows whether the right copy is already in place, and does
    // nothing when it is.
    outputs.upToDateWhen { false }
}

if (!usePrebuiltNative) {
    // A local build overwrites what a prebuilt copy put in these directories, so
    // the copy is no longer what the fetch's stamp says. Forget the stamp, so
    // that going back to prebuilt unpacks it again.
    layout.buildDirectory.file("generated/.libbird-native-fingerprint").get().asFile.delete()
}

data class Sdl3JavaInputs(val jar: File?, val sourceDirs: List<File>)

fun Project.resolveSdl3JavaInputs(sourceDir: String): Sdl3JavaInputs {
    val vcpkgRoot = "$sourceDir/Build/vcpkg-release"
    val jar = fileTree("$vcpkgRoot/packages") {
        include("**/SDL3.jar")
        include("**/SDL3-*.jar")
        exclude("**/*-sources.jar")
    }.files.minByOrNull { it.path }

    val sourceDirs = if (jar == null) {
        val javaDirs = fileTree("$vcpkgRoot/buildtrees/sdl3") {
            include("**/android-project/app/src/main/java/**/*.java")
        }.files.mapNotNull { file ->
            var current: File? = file
            while (current != null && current.name != "java") {
                current = current.parentFile
            }
            current
        }.distinct()

        // vcpkg keeps every SDL source tree it has extracted (one per version
        // it has built), and their Java sources are the same files. Only the
        // newest one matches the SDL that was built, and mixing trees both
        // duplicates files and can pair classes from different versions.
        fun sdl3TreeName(javaDir: File) =
            javaDir.path.substringAfter("buildtrees/sdl3/src/").substringBefore('/')

        fun sdl3TreeVersion(javaDir: File): String =
            Regex("""(\d+)\.(\d+)\.(\d+)""").find(sdl3TreeName(javaDir))
                ?.groupValues?.drop(1)
                ?.joinToString("") { it.padStart(6, '0') }
                ?: ""

        val newestTree = javaDirs.maxByOrNull { sdl3TreeVersion(it) + sdl3TreeName(it) }
            ?.let { sdl3TreeName(it) }
        javaDirs.filter { sdl3TreeName(it) == newestTree }.sortedBy { it.path }
    } else {
        emptyList()
    }

    return Sdl3JavaInputs(jar = jar, sourceDirs = sourceDirs)
}

fun verifySdl3JavaInputs(inputs: Sdl3JavaInputs) {
    check(inputs.jar != null || inputs.sourceDirs.isNotEmpty()) {
        "Unable to locate SDL Android Java sources. Expected either packaged SDL3 Java artifacts or unpacked SDL buildtree sources under Build/vcpkg-release."
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
            // sync, not copy: a source file the SDL in use no longer has must
            // not linger from an earlier version.
            sync {
                from(inputs.sourceDirs)
                into(generatedSdl3JavaDir)
                duplicatesStrategy = DuplicatesStrategy.EXCLUDE
            }
        }
    }
}

val verifySdl3JavaInputsTask = tasks.register("verifySdl3JavaInputs") {
    group = "verification"
    description = "Verifies SDL Android Java inputs exist after externalNativeBuild."

    doLast { verifySdl3JavaInputs(resolveSdl3JavaInputs(sourceDir)) }
}

if (usePrebuiltNative) {
    // Nothing is compiled: what the native build would have produced is
    // unpacked first, before anything reads those directories.
    tasks.matching { it.name == "preBuild" }.configureEach {
        dependsOn(fetchPrebuiltNative)
    }

    tasks.matching {
        (it.name.startsWith("merge") &&
                (it.name.endsWith("Assets") || it.name.endsWith("JniLibFolders")))
    }.configureEach {
        dependsOn(fetchPrebuiltNative)
    }

    tasks.withType<JavaCompile>().configureEach {
        dependsOn(fetchPrebuiltNative)
    }
} else {
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
}

configure<LibraryExtension> {
    namespace = "dev.flutterbird.ladybird"
    compileSdk = 35
    ndkVersion = "29.0.13599879"

    defaultConfig {
        minSdk = 30
        consumerProguardFiles("consumer-rules.pro")
        if (!usePrebuiltNative) {
            externalNativeBuild {
                cmake {
                    cppFlags += "-std=c++23"
                    arguments +=
                            listOf(
                                    "-DANDROID_STL=c++_shared",
                                    "-DLADYBIRD_CACHE_DIR=$cacheDir",
                                    "-DLADYBIRD_HELPER_JNI_DIR=${ladybirdHelperJniDir.get().asFile.absolutePath}",
                                    "-DVCPKG_TARGET_ANDROID=ON",
                                    "-DLADYBIRD_VCPKG_TYPE=release",
                                    // "-DCMAKE_SHARED_LINKER_FLAGS=-fuse-ld=mold", 
                                    // "-DCMAKE_EXE_LINKER_FLAGS=-fuse-ld=mold"
                            )
                    targets +=
                            listOf(
                                    "ladybird_plugin",
                                    "engine",
                                    "AudioServer",
                                    "Compositor",
                                    "ImageDecoder",
                                    "MediaServer",
                                    "RequestServer",
                                    "SystemProbe",
                                    "VideoDecoderServer",
                                    "WebContent"
                            )
                }
            }
        }
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    if (!usePrebuiltNative) {
        externalNativeBuild {
            cmake {
                path("CMakeLists.txt")
                version = "3.25.0+"
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
            keepDebugSymbols.add("**/libWebContent.so")
        }
    }
}

// Variant API instead of the `sourceSets` DSL: it works whether the host build
// uses AGP's legacy or new DSL (android.newDsl), which `sourceSets` does not.
extensions.configure<LibraryAndroidComponentsExtension> {
    onVariants { variant ->
        variant.sources.assets?.addStaticSourceDirectory(
            layout.buildDirectory.dir("generated/ladybirdAssets").get().asFile.absolutePath)
        variant.sources.java?.addStaticSourceDirectory(generatedSdl3JavaDir)
        variant.sources.jniLibs?.addStaticSourceDirectory(ladybirdHelperJniDir.get().asFile.absolutePath)
    }
}

dependencies {
    implementation(fileTree("$sourceDir/Build/vcpkg-release/packages") {
        include("**/SDL3.jar")
        include("**/SDL3-*.jar")
        exclude("**/*-sources.jar")
    })

    if (usePrebuiltNative) {
        // There is no vcpkg tree to find SDL's jar in, so a prebuilt copy brings
        // it (when the build it came from used the jar rather than the sources,
        // see tool/libbird_native.sh), unpacked next to the other generated files.
        implementation(
            fileTree(layout.buildDirectory.dir("generated/sdl3Jar").get().asFile) {
                include("*.jar")
            }
        )
    }
}
