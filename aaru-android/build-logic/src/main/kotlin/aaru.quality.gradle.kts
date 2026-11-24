// Format (ktlint through Spotless) and static analysis (detekt), the same for
// every module. Generated sources are checked for staleness, never for style.
import io.gitlab.arturbosch.detekt.Detekt

plugins {
    id("com.diffplug.spotless")
    id("io.gitlab.arturbosch.detekt")
}

val libs = extensions.getByType<VersionCatalogsExtension>().named("libs")

spotless {
    kotlin {
        target("src/**/*.kt")
        targetExclude("src/generated/**", "**/*.gen.kt")
        ktlint(libs.findVersion("ktlint").get().requiredVersion)
    }
    kotlinGradle {
        target("*.gradle.kts")
        ktlint(libs.findVersion("ktlint").get().requiredVersion)
    }
}

detekt {
    buildUponDefaultConfig = true
    allRules = false
    parallel = true
    config.setFrom(rootProject.file("config/detekt.yml"))
    source.setFrom("src/main/kotlin", "src/test/kotlin", "src/androidTest/kotlin")
}

dependencies {
    "detektPlugins"(libs.findLibrary("detekt-compose-rules").get())
}

tasks.withType<Detekt>().configureEach {
    jvmTarget = "17"
    exclude("**/generated/**", "**/*.gen.kt")
}
