import os
import glob

files = glob.glob('third_party/ladybird/Libraries/LibGfx/**/*.h', recursive=True) + \
        glob.glob('third_party/ladybird/Libraries/LibGfx/**/*.cpp', recursive=True)

for f in files:
    with open(f, 'r') as file:
        content = file.read()
    
    new_content = content.replace('#ifdef AK_OS_MACOS', '#if defined(AK_OS_MACOS) || defined(AK_OS_IOS)')
    new_content = new_content.replace('#ifndef AK_OS_MACOS', '#if !defined(AK_OS_MACOS) && !defined(AK_OS_IOS)')
    new_content = new_content.replace('#if defined(AK_OS_MACOS)', '#if defined(AK_OS_MACOS) || defined(AK_OS_IOS)')
    new_content = new_content.replace('#if !defined(AK_OS_MACOS)', '#if !defined(AK_OS_MACOS) && !defined(AK_OS_IOS)')
    new_content = new_content.replace('#    elif defined(AK_OS_MACOS)', '#    elif defined(AK_OS_MACOS) || defined(AK_OS_IOS)')
    
    # We must fix cases where `defined(AK_OS_MACOS) || defined(AK_OS_IOS)` is placed next to `&& !defined(AK_OS_IOS)` from original code (though none should exist in LibGfx based on grep).
    
    if content != new_content:
        with open(f, 'w') as file:
            file.write(new_content)
        print(f"Updated {f}")
