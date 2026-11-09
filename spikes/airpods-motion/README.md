> Hackathon prototype from MakeUC 2026, kept for reference and not maintained. The app lives in [airsign/](../../airsign/).

# AirPods motion spike (throwaway)

Built 2026-11-07 during MakeUC to see what AirPods head-motion data looks like. Not the project. No tests.

## Run

1. `./build.sh`
2. `open build/AirPodsMotion.app`. Your browser opens http://127.0.0.1:8765
3. Put the AirPods in, connect them to this Mac, and click Allow if macOS asks for motion access

The page shows live charts (attitude, gyro, gravity-free acceleration), a 3D head, rough nod/shake/tilt/step detection, and a Record CSV button.

The status window's "Samples/sec" line shows whether streaming continues while the app is in the background.

## What we learned

From one 13.6 s recording (`airpods-motion-2026-11-07T18-11-33-187Z.csv`):

- Steady 50 Hz, a sample every 20 ms, no gaps. It kept streaming while the browser, not this app, was in front.
- Only the left earbud reported the whole time.
- Gyro axes: x = nod (pitch), z = turn/shake (yaw), y = tilt (roll). Nods and turns separate cleanly on the gyro.
- Euler angles get coupled during big turns (pitch read +114° during a turn). Detect gestures from the gyro rates, not from pitch/roll/yaw.
- The starting pose is not "level = 0" (pitch started at −46°), so any app needs a recenter/calibration step.
- Handheld works: an AirPod held in the fingers keeps streaming as long as a finger covers its in-ear (skin) sensor. Tested by the user, photo 2026-11-07.
- Head moves alone produce up to 0.9 g of acceleration, so step counting from the accelerometer will be noisy while the head moves.
