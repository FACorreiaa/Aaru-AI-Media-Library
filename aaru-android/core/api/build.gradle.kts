plugins {
    id("aaru.kotlin.jvm")
    id("aaru.serialization")
    id("aaru.openapi")
}

// The /v1 client, generated from the server's openapi.yaml and committed, as
// aaru-api is for the Apple apps. `./gradlew :core:api:generateApi` rewrites
// it; CI fails when it is stale.
val spec = rootProject.file("../aaru-server/Sources/AppAPI/openapi.yaml")
val generatedDir = layout.projectDirectory.dir("src/generated")

openApiGenerate {
    generatorName.set("kotlin")
    library.set("jvm-retrofit2")
    inputSpec.set(spec.absolutePath)
    outputDir.set(layout.buildDirectory.dir("openapi").map { it.asFile.absolutePath })
    packageName.set("app.aaru.api")
    apiPackage.set("app.aaru.api.generated")
    modelPackage.set("app.aaru.api.generated.models")
    configOptions.set(
        mapOf(
            "serializationLibrary" to "kotlinx_serialization",
            "useCoroutines" to "true",
            "enumPropertyNaming" to "camelCase",
            "omitGradleWrapper" to "true",
            "explicitApi" to "true",
            "sourceFolder" to "kotlin"
        )
    )
    // `for` and `in` are Kotlin keywords.
    parameterNameMappings.set(mapOf("for" to "purpose", "in" to "within"))
    globalProperties.set(
        mapOf(
            "apis" to "",
            "models" to "",
            "apiDocs" to "false",
            "modelDocs" to "false",
            "apiTests" to "false",
            "modelTests" to "false",
            "supportingFiles" to "CollectionFormats.kt"
        )
    )
}

val generateApi by tasks.registering(Sync::class) {
    group = "aaru"
    description = "Regenerates the /v1 client from openapi.yaml into src/generated."
    dependsOn(tasks.named("openApiGenerate"))
    from(layout.buildDirectory.dir("openapi/kotlin"))
    filter(MendGeneratedApi())
    into(generatedDir.dir("kotlin"))
}

// Committed output: compiling reads it, and never regenerates it by itself.
tasks.matching { it.name != generateApi.name && it.name != "openApiGenerate" }.configureEach {
    mustRunAfter(generateApi)
}

sourceSets.main {
    kotlin.srcDir(generatedDir.dir("kotlin"))
}

kotlin {
    explicitApi()
    compilerOptions {
        // Generated code is not ours to tidy.
        allWarningsAsErrors.set(false)
    }
}

dependencies {
    api(libs.okhttp)
    api(libs.retrofit)
    api(libs.kotlinx.serialization.json)
    api(libs.kotlinx.coroutines.core)
    implementation(libs.retrofit.serialization)
    implementation(libs.okhttp.sse)

    testImplementation(libs.junit)
    testImplementation(libs.okhttp.mockwebserver)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.turbine)
}
