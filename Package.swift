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
        .executableTarget(
            name: "Assistant",
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
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
