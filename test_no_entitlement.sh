#!/bin/bash
echo "Resigning app WITHOUT restricted entitlement..."
codesign --force --deep --sign - build/ios/Debug-iphonesimulator/Runner.app

echo "Installing app..."
xcrun simctl install booted build/ios/Debug-iphonesimulator/Runner.app

echo "Starting log stream..."
xcrun simctl spawn booted log stream --predicate 'process == "amfid" || subsystem contains "com.apple.security" || message contains "app.rubisco.flutterbird" || message contains "entitlement"' > no_entitlement_proof.log 2>&1 &
LOG_PID=$!

sleep 1

echo "Attempting to launch app..."
xcrun simctl launch booted app.rubisco.flutterbird

sleep 3
kill $LOG_PID

echo "========== LOGS =========="
cat no_entitlement_proof.log
