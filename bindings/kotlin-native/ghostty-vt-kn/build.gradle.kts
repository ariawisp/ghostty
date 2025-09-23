plugins {
    alias(libs.plugins.kotlin.multiplatform)
}

group = "org.ghostty"
version = "0.1-SNAPSHOT"

kotlin {
    macosArm64()
    sourceSets {
        val commonMain by getting
        val macosArm64Main by getting
        val commonTest by getting {
            dependencies {
                implementation(kotlin("test"))
                implementation(libs.kotest.assertions.core)
            }
        }
        val macosArm64Test by getting
    }
    macosArm64() {
        // Use paths relative to this module directory at build time.
        val includeDirRel = "../../../zig-out/include"
        val libDirRel = "../../../zig-out/lib"

        compilations.getByName("main").cinterops.create("ghostty_vt") {
            defFile(project.file("src/nativeInterop/cinterop/ghostty_vt.def"))
            includeDirs(project.file(includeDirRel))
        }
        binaries {
            all {
                linkerOpts(
                    "-L$libDirRel",
                    "-lghostty_vt_c",
                    "-lsimdutf",
                    "-lhighway",
                    "-lutfcpp",
                    "-lc++",
                    "-macosx_version_min",
                    "26.0",
                )
            }
        }
    }
}


// Notes:
// - Run `zig build` in the Ghostty repo root before building this module.
// - The cinterop def links against `zig-out/lib/libghostty_vt_c.a` and includes from `zig-out/include`.
