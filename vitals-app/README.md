# PulseGuard — Wearable Companion App

**PulseGuard** is a customized companion Progressive Web App (PWA) designed specifically for the **ESP32-S3 Smart Wearable Vital Signs Monitor**.

It interfaces with the watch's current firmware **without requiring any changes to the hardware code**.

---

## Key Features

- **Dual-Mode Connectivity**:
  - **Bluetooth Low Energy (BLE)**: Connects directly to the watch GATT server (`Vitals-Watch`) using the Web Bluetooth API.
  - **Wi-Fi Network / Hotspot**: Connects over the local LAN or the watch's own access point (`192.168.4.1`).
- **Apple Health / Cyber-Medical Dark UI**:
  - Glassmorphic card design with dynamic neon glowing accents.
  - Beating heart icon synchronized with real beat detection.
  - Color-coded biometric thresholds (Optimal, Elevated, Low, Fever).
- **Real-Time 60 FPS ECG Oscilloscope**:
  - High-precision HTML5 Canvas rendering of the filtered 250 Hz ECG telemetry.
  - Phosphor persistence trace with medical grid overlay.
  - Leads status indicator (`Leads Connected` vs `Leads Disconnected`).
- **Audio Heartbeat Chime**:
  - Web Audio API synthesizer for optional real-time medical monitor beep on each heartbeat.
- **Session Analytics & Export**:
  - Live Min, Max, Average BPM, and lowest SpO₂ calculation.
  - Instant one-click **Export Session CSV** for research data analysis (e.g., Bland-Altman plots).
- **PWA Ready**:
  - Service worker and Web App Manifest installed.
  - Can be added directly to the home screen of Android and iOS devices.

---

## How to Run the App

### Option A: Local Run (Quickest)
1. Navigate to the `vitals-app` folder.
2. Double-click **`start-app.bat`**.
3. Your browser will automatically launch at `http://localhost:8080`.

### Option B: On your Phone (Android / iPhone)
- **Android**:
  1. Open Google Chrome or Microsoft Edge.
  2. If using PC server: Open `http://<your-pc-ip>:8080`.
  3. Tap the **Connect** tab -> **Connect via Bluetooth** -> Select **Vitals-Watch**.
  4. Tap the browser menu (⋮) -> **Add to Home screen** to install it as an app!
- **iPhone / iPad**:
  - Apple Safari doesn't support Web Bluetooth natively, but you can either:
    1. Connect via **Wi-Fi** directly (enter `http://192.168.4.1` in the app).
    2. Or use the free **Bluefy** browser from the App Store for native Web Bluetooth support!

### Option C: Free Cloud Hosting (GitHub Pages / Vercel)
Because PulseGuard is 100% client-side (static HTML/CSS/JavaScript), you can drop this folder onto **GitHub Pages**, **Netlify**, or **Vercel** for free. Once published to an HTTPS URL, you can open it on any device in the world, pair with your watch over BLE, or connect via Wi-Fi!

---

## Technical Specifications
- **BLE Service**: `19b10000-e8f2-537e-4f6c-d104768a1214`
- **Vitals Stream**: `19b10001-e8f2-537e-4f6c-d104768a1214` (JSON at 1 Hz)
- **ECG Stream**: `19b10002-e8f2-537e-4f6c-d104768a1214` (16-bit signed telemetry at 25 Hz)
- **Wi-Fi REST Endpoint**: `http://<device-ip>/api/vitals`
