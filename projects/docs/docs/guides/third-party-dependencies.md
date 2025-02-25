---
title: Adding external dependencies
slug: '/guides/third-party-dependencies'
description: Learn how to define the contract between the dependency managers and Tuist.
---

# Adding external dependencies

External dependencies are also represented by a **graph** where nodes represent frameworks, libraries, or bundles. Dependency managers like [CocoaPods](https://cocoapods.org) integrate it when running `pod install` leveraging Xcode workspaces, and Swift Package Manager does it at build time leveraging Xcode's closed build system. Both approaches might lead to integration issues that can cause compilation issues down the road. We are aware that's not a great developer experience, and thus we take a different approach to managing external dependencies that allow leveraging Tuist features such as linting and caching. The idea is simple; developers define their Carthage and Package dependencies in a `Dependencies.swift` file. They are fetched by running `tuist fetch` and integrated into the generated Xcode project at generation time. Because we merge your project and the external dependencies' graph into a single graph, we validate and fail early if the resulting graph is invalid.

:::note CocoaPods support
We are currently working on adding support for CocoaPods.
:::

### Declaring the dependencies

External dependencies are declared in a `Dependencies.swift` file in your project's `Tuist` directory at the project's root. If that file doesn't exist, create an empty file, and run `tuist edit` to edit its content with Xcode. The snippet below shows an example `Dependencies.swift` manifest file:

```swift
import ProjectDescription

let dependencies = Dependencies(
    carthage: [
        .github(path: "Alamofire/Alamofire", requirement: .exact("5.0.4")),
    ],
    swiftPackageManager: [
        .remote(url: "https://github.com/Alamofire/Alamofire", requirement: .upToNextMajor(from: "5.0.0")),
    ],
    platforms: [.iOS]
)
```

:::note Standard interface
One of the benefits of using Tuist's built-in support for declaring external dependencies is that the interface is standard across all the supported dependency managers. It makes moving a dependency from a dependency manager to another a **non-breaking change**.
:::

### Fetching dependencies

After dependencies have been declared, you need to fetch them by running [`tuist fetch`](commands/dependencies.md#fetching). Tuist will use the dependency managers to pull the dependencies under the `Tuist/Dependencies` directory:

```bash
Tuist
    |- Dependencies.swift # Manifest
    |- Dependencies
        |- graph.json # stores the serialized dependencies graph generated by `tuist fetch`
        |- Lockfiles # stores the lockfiles generated by the dependencies resolution
            |- Carthage.resolved
            |- Package.resolved
            |- Podfile.lock # coming soon
        |- Carthage 
            |- Build # stores content of `Carthage/Build` directory generated by `Carthage`
                |- Alamofire.xcframework
                |- .Alamofire.version
            |- Cartfile # the generated Cartfile
        |- SwiftPackageManager
            |- .build # stores content of `.build/` directory generated by `Swift Package Manager`
                |- artifacts
                |- checkouts
                |- repositories
                |- manifest.db
                |- workspace-state.json
            |- Package.swift # the generated Package.swift
        |- Cocoapods # coming soon
            |- Pods # stores content of `Pods` directory generated by `CocoaPods`
                |- RxSwift
            |- Podfile # the generated Podfile
```

We recommend not including the following files and directories through [version control](https://en.wikipedia.org/wiki/Version_control) (i.e. `.gitignore`).

```bash
Tuist/Dependencies/graph.json # Avoid checking in the serialized dependencies graph generated by Tuist.
Tuist/Dependencies/Carthage # Avoid checking in build artifacts from Carthage dependencies.
Tuist/Dependencies/SwiftPackageManager # Avoid checking in build artifacts from Swift Package Manager dependencies.
Tuist/Dependencies/Cocoapods # Avoid checking in build artifacts from CocoaPods dependencies.
```

### Integrating dependencies into your project

Once dependencies have been fetched, you can declare dependencies from your projects' targets. Run `tuist edit` to edit your project's manifest, and use the `.external` target dependency option to declare the dependency.

The snippet below shows an example `Project.swift` manifest file:

```swift
import ProjectDescription

let project = Project(
    name: "App",
    organizationName: "tuist.io",
    targets: [
        Target(
            name: "App",
            platform: .iOS,
            product: .app,
            bundleId: "io.tuist.app",
            deploymentTarget: .iOS(targetVersion: "13.0", devices: .iphone),
            infoPlist: .default,
            sources: ["Targets/App/Sources/**"],
            dependencies: [
                // highlight-next-line
                .external(name: "Alamofire"),
            ]
        ),
    ]
)
```

## Some notes on the integration of Swift Packages

When Swift Packages are integrated into your project's graph, there are some heuristics in place to ensure the resulting graph is valid:

- Tuist defaults to using `iOS` as a platform when there's more than one platform defined in the `Dependencies.swift` and the package manifest file. This is currently a limitation of Tuist [because it does not support multi-platform targets](https://github.com/tuist/tuist/issues/397).
- Tuist defaults to using the product type defined in the `SwiftPackageManagerDependencies.productTypes` property if the linking type is not defined in the package manifest file. If no product type is defined in `SwiftPackageManagerDependencies`, Tuist will default to a `.staticFramework`
- Tuist defaults to not configuring the `ENABLE_TESTING_SEARCH_PATHS` setting for generated SwiftPackageManager targets. If one of your dependencies require it, configure it using the `targetSettings` property in your `Dependencies.swift` file, for example: `targetSettings: ["Nimble": ["ENABLE_TESTING_SEARCH_PATHS": "YES"]]`