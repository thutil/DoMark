// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Domark",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Domark", targets: ["Domark"]),
    ],
    dependencies: [
        // swift-markdown ไม่ปล่อย semver tag — ต้องอ้าง branch เท่านั้น
        .package(url: "https://github.com/apple/swift-markdown.git", branch: "release/6.3.1"),
        // Draws LaTeX natively with Core Text — math without a web view
        .package(url: "https://github.com/mgriebling/SwiftMath.git", from: "1.7.3"),
    ],
    targets: [
        .executableTarget(
            name: "Domark",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "SwiftMath", package: "SwiftMath"),
            ]
        ),
    ]
)
