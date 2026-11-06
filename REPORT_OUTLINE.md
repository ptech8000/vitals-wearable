# Development of Smart Wearable Device for Monitoring Vital Signs

## Abstract
Low-cost ESP32-S3 wearable measuring ECG, heart rate, SpO₂ and body temperature, with a smartwatch-style OLED display and a self-hosted, responsive web dashboard (installable PWA) served directly from the device over Wi-Fi (own hotspot or home network). No cloud service is required. Includes ECG filtering with R-peak heart-rate detection, sensor calibration, threshold alerts and timestamped CSV data logging.

## Chapter 1 – Introduction
1.1 Background (chronic disease, remote patient monitoring, IoT in healthcare)
1.2 Problem statement
1.3 Aim and objectives
1.4 Scope and limitations
1.5 Significance

## Chapter 2 – Literature Review
2.1 Vital signs and physiology (ECG, PPG, SpO₂, temperature)
2.2 Existing wearables (Fitbit, Apple Watch, clinical monitors) – include a comparison table (cost, sensors, accuracy, connectivity, privacy)
2.3 Sensing principles: biopotential amplification, photoplethysmography, infrared thermopile
2.4 Communication and hosting options (Wi-Fi, BLE, MQTT, cloud platforms such as ThingSpeak/Firebase vs. on-device web server; justify the edge-hosted choice: privacy, no subscription, works offline)
2.5 Signal processing for ECG/PPG (baseline wander, mains interference, R-peak detection, motion artifacts)
2.6 Research gap

## Chapter 3 – Methodology
3.1 System block diagram: Sensors → ESP32-S3 (250 Hz ECG task + main loop) → OLED / Wi-Fi AP+STA → on-device web server → phone/PC browser
3.2 Component selection (table with costs: ESP32-S3, AD8232, MAX30102, MLX90614, SSD1306, LiPo) and bill of materials
3.3 Circuit design (see WIRING.md) – include a proper schematic
3.4 Firmware design (include flowcharts)
  - 3.4.1 PPG heart rate: beat detection with 4-beat averaging
  - 3.4.2 SpO₂: ratio-of-ratios, SpO₂ = A − B·R, calibrated against a reference oximeter
  - 3.4.3 ECG chain: 250 Hz sampling, moving-average mains-hum rejection (50 Hz), baseline-wander removal, adaptive-threshold R-peak detection, HR from R-R intervals, lead-off detection
  - 3.4.4 Temperature: MLX90614 object temperature plus calibration offset
  - 3.4.5 Alert logic (HR > 120 / < 50 bpm, SpO₂ < 92 %, temperature > 38 °C) – state the source of thresholds
3.5 User interfaces
  - 3.5.1 OLED: home, ECG, session statistics and network pages
  - 3.5.2 Web dashboard: live vitals, ECG trace, trends, status banner, Wi-Fi provisioning tab, tools tab (calibration, CSV export)
  - 3.5.3 Connectivity: always-on hotspot "Vitals-Watch", mDNS (vitals.local), NTP time sync
3.6 Data logging (5 s records, timestamped CSV)
3.7 Enclosure/wearable packaging and power (battery, charging, power budget)

## Chapter 4 – Results and Discussion
4.1 Hardware prototype photos and dashboard/OLED screenshots
4.2 Test procedure (n ≥ 10 subjects, resting vs. after exercise; see VALIDATION_TEMPLATE.md)
4.3 Accuracy: compare with reference (commercial pulse oximeter, clinical thermometer, reference ECG/PPG HR); report mean error, RMSE, Bland–Altman, before and after calibration
4.4 ECG waveform quality: noise, mains rejection effect (before/after filter), motion artifacts, R-peak detection accuracy vs. reference
4.5 PPG vs. ECG heart-rate agreement
4.6 Latency, dashboard refresh and Wi-Fi reliability, power consumption/battery life
4.7 Discussion and limitations (skin-surface vs. core temperature, uncalibrated SpO₂ range, motion sensitivity, not clinically validated)

## Chapter 5 – Conclusion and Recommendations
Summary, contributions, future work (BLE app, push notifications/buzzer, ML arrhythmia detection, HTTPS/authentication, flexible PCB, battery gauge, SD-card logging, regulatory validation)

## References / Appendices
Datasheets, source code, wiring, schematic, ethics/consent forms for human testing, raw test data (CSV).
