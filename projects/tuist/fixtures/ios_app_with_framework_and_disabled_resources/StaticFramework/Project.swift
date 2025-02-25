import ProjectDescription

let project = Project(
    name: "StaticFramework",
    options: [
        .disableBundleAccessors,
        .disableSynthesizedResourceAccessors,
    ],
    targets: [
        Target(
            name: "StaticFramework",
            platform: .iOS,
            product: .staticFramework,
            bundleId: "io.tuist.StaticFramework",
            infoPlist: "Config/StaticFramework-Info.plist",
            sources: "Sources/**",
            dependencies: []
        ),
        Target(
            name: "StaticFrameworkResources",
            platform: .iOS,
            product: .bundle,
            bundleId: "io.tuist.StaticFrameworkResources",
            infoPlist: .default,
            sources: [],
            resources: "Resources/**",
            dependencies: []
        ),
    ]
)
