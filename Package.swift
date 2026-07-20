// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Assistant",
    platforms: [
        // 14.2 нужен ради Core Audio process taps и стабильного ScreenCaptureKit-аудио
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Assistant", targets: ["Assistant"])
    ],
    targets: [
        // Core ML энкодер whisper. Отдельный таргет, потому что автогенерированный
        // Core ML код требует ARC, а WhisperCore собирается с -fno-objc-arc.
        .target(
            name: "WhisperCoreML",
            path: "Vendor/whisper-coreml",
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags(["-Wno-shorten-64-to-32", "-O3", "-DNDEBUG"])
            ],
            linkerSettings: [
                .linkedFramework("CoreML"),
                .linkedFramework("Foundation")
            ]
        ),
        // Нативное ядро распознавания: ggml + whisper, Accelerate и Metal.
        // Собирается из исходников, без cmake и внешних пакетов.
        .target(
            name: "WhisperCore",
            dependencies: ["WhisperCoreML"],
            path: "Vendor/whisper",
            exclude: ["LICENSE"],
            sources: [
                "ggml/src/ggml.c",
                "src/whisper.cpp",
                "ggml/src/ggml-aarch64.c",
                "ggml/src/ggml-alloc.c",
                "ggml/src/ggml-backend.cpp",
                "ggml/src/ggml-cpu.c",
                "ggml/src/ggml-quants.c",
                "ggml/src/ggml-metal.m"
            ],
            resources: [.process("ggml/src/ggml-metal.metal")],
            publicHeadersPath: "spm-headers",
            cSettings: [
                .unsafeFlags(["-Wno-shorten-64-to-32", "-O3", "-DNDEBUG"]),
                .define("GGML_USE_ACCELERATE"),
                .unsafeFlags(["-fno-objc-arc"]),
                .define("GGML_USE_METAL"),
                // Core ML энкодер + мягкий откат на Metal, если модель не скачана
                .define("WHISPER_USE_COREML"),
                .define("WHISPER_COREML_ALLOW_FALLBACK")
            ],
            linkerSettings: [
                .linkedFramework("Accelerate")
            ]
        ),
        .executableTarget(
            name: "Assistant",
            dependencies: ["WhisperCore"],
            path: "Sources/Assistant",
            swiftSettings: [
                // пока держим v5-режим, миграцию на строгий concurrency v6 делаем отдельно
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "AssistantTests",
            dependencies: ["Assistant"],
            path: "Tests/AssistantTests",
            resources: [.process("Fixtures")],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ],
    cxxLanguageStandard: .cxx11
)
