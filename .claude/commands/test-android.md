You are preparing for a manual Android test session on a connected physical device.

## Steps

1. **Update from main**: Pull latest changes from main into the current branch. Resolve any merge conflicts.

```
git fetch origin main && git merge origin/main --no-edit
```

If there are merge conflicts, resolve them, then `git add` the resolved files and `git commit`.

2. **Build the Android app**: Build a debug APK using the Android Studio bundled JDK.

```
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
export ANDROID_HOME="/Users/sudarshan/Library/Android/sdk"
cd android && ./gradlew assembleDebug
```

Fix any build errors and retry until the build succeeds.

3. **Install and launch on device**: Find the connected physical device (not emulator) via `adb devices`, then install and launch.

```
export PATH="/Users/sudarshan/Library/Android/sdk/platform-tools:$PATH"
DEVICE=$(adb devices | grep -v emulator | grep 'device$' | head -1 | awk '{print $1}')
adb -s "$DEVICE" install -r android/app/build/outputs/apk/debug/app-debug.apk
adb -s "$DEVICE" shell am force-stop com.iceblox.app
adb -s "$DEVICE" shell am start -n com.iceblox.app/.MainActivity
```

4. **Capture screenshots**: Create a timestamped directory under `.context/test-screenshots/`, then take a screenshot every 5 seconds for 60 seconds (12 screenshots total). Save each with an incrementing filename. After all screenshots are captured, display each one using the Read tool so you can see them.

```
export PATH="/Users/sudarshan/Library/Android/sdk/platform-tools:$PATH"
DEVICE=$(adb devices | grep -v emulator | grep 'device$' | head -1 | awk '{print $1}')
DIR=".context/test-screenshots/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$DIR"
for i in $(seq -w 1 12); do
  adb -s "$DEVICE" exec-out screencap -p > "$DIR/screenshot-$i.png"
  sleep 5
done
```

After capturing, read each screenshot image and summarize what you observe (detections, bounding boxes, errors, UI state).

5. **Report**: Summarize the test session — what worked, what didn't, any issues observed across the screenshots.
