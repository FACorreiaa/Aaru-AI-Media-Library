// Compose for an Android module that already applied the application or library convention.
plugins {
    id("org.jetbrains.kotlin.plugin.compose")
}

val libs = extensions.getByType<VersionCatalogsExtension>().named("libs")

extensions.configure<com.android.build.api.dsl.CommonExtension>("android") {
    buildFeatures.compose = true
}

dependencies {
    "implementation"(platform(libs.findLibrary("compose-bom").get()))
    "implementation"(libs.findLibrary("compose-ui").get())
    "implementation"(libs.findLibrary("compose-foundation").get())
    "implementation"(libs.findLibrary("compose-material3").get())
    "implementation"(libs.findLibrary("compose-ui-tooling-preview").get())
    "debugImplementation"(libs.findLibrary("compose-ui-tooling").get())
}
