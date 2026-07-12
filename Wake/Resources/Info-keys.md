# Info.plist keys & capabilities

XcodeGen injects the usage strings via `project.yml` (`INFOPLIST_KEY_*`). If you
create the project manually in Xcode, add these to Info.plist and enable the
matching capabilities.

## Usage descriptions
| Key | Value |
|---|---|
| `NSHealthShareUsageDescription` | Wake reads your sleep data to learn how long you take to wake up. |
| `NSMotionUsageDescription` | Wake reads your motion history to estimate when you fell asleep. |
| `NSMicrophoneUsageDescription` | Wake listens for “I’m awake” to decide whether to stop the alarm. |
| `NSSpeechRecognitionUsageDescription` | Wake recognises your voice on-device to confirm you’re awake. |

## Background modes (`UIBackgroundModes`)
- `audio` — legitimately playing the wake soundscape through the early stages.

## Capabilities to enable in Signing & Capabilities
- **Background Modes → Audio**
- **HealthKit** (read: Sleep Analysis)
- **Push Notifications** / local notification auth (requested at runtime)
- **Critical Alerts** — requires a special entitlement request to Apple; until
  granted, the ladder uses `.timeSensitive` interruption level.
- **AlarmKit** (iOS 26) — for the guaranteed deadline alarm; gated at runtime.

## UI
- `UIUserInterfaceStyle = Dark` — Wake commits to the night world.
