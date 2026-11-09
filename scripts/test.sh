#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

# Check if the x86_64 CommandLineTools PackageDescription manifest defect is present
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    SHIM_OBJ="/tmp/desKTop_pm_shim.o"
    cat << 'EOF' > /tmp/desKTop_pm_shim.s
.text
.globl _$s18PackageDescription0A0C4name19defaultLocalization9platforms9pkgConfig9providers8products12dependencies7targets21swiftLanguageVersions01cN8Standard03cxxnP0ACSS_AA0N3TagVSgSayAA17SupportedPlatformVGSgSSSgSayAA06SystemA8ProviderOGSgSayAA7ProductCGSayAC10DependencyCGSayAA6TargetCGSayAA12SwiftVersionOGSgAA09CLanguageP0OSgAA011CXXLanguageP0OSgtcfC
_$s18PackageDescription0A0C4name19defaultLocalization9platforms9pkgConfig9providers8products12dependencies7targets21swiftLanguageVersions01cN8Standard03cxxnP0ACSS_AA0N3TagVSgSayAA17SupportedPlatformVGSgSSSgSayAA06SystemA8ProviderOGSgSayAA7ProductCGSayAC10DependencyCGSayAA6TargetCGSayAA12SwiftVersionOGSgAA09CLanguageP0OSgAA011CXXLanguageP0OSgtcfC:
    jmp _$s18PackageDescription0A0C4name19defaultLocalization9platforms9pkgConfig9providers8products12dependencies7targets21swiftLanguageVersions01cN8Standard03cxxnP0ACSS_AA0N3TagVSgSayAA17SupportedPlatformVGSgSSSgSayAA06SystemA8ProviderOGSgSayAA7ProductCGSayAC10DependencyCGSayAA6TargetCGSayAA05SwiftN4ModeOGSgAA09CLanguageP0OSgAA011CXXLanguageP0OSgtcfC
EOF
    clang -target x86_64-apple-macos14.0 -c /tmp/desKTop_pm_shim.s -o "$SHIM_OBJ" 2>/dev/null

    cat << EOF > /tmp/desKTop_swiftc_wrapper
#!/usr/bin/env bash
if [[ "\$*" == *"app-manifest"* ]] || [[ "\$*" == *"Package.swift"* ]]; then
    exec /Library/Developer/CommandLineTools/usr/bin/swiftc "\$@" -Xlinker "$SHIM_OBJ"
else
    exec /Library/Developer/CommandLineTools/usr/bin/swiftc "\$@"
fi
EOF
    chmod +x /tmp/desKTop_swiftc_wrapper
    export SWIFT_EXEC=/tmp/desKTop_swiftc_wrapper
fi

swift run desKTopTests "$@"
