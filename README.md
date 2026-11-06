# PulseGuard: ESP32-S3 Biomedical Wearable & Telemetry Platform

[![Hardware](https://img.shields.io/badge/Hardware-ESP32--S3-red.svg)](https://www.espressif.com/)
[![Firmware](https://img.shields.io/badge/Firmware-Arduino%20%2F%20C%2B%2B-blue.svg)](https://www.arduino.cc/)
[![Connectivity](https://img.shields.io/badge/Wireless-BLE%205.0%20%7C%20Wi--Fi%20%7C%20OTA-green.svg)]()
[![Frontend](https://img.shields.io/badge/Dashboard-Progressive%20Web%20App%20(PWA)-orange.svg)]()
[![License](https://img.shields.io/badge/License-MIT-purple.svg)]()

**PulseGuard** is a wearable vital signs monitor and continuous telemetry platform built on the dual-core **ESP32-S3** microcontroller. The system combines multi-modal biomedical sensing (ECG, PPG, $\text{SpO}_2$, and contactless skin temperature) with on-device OLED visualization, low-latency Bluetooth Low Energy (BLE) streaming, and an on-board web server hosting a standalone real-time dashboard.

---

## 🌟 Key Features

### 1. Multi-Modal Biomedical Acquisition
* **Continuous ECG (Electrocardiogram):** Dedicated FreeRTOS task sampling the **AD8232** front-end at **250 Hz** with real-time 50/60 Hz mains hum notch filtration, baseline-wander cancellation, and adaptive R-peak heart rate detection.
* **Photoplethysmography (PPG) & Pulse Oximetry ($\text{SpO}_2$):** **MAX30102** optical sensor measuring arterial pulse and red/infrared absorption ratios for blood oxygen estimation.
* **Precision Contactless Temperature:** **MLX90614** infrared sensor providing calibrated body/skin temperature measurements without physical thermistor drift.
* **On-Wrist OLED Display:** 0.96" SSD1306 (128x64) displaying animated live pulse, heart rate, $\text{SpO}_2$, temperature, ECG sparklines, and connectivity indicators.

### 2. High-Stability Signal Processing
* **Physiological Refractory Blanking:** Rejection of false peaks within 320 ms ($\ge 185\text{ BPM}$ upper bound) to eliminate dicrotic notch ringing and electrical switching transients.
* **8-Beat Trimmed-Mean & Outlier Rejection:** Discards extreme minimum and maximum intervals before averaging to reject motion artifacts.
* **Exponential Moving Average (EMA):** 70/30 smoothing for jitter-free readings on battery power.
* **Boosted Optical Penetration:** Tuned 10 mA LED drive current for high Signal-to-Noise Ratio (SNR) when operating without earth ground sinks.

### 3. Dual-Mode Wireless Telemetry
* **Standard Bluetooth SIG Profiles:**
  * Heart Rate Service (`0x180D`, Char `0x2A37`)
  * Health Thermometer Characteristic (`0x2A1F`)
  * Blood Pressure Measurement (`0x2A35`)
  * Battery Service (`0x180F`, Char `0x2A19`)
* **Custom High-Throughput Service (`19b10000-...`):**
  * 25 Hz streamed filtered ECG waveform
  * 8-byte compact binary telemetry packets for standard Web Bluetooth MTU
  * Over-the-air Wi-Fi credential provisioning via BLE GATT
* **Wi-Fi Telemetry & mDNS Auto-Discovery:**
  * Advertises `_vitalsync._tcp.local` on port 80.
  * REST endpoints: `/vitals` (standard mobile telemetry schema) and `/api/vitals` (ECG buffer + system statistics).

### 4. Over-The-Air (OTA) Wireless Firmware Updates
* **Dual A/B Partition Scheme (`default_8MB` on 16MB Flash):** 3.34 MB application slots with automatic rollback protection.
* **Browser-Based OTA (`/update`):** Drag-and-drop `.bin` firmware flashing from any browser with a live progress bar.
* **ArduinoOTA Support:** Direct wireless flashing from the Arduino IDE or command line.

---

## 🛠️ Hardware Pinout & Wiring

| Peripheral | Module Pin | ESP32-S3 Pin | Voltage | Notes |
| :--- | :--- | :--- | :--- | :--- |
| **SSD1306 OLED** | SDA / SCL | **GPIO 8 / GPIO 9** | 3.3V | $\text{I}^2\text{C}$ Address: `0x3C` |
| **MAX30102 PPG** | SDA / SCL | **GPIO 8 / GPIO 9** | 3.3V | $\text{I}^2\text{C}$ Address: `0x57` |
| **MLX90614 IR Temp** | SDA / SCL | **GPIO 8 / GPIO 9** | 3.3V | $\text{I}^2\text{C}$ Address: `0x5A` |
| **AD8232 ECG** | OUTPUT | **GPIO 4** | 3.3V | ADC1 Analog Input (250 Hz FreeRTOS task) |
| **AD8232 ECG** | LO+ / LO- | **GPIO 10 / GPIO 11** | 3.3V | Leads-off fault detection |
| **All Modules** | VCC / GND | **3V3 / GND** | 3.3V | Common regulated power rail |

---

## 📁 Repository Structure

```text
vitals-wearable/
├── vitals-wearable.ino       # ESP32-S3 complete firmware (FreeRTOS, Sensors, BLE, Wi-Fi, OTA)
├── vitals-app/               # PulseGuard Companion Web Application
│   ├── index.html            # Responsive telemetry dashboard (PWA)
│   ├── app.js                # Web Bluetooth & REST streaming engine
│   ├── styles.css            # Dark glassmorphism UI theme
│   ├── server.py             # Local HTTP server with auto-discovery
│   ├── start-app.bat         # One-click Windows application launcher
│   └── sw.js / manifest.json # Offline service worker & PWA manifest
├── images/                   # Circuit schematics and prototype photos
├── WIRING.md                 # Detailed electrical wiring & hardware build guide
├── APP_INTEGRATION.md        # BLE GATT specifications & REST API schema
└── README.md                 # Project documentation
```

---

## 🚀 Getting Started

### 1. Compiling & Flashing Firmware
Install the ESP32 board package in Arduino IDE or via `arduino-cli`:

```bash
# Required libraries:
# Adafruit SSD1306, Adafruit GFX, Adafruit MLX90614, SparkFun MAX3010x, ArduinoOTA

# Compile with dual OTA partitions:
arduino-cli compile --fqbn esp32:esp32:esp32s3:PartitionScheme=default_8MB,FlashSize=16M .

# Upload to ESP32-S3:
arduino-cli upload -p COMx --fqbn esp32:esp32:esp32s3:PartitionScheme=default_8MB,FlashSize=16M .
```

### 2. Launching the Web Companion App
Run `start-app.bat` inside `vitals-app/`, or serve the folder using any HTTP server:
```bash
cd vitals-app
python server.py
```
Open `http://localhost:8000` in Google Chrome or Microsoft Edge to connect via **Web Bluetooth** or **Wi-Fi REST**.

### 3. Performing Wireless OTA Updates
1. Navigate to `http://<watch-ip>/update` in your browser.
2. Select the compiled `.bin` file.
3. Click **Upload & Flash**. The watch will update and reboot automatically.

---

## ⚖️ License & Disclaimer

This project is licensed under the MIT License.

> **Disclaimer:** PulseGuard is an experimental open-source engineering platform intended for educational, research, and hobbyist development. It is **not** a certified medical diagnostic device.
