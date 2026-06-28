#!/bin/bash
counter=0
for lib in $(find ladybird_build -name "*.a" -type f); do
    if grep -q "__RNvCs5QKde7ScR4H_" "$lib" 2>/dev/null; then
        char=$(printf \\$(printf '%03o' $((65 + counter))))
        perl -pi -e "s/__RNvCs5QKde7ScR4H_/__RNvCs5QKde7ScR4${char}_/g" "$lib"
        ranlib "$lib" 2>/dev/null || true
        counter=$((counter + 1))
    fi
done
