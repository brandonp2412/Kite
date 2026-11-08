import org.gradle.api.DefaultTask
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.file.FileSystemOperations
import org.gradle.api.tasks.InputDirectory
import org.gradle.api.tasks.OutputDirectory
import org.gradle.api.tasks.TaskAction
import javax.inject.Inject

plugins {
    alias(libs.plugins.androidApplication)
}

abstract class SyncNativeLibraries : DefaultTask() {
    @get:Inject
    abstract val fileSystemOperations: FileSystemOperations

    @get:InputDirectory
    abstract val inputDirectory: DirectoryProperty

    @get:OutputDirectory
    abstract val outputDirectory: DirectoryProperty

    @TaskAction
    fun sync() {
        fileSystemOperations.sync {
            from(inputDirectory)
            into(outputDirectory)
        }
    }
}

val supportedAndroidAbis = listOf("arm64-v8a", "armeabi", "armeabi-v7a", "x86", "x86_64")
val selectedAndroidAbis = providers.gradleProperty("androidAbi")
    .orElse(providers.gradleProperty("android.injected.build.abi"))
    .orNull
    ?.split(',')
    ?.map(String::trim)
    ?.filter(String::isNotEmpty)
    ?.distinct()
    ?.takeIf(List<String>::isNotEmpty)
val unknownAndroidAbis = selectedAndroidAbis.orEmpty() - supportedAndroidAbis
require(unknownAndroidAbis.isEmpty()) {
    "Unsupported Android ABI(s): ${unknownAndroidAbis.joinToString()}. Supported ABIs: ${supportedAndroidAbis.joinToString()}"
}

val kiteKeystorePath = providers.environmentVariable("KITE_RELEASE_KEYSTORE").orNull
val kiteKeystorePassword = providers.environmentVariable("KITE_RELEASE_STORE_PASSWORD").orNull
val kiteKeyAlias = providers.environmentVariable("KITE_RELEASE_KEY_ALIAS").orNull
val kiteKeyPassword = providers.environmentVariable("KITE_RELEASE_KEY_PASSWORD").orNull

// The local default tracks the latest development release; CI supplies its tag through
// -PandroidVersionName. All build types use the same deterministic versionCode formula.
val androidVersionName = providers.gradleProperty("androidVersionName").getOrElse("1.0.96")
require(!providers.gradleProperty("androidVersionCode").isPresent) {
    "Kite derives androidVersionCode from androidVersionName; remove -PandroidVersionCode."
}
val versionParts = Regex("""([1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)""")
    .matchEntire(androidVersionName)
    ?: error("Kite Android version must use major.minor.patch (for example 1.0.76).")
val (majorText, minorText, patchText) = versionParts.destructured
val major = majorText.toInt()
val minor = minorText.toInt()
val patch = patchText.toInt()
require(major in 1..2100 && minor in 0..9 && patch in 0..999) {
    "Kite Android version components out of range (major 1..2100, minor 0..9, patch 0..999)."
}
// Compact pre-store codes: 1.0.94 -> 94; 1.0.95 -> 95;
// 1.1.0 -> 1000; 2.0.0 -> 10000. Never reuse a code within this scheme.
// This is lower than historical GitHub APKs and private Samsung installations:
// updating those installs requires a fresh install and Matrix recovery.
fun kiteVersionCode(major: Int, minor: Int, patch: Int): Int =
    (major - 1) * 10_000 + minor * 1_000 + patch
val androidVersionCode = kiteVersionCode(major, minor, patch)
require(androidVersionCode in 1..2_100_000_000) {
    "Kite Android versionCode exceeds the Google Play limit."
}

tasks.register("printKiteAndroidVersion") {
    group = "help"
    description = "Print the exact Android version name and code for a Kite build"
    val outputLine = "Kite Android: $androidVersionName ($androidVersionCode)"
    doLast { logger.lifecycle(outputLine) }
}

tasks.register("verifyKiteVersionCodes") {
    group = "verification"
    description = "Guard the compact, monotonic Android version-code mapping"
    val mappingChecksPass =
        kiteVersionCode(1, 0, 94) == 94 &&
        kiteVersionCode(1, 0, 95) == 95 &&
        kiteVersionCode(1, 0, 999) == 999 &&
        kiteVersionCode(1, 1, 0) == 1_000 &&
        kiteVersionCode(1, 9, 999) == 9_999 &&
        kiteVersionCode(2, 0, 0) == 10_000
    doLast { check(mappingChecksPass) { "Kite Android version-code mapping changed" } }
}

android {
    namespace = "chat.schildi.revenge"
    compileSdk = 37

    defaultConfig {
        applicationId = "app.kite"
        minSdk = 26
        targetSdk = 37
        versionCode = androidVersionCode
        versionName = androidVersionName
    }
    signingConfigs {
        if (listOf(kiteKeystorePath, kiteKeystorePassword, kiteKeyAlias, kiteKeyPassword).all { it != null }) {
            create("kiteRelease") {
                storeFile = file(requireNotNull(kiteKeystorePath))
                storePassword = kiteKeystorePassword
                keyAlias = kiteKeyAlias
                keyPassword = kiteKeyPassword
            }
        }
    }
    buildTypes {
        debug {
            ndk.abiFilters += selectedAndroidAbis ?: listOf("arm64-v8a")
        }
        release {
            // Release optimization. Configure a private signing key for distribution.
            // F-Droid signs unsigned builds; standalone releases require a private release key.
            signingConfig = signingConfigs.findByName("kiteRelease")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            ndk.abiFilters += selectedAndroidAbis ?: supportedAndroidAbis
        }
        // Optimizations like release, package and signing like debug
        create("PerfDebug") {
            initWith(getByName("release"))
            signingConfig = signingConfigs.getByName("debug")
            matchingFallbacks += listOf("release")
            ndk.abiFilters.clear()
            ndk.abiFilters += selectedAndroidAbis ?: listOf("arm64-v8a")
            // ART runtime punishes debuggable...
            isDebuggable = false
        }
    }
    check(
        defaultConfig.applicationId == "app.kite" &&
            listOf("debug", "release", "PerfDebug").all { buildTypes.getByName(it).applicationIdSuffix.isNullOrEmpty() }
    ) { "Every Kite Android variant must use app.kite without an application ID suffix." }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }
}

