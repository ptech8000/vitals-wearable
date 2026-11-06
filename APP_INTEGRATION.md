# Mobile App Integration Guide (Wi-Fi & BLE)

This document details how any companion mobile or desktop app (Flutter, React Native, Swift, Kotlin, or Web Bluetooth) connects and receives data from the **Vitals Watch** wearable via **Bluetooth Low Energy (BLE)** and **Wi-Fi**.

---

## 1. Bluetooth Low Energy (BLE) Integration

The device runs an active GATT server advertising as **`Vitals-Watch`**.

### Services & Characteristics Overview

| Service / Characteristic | UUID | Type | Description |
|---|---|---|---|
| **Standard Heart Rate Service** | `0x180D` | Service | Standard Bluetooth SIG service (works with standard fitness apps) |
| ↳ Heart Rate Measurement | `0x2A37` | Read / Notify | Byte 0: Flags (`0x06` finger on, `0x00` off), Byte 1: BPM (uint8) |
| **Custom Vitals Service** | `19b10000-e8f2-537e-4f6c-d104768a1214` | Service | High-level vitals streaming and watch control |
| ↳ Live Vitals JSON | `19b10001-e8f2-537e-4f6c-d104768a1214` | Read / Notify | Compact JSON streamed at 1 Hz with all vital signs |
| ↳ Live ECG Stream | `19b10002-e8f2-537e-4f6c-d104768a1214` | Notify | 16-bit signed integer ECG samples streamed at 25 Hz |
| ↳ Wi-Fi Provisioning | `19b10003-e8f2-537e-4f6c-d104768a1214` | Write | Send `SSID:PASSWORD` over BLE to connect watch to home Wi-Fi |

### 1.1 Live Vitals JSON Format (Characteristic `19b10001-...`)
Streamed once per second:
```json
{
  "bpm": 74,
  "spo2": 98,
  "temp": 36.6,
  "ebpm": 73,
  "finger": 1,
  "leads": 0
}
```
- `bpm`: Heart Rate from optical PPG sensor (MAX30102).
- `spo2`: Blood Oxygen Percentage (70–100%).
- `temp`: Calibrated body temperature (°C).
- `ebpm`: Heart Rate calculated from ECG R-peaks (cross-check).
- `finger`: `1` = finger on sensor, `0` = sensor open.
- `leads`: `0` = ECG electrodes connected, `1` = leads off.

### 1.2 Live ECG Stream (Characteristic `19b10002-...`)
- Streamed at 25 Hz.
- Value: 2-byte signed 16-bit integer (`int16_t` little-endian) representing the filtered ECG voltage amplitude.

### 1.3 Wi-Fi Setup via Bluetooth (Characteristic `19b10003-...`)
To connect the watch to home Wi-Fi without having to disconnect the phone's Wi-Fi:
Write a plain UTF-8 string formatted as:
```text
NetworkName:Password123
```
The watch will save the credentials to flash memory, connect, and update its OLED and web server automatically.

---

## 2. Wi-Fi REST API Integration

The app can also connect over Wi-Fi when connected to:
- **Direct Hotspot:** Join Wi-Fi `Vitals-Watch` (password `vitals123`), Base URL: `http://192.168.4.1`
- **Local Network:** Base URL: `http://vitals.local` or the device IP shown on the OLED screen.

### 2.1 Get Live Vitals
```http
GET /api/vitals?since=0
```
Response:
```json
{
  "bpm": 74,
  "spo2": 98,
  "temp": 36.6,
  "finger": true,
  "leads": false,
  "sta": true,
  "rssi": -62,
  "seq": 1420,
  "ebpm": 73,
  "avg": 72,
  "min": 68,
  "max": 85,
  "smin": 97,
  "up": 185,
  "ble": true,
  "ecg": [12, 14, 18, 55, 120, -40, 10]
}
```

### 2.2 Download Historical Log
```http
GET /log.csv
```
Returns a CSV file containing 1 hour of timestamped 5-second measurements:
```csv
time,uptime_s,hr_ppg_bpm,hr_ecg_bpm,spo2_pct,temp_c
2026-11-04 00:30:15,120,74,73,98,36.6
```

### 2.3 Wi-Fi Scan & Provisioning
- `GET /api/scan`: Scans visible 2.4 GHz Wi-Fi networks.
- `POST /api/wifi`: Parameters `ssid=...&pass=...` to connect.
- `GET /api/wifi/status`: Checks current connection status and IP.

---

## 3. Quick Test Using nRF Connect App (Free on iOS & Android)

1. Open **nRF Connect** on your smartphone.
2. Tap **Scan** and look for **`Vitals-Watch`**.
3. Tap **Connect**.
4. You will see:
   - **Heart Rate (`0x180D`)**: Tap the single-down-arrow to enable notifications. Place your finger on the MAX30102 to see live BPM updates.
   - **Unknown Service (`19b10000-...`)**: Expand and enable notifications on characteristic `19b10001-...` to see the live JSON vitals stream!
