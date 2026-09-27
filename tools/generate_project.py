#!/usr/bin/env python3
"""Regenerates MuonMonitor.xcodeproj from the folders on disk.

Run from the repository root after cloning, and again after adding or removing
Swift files or resources:  python3 tools/generate_project.py
Signing and identifiers live in MuonMonitor/Config.xcconfig, not in the project.
Paths inside the project are relative to MuonMonitor/.
"""
import hashlib, json, os, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent / "MuonMonitor"
PROJ = ROOT / "MuonMonitor.xcodeproj"

def oid(*parts):
    return hashlib.md5("/".join(parts).encode()).hexdigest()[:24].upper()

def swift(folder):
    return sorted(str(p.relative_to(ROOT)) for p in (ROOT / folder).rglob("*.swift"))

# Everything in Shared/ is compiled into both targets (design tokens, glyphs, activity
# attributes, intents), except the telemetry decoder, which only the app needs.
WIDGET_EXCLUDED = {"Shared/Telemetry.swift"}
WIDGET_SHARED = [p for p in swift("Shared") if p not in WIDGET_EXCLUDED]
# Bundled fonts (SIL OFL 1.1) are copied into both the app and the widget extension
# and registered through UIAppFonts in each Info.plist.
RESOURCES = sorted(str(p.relative_to(ROOT)) for p in (ROOT / "Resources").rglob("*") if p.is_file() and not p.name.startswith("."))
APP_SOURCES = swift("App") + swift("Shared")
WIDGET_SOURCES = swift("Widget") + WIDGET_SHARED
UI_TEST_SOURCES = ["../tests/UITests/TabNavigationTests.swift"]
OTHER_FILES = ["Assets.xcassets", "App/Info.plist", "Widget/Info.plist", "App/App.entitlements", "Widget/Widget.entitlements", "Config.xcconfig"]

objects = {}
def add(key, obj):
    objects[key] = obj
    return key

def filetype(p):
    return {".swift": "sourcecode.swift", ".plist": "text.plist.xml", ".entitlements": "text.plist.entitlements",
            ".xcconfig": "text.xcconfig", ".md": "net.daringfireball.markdown", ".ttf": "file", ".otf": "file",
            ".txt": "text", ".xcassets": "folder.assetcatalog"}[pathlib.Path(p).suffix]

fileref = {}
for p in sorted(set(APP_SOURCES + WIDGET_SOURCES + OTHER_FILES + RESOURCES + UI_TEST_SOURCES)):
    fileref[p] = add(oid("ref", p), {"isa": "PBXFileReference", "lastKnownFileType": filetype(p), "path": p, "sourceTree": "<group>"})

app_product = add(oid("product", "app"), {"isa": "PBXFileReference", "explicitFileType": "wrapper.application", "path": "MuonMonitor.app", "sourceTree": "BUILT_PRODUCTS_DIR", "includeInIndex": 0})
ext_product = add(oid("product", "ext"), {"isa": "PBXFileReference", "explicitFileType": "wrapper.app-extension", "path": "MuonLive.appex", "sourceTree": "BUILT_PRODUCTS_DIR", "includeInIndex": 0})

def group(name, paths):
    return add(oid("group", name), {"isa": "PBXGroup", "children": [fileref[p] for p in paths], "name": name, "sourceTree": "<group>"})

groups = [group("App", [p for p in fileref if p.startswith("App/")]), group("Shared", [p for p in fileref if p.startswith("Shared/")]),
          group("Widget", [p for p in fileref if p.startswith("Widget/")]), group("Resources", RESOURCES),
          group("Configuration", ["Config.xcconfig", "Assets.xcassets"])]
products = add(oid("group", "products"), {"isa": "PBXGroup", "children": [app_product, ext_product], "name": "Products", "sourceTree": "<group>"})
main_group = add(oid("group", "main"), {"isa": "PBXGroup", "children": groups + [products], "sourceTree": "<group>"})

def sources_phase(target, paths):
    files = [add(oid("build", target, p), {"isa": "PBXBuildFile", "fileRef": fileref[p]}) for p in paths]
    return add(oid("phase", target, "sources"), {"isa": "PBXSourcesBuildPhase", "buildActionMask": 2147483647, "files": files, "runOnlyForDeploymentPostprocessing": 0})

def resources_phase(target, paths):
    files = [add(oid("build", target, "res", p), {"isa": "PBXBuildFile", "fileRef": fileref[p]}) for p in paths]
    return add(oid("phase", target, "PBXResourcesBuildPhase"), {"isa": "PBXResourcesBuildPhase", "buildActionMask": 2147483647, "files": files, "runOnlyForDeploymentPostprocessing": 0})

