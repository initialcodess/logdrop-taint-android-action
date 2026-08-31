// LogDrop Taint as a Gradle task, so a scan runs where the build already runs.
//
// This is Android's counterpart to the iOS analyzer's Xcode run-script phase: the
// developer sees a leak while they are still writing it, rather than on a pull request
// an hour later.
//
// Add to the app module's build.gradle.kts:
//
//     apply(from = "logdrop.gradle.kts")
//
// then `./gradlew logdropTaint`.

val logdropVersion = "v0.8.1"
val logdropDir = layout.buildDirectory.dir("logdrop").get().asFile

tasks.register("logdropInstall") {
    description = "Download and verify the LogDrop Taint analyzer."
    group = "verification"
    outputs.file(File(logdropDir, "logdrop-taint-android-$logdropVersion.jar"))
    doLast {
        logdropDir.mkdirs()
        val script = File(logdropDir, "install.sh")
        script.writeText(
            java.net.URI(
                "https://raw.githubusercontent.com/initialcodess/logdrop-taint-android-action/" +
                    "$logdropVersion/examples/install-logdrop-taint.sh"
            ).toURL().readText()
        )
        providers.exec {
            commandLine("bash", script.absolutePath)
            environment("LOGDROP_VERSION", logdropVersion)
            environment("LOGDROP_DIR", logdropDir.absolutePath)
        }.standardOutput.asText.get().let(::println)
    }
}

tasks.register<JavaExec>("logdropTaint") {
    description = "Scan this module's Kotlin source for data-flow leaks."
    group = "verification"
    dependsOn("logdropInstall")
    classpath = files(File(logdropDir, "logdrop-taint-android-$logdropVersion.jar"))
    mainClass.set("io.initialcode.logdrop.taint.EntryKt")
    args = listOf(
        "src/main",
        "--sarif", File(logdropDir, "logdrop-taint.sarif").absolutePath,
        "--repo-root", rootProject.projectDir.absolutePath,
        "--verbose",
    )
    // NO --fail-on-findings here on purpose. On a developer's machine this is a
    // warning layer; the gate belongs in CI, where it blocks the merge. A scan that
    // broke the build every time somebody typed a half-finished line would be turned
    // off within a day.
    isIgnoreExitValue = true
}
