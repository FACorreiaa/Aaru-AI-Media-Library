import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("aaru.quality")
}

android {
    aaruDefaults()
    defaultConfig.targetSdk = AaruSdk.TARGET
    lint.checkDependencies = true
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
        allWarningsAsErrors.set(true)
    }
}