dependencies {
    implementation(projects.composeApp)
    implementation(projects.res)
    implementation(libs.androidx.core.ktx)
    coreLibraryDesugaring(libs.desugar.jdk.libs)
}

val matrixRustBindings = project(":matrixRustBindings")
val syncDebugNativeLibraries = tasks.register<SyncNativeLibraries>("syncDebugNativeLibraries") {
    dependsOn(":matrixRustBindings:buildAndroidDebugSdk")
    inputDirectory.set(matrixRustBindings.layout.buildDirectory.dir("generated/android/debug/jniLibs"))
    outputDirectory.set(layout.buildDirectory.dir("generated/jniLibs/debug"))
}
val syncReleaseNativeLibraries = tasks.register<SyncNativeLibraries>("syncReleaseNativeLibraries") {
    dependsOn(":matrixRustBindings:buildAndroidReleaseSdk")
    inputDirectory.set(matrixRustBindings.layout.buildDirectory.dir("generated/android/release/jniLibs"))
    outputDirectory.set(layout.buildDirectory.dir("generated/jniLibs/release"))
}

androidComponents {
    onVariants(selector().withBuildType("debug")) { variant ->
        variant.outputs.forEach { output ->
            output.versionCode.set(androidVersionCode)
            output.versionName.set("debug-$androidVersionName")
        }
        variant.sources.jniLibs?.addGeneratedSourceDirectory(syncDebugNativeLibraries, SyncNativeLibraries::outputDirectory)
    }
    onVariants(selector().withBuildType("release")) { variant ->
        variant.sources.jniLibs?.addGeneratedSourceDirectory(syncReleaseNativeLibraries, SyncNativeLibraries::outputDirectory)
    }
    onVariants(selector().withBuildType("PerfDebug")) { variant ->
        variant.outputs.forEach { output ->
            output.versionCode.set(androidVersionCode)
            output.versionName.set("perfdebug-$androidVersionName")
        }
        variant.sources.jniLibs?.addGeneratedSourceDirectory(syncReleaseNativeLibraries, SyncNativeLibraries::outputDirectory)
    }
}

// Preserve Kite's intentionally compact Android long-press menus across release builds.
// This also catches releases made from a checkout that accidentally omitted the UI remap.
val verifyKiteLongPressMenu = tasks.register("verifyKiteLongPressMenu") {
    group = "verification"
    description = "Reject releases that regress Kite's message and inbox long-press actions"
    val messageMenu = rootProject.file(
        "composeApp/src/jvmMain/kotlin/chat/schildi/revenge/compose/destination/conversation/event/EventRowContextMenu.kt"
    )
    val inboxMenu = rootProject.file(
        "composeApp/src/jvmMain/kotlin/chat/schildi/revenge/compose/destination/inbox/InboxRowContextMenu.kt"
    )
    val timelineVisibility = rootProject.file(
        "composeApp/src/jvmMain/kotlin/chat/schildi/revenge/model/conversation/KiteTimelineVisibility.kt"
    )
    val timelineViewModel = rootProject.file(
        "composeApp/src/jvmMain/kotlin/chat/schildi/revenge/model/conversation/ConversationViewModel.kt"
    )
    val conversationScreen = rootProject.file(
        "composeApp/src/jvmMain/kotlin/chat/schildi/revenge/compose/destination/conversation/ConversationScreen.kt"
    )
    inputs.files(messageMenu, inboxMenu, timelineVisibility, timelineViewModel, conversationScreen)
    doLast {
        val messageSource = messageMenu.readText()
        check(
            listOf(
                "ContextMenuActionRowEntry(",
                "Action.Event.CopyContent",
                "Res.string.action_select_message",
                "Action.Event.Redact",
            ).all(messageSource::contains) &&
                !messageSource.contains("ContextMenuSubmenuEntry") &&
                !messageSource.contains("action_show_more")
        ) {
            "Kite message long-press contract regressed: preserve quick reactions, Copy, Select, Delete, without Show more."
        }
        val inboxSource = inboxMenu.readText()
        check(
            inboxSource.contains("Action.Room.MarkLowPriority") &&
                inboxSource.contains("Res.string.action_context_low_priority_toggle") &&
                !inboxSource.contains("ContextMenuSubmenuEntry") &&
                !inboxSource.contains("action_show_more") &&
                !inboxSource.contains("Action.Room.MarkRoomRead") &&
                !inboxSource.contains("Action.Room.MarkRoomUnread") &&
                !inboxSource.contains("Action.Room.MarkInviteSeen")
        ) {
            "Kite inbox long-press contract regressed: show Low priority directly, with no read/unread entries."
        }
        check(
            timelineVisibility.readText().contains("virtual !is VirtualTimelineItem.DayDivider") &&
                timelineViewModel.readText().contains("it.isKiteVisibleConversationItem()") &&
                !timelineViewModel.readText().contains("search_date_") &&
                !conversationScreen.readText().contains("FloatingDateHeader(listState, renderedItems)")
        ) {
            "Kite messages-only timeline regressed: do not render state events or date separators."
        }
    }
}
tasks.matching { it.name == "preReleaseBuild" || it.name == "prePerfDebugBuild" }
    .configureEach { dependsOn(verifyKiteLongPressMenu) }
