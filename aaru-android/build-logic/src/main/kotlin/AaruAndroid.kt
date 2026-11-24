import com.android.build.api.dsl.CommonExtension
import com.android.build.api.dsl.Lint
import org.gradle.api.JavaVersion

/** The SDK levels every Android module shares. */
object AaruSdk {
    const val COMPILE = 37
    const val COMPILE_MINOR = 2
    const val TARGET = 37
    const val MIN = 28
}

/** What an application and a library configure the same way. */
fun CommonExtension.aaruDefaults() {
    compileSdk {
        version = release(AaruSdk.COMPILE) { minorApiLevel = AaruSdk.COMPILE_MINOR }
    }
    defaultConfig.minSdk = AaruSdk.MIN
    compileOptions.sourceCompatibility = JavaVersion.VERSION_17
    compileOptions.targetCompatibility = JavaVersion.VERSION_17
    lint.aaruDefaults()
}

/** Android Lint as a gate: a warning fails the build, and nothing is baselined away. */
fun Lint.aaruDefaults() {
    warningsAsErrors = true
    abortOnError = true
    checkReleaseBuilds = true
    // New library versions are a decision, not a defect: versions change in libs.versions.toml.
    disable += setOf("GradleDependency", "NewerVersionAvailable", "AndroidGradlePluginVersion")
    // No text in code: every string a person reads is a resource.
    error += setOf("HardcodedText", "SetTextI18n")
}
