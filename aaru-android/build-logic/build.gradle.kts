plugins {
    `kotlin-dsl`
}

dependencies {
    implementation(libs.gradle.android)
    implementation(libs.gradle.kotlin)
    implementation(libs.gradle.compose)
    implementation(libs.gradle.serialization)
    implementation(libs.gradle.spotless)
    implementation(libs.gradle.detekt)
    implementation(libs.gradle.ksp)
    implementation(libs.gradle.hilt)
    implementation(libs.gradle.openapi)
}