def empty_phase(target, isa):
    return add(oid("phase", target, isa), {"isa": isa, "buildActionMask": 2147483647, "files": [], "runOnlyForDeploymentPostprocessing": 0})

xcconfig = fileref["Config.xcconfig"]
COMMON = {"SDKROOT": "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET": "26.0", "SWIFT_VERSION": "5.0", "TARGETED_DEVICE_FAMILY": "1",
          "CODE_SIGN_STYLE": "Automatic", "DEVELOPMENT_TEAM": "$(MUON_TEAM)", "CLANG_ENABLE_MODULES": "YES",
          "SWIFT_EMIT_LOC_STRINGS": "YES", "ENABLE_USER_SCRIPT_SANDBOXING": "YES", "CURRENT_PROJECT_VERSION": "4", "MARKETING_VERSION": "2.1"}
DEBUG = {"SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG", "SWIFT_OPTIMIZATION_LEVEL": "-Onone", "DEBUG_INFORMATION_FORMAT": "dwarf", "ONLY_ACTIVE_ARCH": "YES", "ENABLE_TESTABILITY": "YES", "COPY_PHASE_STRIP": "NO"}
RELEASE = {"SWIFT_ACTIVE_COMPILATION_CONDITIONS": "", "SWIFT_OPTIMIZATION_LEVEL": "-O", "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym"}

def configs(target, settings):
    ids = []
    for name, extra in (("Debug", DEBUG), ("Release", RELEASE)):
        ids.append(add(oid("config", target, name), {"isa": "XCBuildConfiguration", "baseConfigurationReference": xcconfig,
                                                    "buildSettings": {**COMMON, **extra, **settings}, "name": name}))
    return add(oid("configlist", target), {"isa": "XCConfigurationList", "buildConfigurations": ids, "defaultConfigurationIsVisible": 0, "defaultConfigurationName": "Release"})

RUNPATH = ["$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"]
ext_target = add(oid("target", "ext"), {
    "isa": "PBXNativeTarget", "name": "MuonLive", "productName": "MuonLive", "productReference": ext_product,
    "productType": "com.apple.product-type.app-extension", "buildRules": [], "dependencies": [],
    "buildConfigurationList": configs("ext", {"PRODUCT_NAME": "MuonLive", "PRODUCT_BUNDLE_IDENTIFIER": "$(MUON_BUNDLE_ID).Live",
                                             "INFOPLIST_FILE": "Widget/Info.plist", "GENERATE_INFOPLIST_FILE": "NO", "CODE_SIGN_ENTITLEMENTS": "$(MUON_WIDGET_ENTITLEMENTS)",
                                             "LD_RUNPATH_SEARCH_PATHS": RUNPATH, "SKIP_INSTALL": "YES", "APPLICATION_EXTENSION_API_ONLY": "YES"}),
    "buildPhases": [sources_phase("ext", WIDGET_SOURCES), empty_phase("ext", "PBXFrameworksBuildPhase"), resources_phase("ext", RESOURCES)]})

project_id = oid("project")
proxy = add(oid("proxy", "ext"), {"isa": "PBXContainerItemProxy", "containerPortal": project_id, "proxyType": 1, "remoteGlobalIDString": ext_target, "remoteInfo": "MuonLive"})
dependency = add(oid("dependency", "ext"), {"isa": "PBXTargetDependency", "target": ext_target, "targetProxy": proxy})
embed_file = add(oid("embed", "ext"), {"isa": "PBXBuildFile", "fileRef": ext_product, "settings": {"ATTRIBUTES": ["RemoveHeadersOnCopy"]}})
embed = add(oid("phase", "app", "embed"), {"isa": "PBXCopyFilesBuildPhase", "buildActionMask": 2147483647, "dstPath": "", "dstSubfolderSpec": 13,
                                            "files": [embed_file], "name": "Embed Foundation Extensions", "runOnlyForDeploymentPostprocessing": 0})
app_target = add(oid("target", "app"), {
    "isa": "PBXNativeTarget", "name": "MuonMonitor", "productName": "MuonMonitor", "productReference": app_product,
    "productType": "com.apple.product-type.application", "buildRules": [], "dependencies": [dependency],
    "buildConfigurationList": configs("app", {"PRODUCT_NAME": "MuonMonitor", "PRODUCT_BUNDLE_IDENTIFIER": "$(MUON_BUNDLE_ID)",
                                             "INFOPLIST_FILE": "App/Info.plist", "GENERATE_INFOPLIST_FILE": "NO", "CODE_SIGN_ENTITLEMENTS": "$(MUON_APP_ENTITLEMENTS)",
                                             "LD_RUNPATH_SEARCH_PATHS": RUNPATH, "SKIP_INSTALL": "NO", "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon"}),
    "buildPhases": [sources_phase("app", APP_SOURCES), empty_phase("app", "PBXFrameworksBuildPhase"), resources_phase("app", RESOURCES + ["Assets.xcassets"]), embed]})

