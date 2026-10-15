import org.gradle.api.DefaultTask
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.file.FileSystemOperations
import org.gradle.api.tasks.InputDirectory
import org.gradle.api.tasks.OutputDirectory
import org.gradle.api.tasks.TaskAction
import java.time.ZoneOffset
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
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

val calVer = ZonedDateTime.now(ZoneOffset.UTC)
    .format(DateTimeFormatter.ofPattern("yy.MM.dd"))
val androidVersionNameOverride = providers.gradleProperty("androidVersionName")
val androidVersionCodeOverride = providers.gradleProperty("androidVersionCode").map(String::toInt)
val androidVersionName = androidVersionNameOverride.getOrElse(calVer)
val androidVersionCode = androidVersionCodeOverride.getOrElse("${calVer.replace(".", "")}00".toInt())

android {
    namespace = "chat.schildi.revenge"
    compileSdk = 37

    defaultConfig {
        applicationId = "app.kite.revenge.debug"
        minSdk = 26
        targetSdk = 37
        versionCode = androidVersionCode
        versionName = androidVersionName
    }
    buildTypes {
        debug {
            ndk.abiFilters += selectedAndroidAbis ?: listOf("arm64-v8a")
        }
        release {
            // Release optimization with the same package ID and signing identity as the Samsung installation.
            signingConfig = signingConfigs.getByName("debug")
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
        defaultConfig.applicationId == "app.kite.revenge.debug" &&
            listOf("debug", "release", "PerfDebug").all { buildTypes.getByName(it).applicationIdSuffix.isNullOrEmpty() }
    ) { "Every Kite Android variant must use app.kite.revenge.debug without an application ID suffix." }
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
            output.versionCode.set(androidVersionCodeOverride.orElse(1))
            output.versionName.set(androidVersionNameOverride.orElse("debug-$calVer"))
        }
        variant.sources.jniLibs?.addGeneratedSourceDirectory(syncDebugNativeLibraries, SyncNativeLibraries::outputDirectory)
    }
    onVariants(selector().withBuildType("release")) { variant ->
        variant.sources.jniLibs?.addGeneratedSourceDirectory(syncReleaseNativeLibraries, SyncNativeLibraries::outputDirectory)
    }
    onVariants(selector().withBuildType("PerfDebug")) { variant ->
        variant.outputs.forEach { output ->
            output.versionCode.set(androidVersionCodeOverride.orElse(1))
            output.versionName.set(androidVersionNameOverride.orElse("perfdebug-$calVer"))
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
