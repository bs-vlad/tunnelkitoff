// swift-tools-version:5.9
import PackageDescription

let package = Package(
  name: "TunnelKit",
  platforms: [
    .iOS(.v16),
    .macOS(.v13),
    .tvOS(.v17),
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
    ),
    .library(
      name: "TunnelKitLogging",
      targets: ["TunnelKitLogging"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/SwiftyBeaver/SwiftyBeaver", from: "1.9.0"),
    .package(url: "https://github.com/roop/wireguard-apple.git", branch: "master"),
  ],
  targets: [
    .target(
      name: "TunnelKit",
      dependencies: [
        "TunnelKitCore",
        "TunnelKitManager",
      ]
    ),
    .target(
      name: "TunnelKitCore",
      dependencies: [
        "__TunnelKitUtils",
        "CTunnelKitCore",
        "SwiftyBeaver",
      ]),
    .target(
      name: "TunnelKitManager",
      dependencies: [
        "TunnelKitWireGuardCore",
        "TunnelKitLogging",
        "SwiftyBeaver",
      ]),
    .target(
      name: "TunnelKitAppExtension",
      dependencies: [
        "TunnelKitCore",
        "TunnelKitLogging",
      ]),
    .target(
      name: "TunnelKitOpenVPN",
      dependencies: [
        "TunnelKitOpenVPNCore",
        "TunnelKitOpenVPNManager",
      ]),
    .target(
      name: "TunnelKitOpenVPNCore",
      dependencies: [
        "TunnelKitCore",
        "CTunnelKitOpenVPNCore",
        "CTunnelKitOpenVPNProtocol",
        "TunnelKitLogging",
      ]),
    .target(
      name: "TunnelKitOpenVPNManager",
      dependencies: [
        "TunnelKitManager",
        "TunnelKitOpenVPNCore",
      ]),
    .target(
      name: "TunnelKitOpenVPNProtocol",
      dependencies: [
        "TunnelKitOpenVPNCore",
        "CTunnelKitOpenVPNProtocol",
        "openssl",
      ]),
    .target(
      name: "TunnelKitOpenVPNAppExtension",
      dependencies: [
        "TunnelKitAppExtension",
        "TunnelKitOpenVPNCore",
        "TunnelKitOpenVPNManager",
        "TunnelKitOpenVPNProtocol",
      ]),
    .target(
      name: "TunnelKitWireGuard",
      dependencies: [
        "TunnelKitWireGuardCore",
        "TunnelKitWireGuardManager",
      ]),
    .target(
      name: "TunnelKitWireGuardCore",
      dependencies: [
        "__TunnelKitUtils",
        "TunnelKitCore",
        "TunnelKitLogging",  // Add this dependency
        .product(name: "WireGuardKit", package: "wireguard-apple"),
        "SwiftyBeaver",
      ]),

    .target(
      name: "TunnelKitWireGuardManager",
      dependencies: [
        "TunnelKitManager",
        "TunnelKitWireGuardCore",
      ]),
    .target(
      name: "TunnelKitWireGuardAppExtension",
      dependencies: [
        "TunnelKitWireGuardCore",
        "TunnelKitWireGuardManager",
      ]),
    .target(
      name: "TunnelKitLZO",
      dependencies: [],
      exclude: [
        "lib/COPYING",
        "lib/Makefile",
        "lib/README.LZO",
        "lib/testmini.c",
      ]),
    .binaryTarget(
      name: "openssl",
      path: "./Frameworks/OpenSSL.xcframework"
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
        "openssl",
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
        "RoutingTests.swift",
      ]),
    .testTarget(
      name: "TunnelKitOpenVPNTests",
      dependencies: [
        "TunnelKitOpenVPNCore",
        "TunnelKitOpenVPNAppExtension",
        "TunnelKitLZO",
      ],
      exclude: [
        "DataPathPerformanceTests.swift",
        "EncryptionPerformanceTests.swift",
      ],
      resources: [
        .process("Resources")
      ]),
    .testTarget(
      name: "TunnelKitLZOTests",
      dependencies: [
        "TunnelKitCore",
        "TunnelKitLZO",
      ]),
    .target(
      name: "TunnelKitLogging",
      dependencies: [
        "SwiftyBeaver"
      ]),
  ]
)
