plugins {
    id("com.android.application")
}
android {
    namespace = "nz.presley.kite.iconshowcase"
    compileSdk = 36
    defaultConfig {
        applicationId = "nz.presley.kite.iconshowcase"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }
    flavorDimensions += "icon"
    productFlavors {
        create("icon01") {
            dimension = "icon"
            applicationId = "nz.presley.kite.icon01"
            versionNameSuffix = "-icon01"
            resValue("string", "app_name", "Kite Icon 01")
        }
        create("icon02") {
            dimension = "icon"
            applicationId = "nz.presley.kite.icon02"
            versionNameSuffix = "-icon02"
            resValue("string", "app_name", "Kite Icon 02")
        }
        create("icon03") {
            dimension = "icon"
            applicationId = "nz.presley.kite.icon03"
            versionNameSuffix = "-icon03"
            resValue("string", "app_name", "Kite Icon 03")
        }
        create("icon04") {
            dimension = "icon"
            applicationId = "nz.presley.kite.icon04"
            versionNameSuffix = "-icon04"
            resValue("string", "app_name", "Kite Icon 04")
        }
        create("icon05") {
            dimension = "icon"
            applicationId = "nz.presley.kite.icon05"
            versionNameSuffix = "-icon05"
            resValue("string", "app_name", "Kite Icon 05")
        }
        create("icon06") {
            dimension = "icon"
            applicationId = "nz.presley.kite.icon06"
            versionNameSuffix = "-icon06"
            resValue("string", "app_name", "Kite Icon 06")
        }
        create("icon07") {
            dimension = "icon"
            applicationId = "nz.presley.kite.icon07"
            versionNameSuffix = "-icon07"
            resValue("string", "app_name", "Kite Icon 07")
        }
        create("icon08") {
            dimension = "icon"
            applicationId = "nz.presley.kite.icon08"
            versionNameSuffix = "-icon08"
            resValue("string", "app_name", "Kite Icon 08")
        }
        create("icon09") {
            dimension = "icon"
            applicationId = "nz.presley.kite.icon09"
            versionNameSuffix = "-icon09"
            resValue("string", "app_name", "Kite Icon 09")
        }
        create("icon10") {
            dimension = "icon"
            applicationId = "nz.presley.kite.icon10"
            versionNameSuffix = "-icon10"
            resValue("string", "app_name", "Kite Icon 10")
        }
    }
    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
        }
    }
    buildFeatures {
        buildConfig = false
        resValues = true
    }
}
