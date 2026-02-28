#!/bin/bash
#
# fix_transformerkit.sh
# Fixes @import module compatibility issues in TransformerKit sources
# that break on newer Xcode versions (Xcode 15+/macOS 14+).
#
# Run this AFTER `carthage bootstrap` or `carthage checkout`.

set -euo pipefail

TRANSFORMERKIT_DIR="Carthage/Checkouts/TransformerKit/Sources"

if [ ! -d "$TRANSFORMERKIT_DIR" ]; then
    echo "Error: TransformerKit checkout not found at $TRANSFORMERKIT_DIR"
    exit 1
fi

echo "Fixing TransformerKit @import compatibility issues..."

# Fix NSValueTransformerName.h: @import Darwin.Availability -> #include <Availability.h>
sed -i '' 's/@import Darwin\.Availability;/#include <Availability.h>/' \
    "$TRANSFORMERKIT_DIR/NSValueTransformerName.h"

# Fix NSValueTransformer+TransformerKit.m:
#   @import Darwin.Availability -> #include <Availability.h>
#   @import ObjectiveC.runtime -> #import <objc/runtime.h>
sed -i '' 's/@import Darwin\.Availability;/#include <Availability.h>/' \
    "$TRANSFORMERKIT_DIR/NSValueTransformer+TransformerKit.m"
sed -i '' 's/@import ObjectiveC\.runtime;/#import <objc\/runtime.h>/' \
    "$TRANSFORMERKIT_DIR/NSValueTransformer+TransformerKit.m"

# Fix TTTDateTransformers.m:
#   @import Darwin.C.time -> #include <time.h>
#   @import Darwin.C.xlocale -> #include <xlocale.h>
sed -i '' 's/@import Darwin\.C\.time;/#include <time.h>/' \
    "$TRANSFORMERKIT_DIR/TTTDateTransformers.m"
sed -i '' 's/@import Darwin\.C\.xlocale;/#include <xlocale.h>/' \
    "$TRANSFORMERKIT_DIR/TTTDateTransformers.m"

echo "TransformerKit fixes applied successfully."
