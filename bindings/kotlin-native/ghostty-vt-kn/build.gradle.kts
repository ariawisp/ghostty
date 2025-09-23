plugins {
    kotlin("multiplatform") version "2.0.21"
}

kotlin {
    macosArm64()
    sourceSets {
        val commonMain by getting
        val macosArm64Main by getting
    }
    macosArm64() {
        compilations.getByName("main").cinterops.create("ghostty_vt") {
            defFile(project.file("src/nativeInterop/cinterop/ghostty_vt.def"))
        }
    }
}

// Notes:
// - Run `zig build` in the Ghostty repo root before building this module.
// - The cinterop def links against `zig-out/lib/libghostty_vt_c.a` and includes from `zig-out/include`.