ui_product = add(oid("product", "uitests"), {"isa": "PBXFileReference", "explicitFileType": "wrapper.cfbundle", "path": "MuonUITests.xctest", "sourceTree": "BUILT_PRODUCTS_DIR"})
objects[products]["children"].append(ui_product)
objects[main_group]["children"].append(group("UI Tests", UI_TEST_SOURCES))
ui_proxy = add(oid("proxy", "app"), {"isa": "PBXContainerItemProxy", "containerPortal": project_id, "proxyType": 1, "remoteGlobalIDString": app_target, "remoteInfo": "MuonMonitor"})
ui_dependency = add(oid("dependency", "app"), {"isa": "PBXTargetDependency", "target": app_target, "targetProxy": ui_proxy})
ui_target = add(oid("target", "uitests"), {
    "isa": "PBXNativeTarget", "name": "MuonUITests", "productName": "MuonUITests", "productReference": ui_product,
    "productType": "com.apple.product-type.bundle.ui-testing", "buildRules": [], "dependencies": [ui_dependency],
    "buildConfigurationList": configs("uitests", {"PRODUCT_NAME": "MuonUITests", "PRODUCT_BUNDLE_IDENTIFIER": "$(MUON_BUNDLE_ID).UITests",
        "GENERATE_INFOPLIST_FILE": "YES", "TEST_TARGET_NAME": "MuonMonitor", "LD_RUNPATH_SEARCH_PATHS": RUNPATH, "SKIP_INSTALL": "YES"}),
    "buildPhases": [sources_phase("uitests", UI_TEST_SOURCES), empty_phase("uitests", "PBXFrameworksBuildPhase"), resources_phase("uitests", [])]})

objects[project_id] = {"isa": "PBXProject", "attributes": {"LastUpgradeCheck": "2700", "BuildIndependentTargetsInParallel": "YES",
                       "TargetAttributes": {app_target: {"CreatedOnToolsVersion": "27.0"}, ext_target: {"CreatedOnToolsVersion": "27.0"}}},
                       "buildConfigurationList": configs("project", {}), "compatibilityVersion": "Xcode 14.0", "developmentRegion": "en",
                       "hasScannedForEncodings": 0, "knownRegions": ["en", "Base"], "mainGroup": main_group, "productRefGroup": products,
                       "projectDirPath": "", "projectRoot": "", "targets": [app_target, ext_target, ui_target]}

def plist(v):
    if isinstance(v, dict): return "{" + "".join(f"{json.dumps(k)} = {plist(x)};" for k, x in v.items()) + "}"
    if isinstance(v, list): return "(" + ",".join(plist(x) for x in v) + ")"
    return json.dumps(str(v)) if not isinstance(v, int) else str(v)

PROJ.mkdir(exist_ok=True)
(PROJ / "project.pbxproj").write_text("// !$*UTF8*$!\n" + plist({"archiveVersion": 1, "classes": {}, "objectVersion": 56, "objects": objects, "rootObject": project_id}) + "\n")

def scheme(name, args):
    ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" BuildableName="MuonMonitor.app" BlueprintName="MuonMonitor" ReferencedContainer="container:MuonMonitor.xcodeproj"/>'
    test_ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ui_target}" BuildableName="MuonUITests.xctest" BlueprintName="MuonUITests" ReferencedContainer="container:MuonMonitor.xcodeproj"/>'
    test_action = f'<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{test_ref}</TestableReference></Testables></TestAction>'
    launch_args = "".join(f'<CommandLineArgument argument="{a}" isEnabled="YES"/>' for a in args)
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.7"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction>{test_action}<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable>{"<CommandLineArguments>" + launch_args + "</CommandLineArguments>" if args else ""}</LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>
'''

schemes = PROJ / "xcshareddata" / "xcschemes"
schemes.mkdir(parents=True, exist_ok=True)
(schemes / "MuonMonitor.xcscheme").write_text(scheme("MuonMonitor", []))
(schemes / "MuonMonitor Demo.xcscheme").write_text(scheme("MuonMonitor Demo", ["--demo"]))
print(f"{len(APP_SOURCES)} app sources, {len(WIDGET_SOURCES)} widget sources, {len(RESOURCES)} resources → {PROJ.relative_to(ROOT.parent)}")
