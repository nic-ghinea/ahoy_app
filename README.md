# 🤖 Combat Robot Controller

A Flutter app for driving small combat robots over **Bluetooth Low Energy (BLE)**.
It was built for a two-wheel **N20 gear-motor** drivetrain with a **servo flipper**, running on an ESP32, but any BLE microcontroller that speaks the protocol below will work.

## ✨ Features

- **Dual-stick tank controls**: a vertical throttle stick, a horizontal steering stick and a hold-to-fire **FLIP** button.
- **Custom layout editor**:
  - Drag controls anywhere on the screen.
  - Resize them with the **+ / −** buttons or by pinching.
  - **Double-tap** a control to rotate it 90°.
  - The layout is saved on the device.
- **Robot tuning**:
  - Dual-rate speed zones (slow and fast) for throttle and steering.
  - Per-motor trim for driving straight and for turning.
  - Invert the left or right motor (for all driving, or for steering only).
  - **Swap N20 motors**, in case the left and right motors are wired the wrong way round.
  - Minimum drive power (stall prevention) and turn sensitivity.
  - Flipper servo rest and fire positions.
- **Presets**: save and load as many tuning profiles as you like.
- **Appearance**: background color, a background image from your gallery, and an accent color.
- Landscape-only UI with a 40 ms (25 Hz) control heartbeat.

## 📱 Supported platforms

| Platform | Status |
|----------|--------|
| Android  | ✅ Tested |
| iOS      | ✅ Should work (requires Bluetooth permission strings) |
| Desktop / Web | ⚠️ Not supported (the BLE plugin has limited support) |

## 🚀 Getting started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart `^3.12`)
- A phone with Bluetooth LE

### Build and run
```bash
git clone https://github.com/<your-username>/<your-repo>.git
cd <your-repo>
flutter pub get
flutter run            # with a phone connected
# or build an APK:
flutter build apk --release
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`.

## 🔌 BLE protocol (for your firmware)

The app connects to a device that exposes:

| | UUID |
|---|---|
| Service        | `4fafc201-1fb5-459e-8fcc-c5c9c331914b` |
| Characteristic | `beb5483e-36e1-4688-b7f5-ea07361b26a8` (Write Without Response) |

Every 40 ms it writes a **6-byte** packet:

| Byte | Meaning |
|------|---------|
| 0 | Left motor direction (`0` = forward, `1` = reverse) |
| 1 | Left motor speed (`0–255`) |
| 2 | Right motor direction |
| 3 | Right motor speed (`0–255`) |
| 4 | Weapon servo value, high byte |
| 5 | Weapon servo value, low byte |

The weapon value is `(byte4 << 8) | byte5`. It is either the *Retracted* or the *Fired* tick value set in Robot Settings (range 200–1200).

> 💡 When the robot stops receiving packets, the firmware should stop the motors after a short timeout (failsafe).

### Minimal ESP32 (Arduino) receive example
```cpp
class Callbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *c) override {
    std::string v = c->getValue();
    if (v.length() < 6) return;
    uint8_t dirL = v[0], spdL = v[1], dirR = v[2], spdR = v[3];
    uint16_t weapon = ((uint8_t)v[4] << 8) | (uint8_t)v[5];
    // drive your motor driver + servo here
  }
};
```

## 🛠️ Usage tips

1. Tap the **Bluetooth** icon and pick your robot.
2. Open **⚙ → Robot Settings** to tune the drivetrain:
   - Wheels spin the wrong way: use **Invert Left/Right Motor**.
   - Only turning is backwards: use **Invert Left/Right Motor (Steering)**.
   - Left and right are mixed up: turn on **Swap N20 Motors**.
   - The robot drifts when driving straight: lower the trim on the faster side.
3. Tap the **layout** icon to customize the controls, then tap ✓ to save.

## 📂 Project structure
```
lib/main.dart   # the whole app: config, controller screen, joystick, settings
```

## 🤝 Contributing
Pull requests are welcome. For larger changes, please open an issue first.

## 📄 License
Released under the MIT License (add a `LICENSE` file to your repository).
