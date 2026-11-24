plugins {
    id("aaru.android.application")
    id("aaru.android.compose")
    id("aaru.hilt")
}

android {
    namespace = "app.aaru"

    defaultConfig {
        applicationId = "com.fernandocorreia.aaru"
        versionCode = 1
        versionName = "0.1.0"
    }

    lint {
        // The launcher icon is the Apple app's square art for now. An adaptive icon cut from
        // the owl master (docs/brand) replaces it in AND-002; remove this line with it.
        disable += "IconLauncherShape"
    }

    buildFeatures {
        buildConfig = true
    }

    // One backend, as the Apple app: dev talks to a server on this machine, beta and prod to
    // production. Beta installs beside prod under its own id, like TestFlight's build.
    flavorDimensions += "channel"
    productFlavors {
        create("dev") {
            dimension = "channel"
            applicationIdSuffix = ".beta"
            buildConfigField("String", "API_URL", "\"http://10.0.2.2:8080/\"")
        }
        create("beta") {
            dimension = "channel"
            applicationIdSuffix = ".beta"
            buildConfigField("String", "API_URL", "\"https://api.aaruapp.com/\"")
        }
        create("prod") {
            dimension = "channel"
            buildConfigField("String", "API_URL", "\"https://api.aaruapp.com/\"")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

dependencies {
    implementation(project(":core:api"))
    implementation(project(":core:design"))

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.compose.material3.adaptive.navigation.suite)
    implementation(libs.kotlinx.coroutines.android)

    testImplementation(libs.junit)
}
