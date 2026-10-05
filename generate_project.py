"""Generate a dependency-free iPhone Xcode project. No signing credentials included."""
from pathlib import Path
import hashlib
root = Path(__file__).parent

def uid(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()

def q(value):
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'

objects = []
def add(name, body):
    objects.append(f'{uid(name)} = {{ {body} }};')

sources = sorted((root/'BodybuildingPro').glob('*.swift'))
file_ids, build_ids = [], []
for path in sources:
    name = path.name
    add('file:'+name, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(name)}; sourceTree = "<group>";')
    add('build:'+name, f'isa = PBXBuildFile; fileRef = {uid("file:"+name)};')
    file_ids.append(uid('file:'+name)); build_ids.append(uid('build:'+name))
for name, kind in [('Info.plist','text.plist.xml'), ('PrivacyInfo.xcprivacy','text.xml'), ('Assets.xcassets','folder.assetcatalog')]:
    add('file:'+name, f'isa = PBXFileReference; lastKnownFileType = {kind}; path = {q(name)}; sourceTree = "<group>";')
    file_ids.append(uid('file:'+name))
add('assets-build', f'isa = PBXBuildFile; fileRef = {uid("file:Assets.xcassets")};')
add('privacy-build', f'isa = PBXBuildFile; fileRef = {uid("file:PrivacyInfo.xcprivacy")};')
add('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = BodybuildingPro.app; sourceTree = BUILT_PRODUCTS_DIR;')
add('sources', 'isa = PBXGroup; children = ('+','.join(file_ids)+',); path = BodybuildingPro; sourceTree = "<group>";')
add('products', f'isa = PBXGroup; children = ({uid("product")},); name = Products; sourceTree = "<group>";')
add('main', f'isa = PBXGroup; children = ({uid("sources")},{uid("products")},); sourceTree = "<group>";')
add('sourcephase', 'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ('+','.join(build_ids)+',); runOnlyForDeploymentPostprocessing = 0;')
add('frameworkphase', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
add('resourcesphase', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({uid("privacy-build")},{uid("assets-build")},); runOnlyForDeploymentPostprocessing = 0;')
for config in ['Debug', 'Release']:
    settings = 'CLANG_ENABLE_MODULES = YES; SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SWIFT_VERSION = 5.0;'
    settings += ' SWIFT_OPTIMIZATION_LEVEL = "-Onone"; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;' if config == 'Debug' else ' SWIFT_COMPILATION_MODE = wholemodule; SWIFT_OPTIMIZATION_LEVEL = "-O";'
    add('project:'+config, f'isa = XCBuildConfiguration; buildSettings = {{ {settings} }}; name = {config};')
    settings = 'ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; CODE_SIGN_STYLE = Automatic; GENERATE_INFOPLIST_FILE = NO; INFOPLIST_FILE = BodybuildingPro/Info.plist; PRODUCT_BUNDLE_IDENTIFIER = com.example.bodybuildingpro; PRODUCT_NAME = "$(TARGET_NAME)"; TARGETED_DEVICE_FAMILY = 1; SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"; ENABLE_PREVIEWS = YES; LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks";'
    add('target:'+config, f'isa = XCBuildConfiguration; buildSettings = {{ {settings} }}; name = {config};')
for group in ['project','target']:
    add(group+'configs', f'isa = XCConfigurationList; buildConfigurations = ({uid(group+":Debug")},{uid(group+":Release")},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
add('target', f'isa = PBXNativeTarget; buildConfigurationList = {uid("targetconfigs")}; buildPhases = ({uid("sourcephase")},{uid("frameworkphase")},{uid("resourcesphase")},); buildRules = (); dependencies = (); name = BodybuildingPro; productName = BodybuildingPro; productReference = {uid("product")}; productType = "com.apple.product-type.application";')
add('project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 1600; }}; buildConfigurationList = {uid("projectconfigs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = ko; hasScannedForEncodings = 0; knownRegions = (ko,en,Base,); mainGroup = {uid("main")}; productRefGroup = {uid("products")}; projectDirPath = ""; projectRoot = ""; targets = ({uid("target")},);')
folder = root/'BodybuildingPro.xcodeproj'; folder.mkdir(exist_ok=True)
(folder/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+f'\n}}; rootObject = {uid("project")}; }}\n')
print(f'Generated project with {len(sources)} Swift sources')
# A shared scheme is required for command-line and hosted macOS builds.
schemes = folder/'xcshareddata'/'xcschemes'; schemes.mkdir(parents=True, exist_ok=True)
(schemes/'BodybuildingPro.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('target')}" BuildableName="BodybuildingPro.app" BlueprintName="BodybuildingPro" ReferencedContainer="container:BodybuildingPro.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('target')}" BuildableName="BodybuildingPro.app" BlueprintName="BodybuildingPro" ReferencedContainer="container:BodybuildingPro.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<AnalyzeAction buildConfiguration="Debug"/>
<ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
