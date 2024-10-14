// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TunnelKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .tvOS(.v17)
    ],
    products: [
        .library(
            name: "TunnelKit",
            targets: ["TunnelKit"]
        ),
        .library(
            name: "TunnelKitOpenVPN",
            targets: ["TunnelKitOpenVPN"]
        ),
        .library(
            name: "TunnelKitOpenVPNAppExtension",
            targets: ["TunnelKitOpenVPNAppExtension"]
        ),
        .library(
            name: "TunnelKitWireGuard",
            targets: ["TunnelKitWireGuard"]
        ),
        .library(
            name: "TunnelKitWireGuardAppExtension",
            targets: ["TunnelKitWireGuardAppExtension"]
        ),
        .library(
            name: "TunnelKitLZO",
            targets: ["TunnelKitLZO"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/SwiftyBeaver/SwiftyBeaver", from: "1.9.0"),
        .package(url: "https://github.com/passepartoutvpn/wireguard-apple", revision: "b79f0f150356d8200a64922ecf041dd020140aa0")
    ],
    targets: [
        .target(
            name: "TunnelKit",
            dependencies: [
                "TunnelKitCore",
                "TunnelKitManager"
            ]
        ),
        .target(
            name: "TunnelKitCore",
            dependencies: [
                "__TunnelKitUtils",
                "CTunnelKitCore",
                "SwiftyBeaver"
            ]),
        .target(
            name: "TunnelKitManager",
            dependencies: [
                "SwiftyBeaver"
            ]),
        .target(
            name: "TunnelKitAppExtension",
            dependencies: [
                "TunnelKitCore"
            ]),
        .target(
            name: "TunnelKitOpenVPN",
            dependencies: [
                "TunnelKitOpenVPNCore",
                "TunnelKitOpenVPNManager"
            ]),
        .target(
            name: "TunnelKitOpenVPNCore",
            dependencies: [
                "TunnelKitCore",
                "CTunnelKitOpenVPNCore",
                "CTunnelKitOpenVPNProtocol"
            ]),
        .target(
            name: "TunnelKitOpenVPNManager",
            dependencies: [
                "TunnelKitManager",
                "TunnelKitOpenVPNCore"
            ]),
        .target(
            name: "TunnelKitOpenVPNProtocol",
            dependencies: [
                "TunnelKitOpenVPNCore",
                "CTunnelKitOpenVPNProtocol",
                "openssl"
            ]),
        .target(
            name: "TunnelKitOpenVPNAppExtension",
            dependencies: [
                "TunnelKitAppExtension",
                "TunnelKitOpenVPNCore",
                "TunnelKitOpenVPNManager",
                "TunnelKitOpenVPNProtocol"
            ]),
        .target(
            name: "TunnelKitWireGuard",
            dependencies: [
                "TunnelKitWireGuardCore",
                "TunnelKitWireGuardManager"
            ]),
        .target(
            name: "TunnelKitWireGuardCore",
            dependencies: [
                "__TunnelKitUtils",
                "TunnelKitCore",
                .product(name: "WireGuardKit", package: "wireguard-apple"),
                "SwiftyBeaver"
            ]),
        .target(
            name: "TunnelKitWireGuardManager",
            dependencies: [
                "TunnelKitManager",
                "TunnelKitWireGuardCore"
            ]),
        .target(
            name: "TunnelKitWireGuardAppExtension",
            dependencies: [
                "TunnelKitWireGuardCore",
                "TunnelKitWireGuardManager"
            ]),
        .target(
            name: "TunnelKitLZO",
            dependencies: [],
            exclude: [
                "lib/COPYING",
                "lib/Makefile",
                "lib/README.LZO",
                "lib/testmini.c"
            ]),
        .binaryTarget(
                    name: "openssl",
                    path: "./Frameworks/openssl.xcframework"
                ),
        .target(
            name: "CTunnelKitCore",
            dependencies: []),
        .target(
            name: "CTunnelKitOpenVPNCore",
            dependencies: []),
        .target(
            name: "CTunnelKitOpenVPNProtocol",
            dependencies: [
                "CTunnelKitCore",
                "CTunnelKitOpenVPNCore",
                "openssl"
            ]),
        .target(
            name: "__TunnelKitUtils",
            dependencies: []),
        .testTarget(
            name: "TunnelKitCoreTests",
            dependencies: [
                "TunnelKitCore"
            ],
            exclude: [
                "RandomTests.swift",
                "RawPerformanceTests.swift",
                "RoutingTests.swift"
            ]),
        .testTarget(
            name: "TunnelKitOpenVPNTests",
            dependencies: [
                "TunnelKitOpenVPNCore",
                "TunnelKitOpenVPNAppExtension",
                "TunnelKitLZO"
            ],
            exclude: [
                "DataPathPerformanceTests.swift",
                "EncryptionPerformanceTests.swift"
            ],
            resources: [
                .process("Resources")
            ]),
        .testTarget(
            name: "TunnelKitLZOTests",
            dependencies: [
                "TunnelKitCore",
                "TunnelKitLZO"
            ])
    ]
)
