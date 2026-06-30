#!/bin/bash
# 1. Sign the app with the highly restricted entitlement
echo "Resigning app with restricted entitlement..."
codesign --force --deep --sign - --entitlements ios/Runner/Runner.entitlements build/ios/Debug-iphonesimulator/Runner.app

# 2. Install it on the simulator
echo "Installing app..."
xcrun simctl install booted build/ios/Debug-iphonesimulator/Runner.app

# 3. Start streaming logs in the background specifically looking for code signing/amfid failures
echo "Starting log stream..."
xcrun simctl spawn booted log stream --predicate 'process == "amfid" || subsystem contains "com.apple.security" || message contains "app.rubisco.flutterbird" || message contains "entitlement"' > amfid_proof.log 2>&1 &
LOG_PID=$!

# Give it a second to start streaming
sleep 1

# 4. Attempt to launch the app
echo "Attempting to launch app..."
xcrun simctl launch booted app.rubisco.flutterbird

# 5. Wait for logs to settle
sleep 3

# 6. Kill log stream
kill $LOG_PID

# 7. Show the logs
echo "========== AMFID LOGS =========="
cat amfid_proof.log
