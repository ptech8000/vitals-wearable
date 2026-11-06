# Wiring (ESP32-S3 defaults; edit pins in the .ino if different)

All power at **3.3 V**. Share a common **GND**.

## I²C bus (shared by 3 devices)
| Device | VCC | GND | SDA | SCL | Address |
|---|---|---|---|---|---|
| SSD1306 OLED | 3V3 | GND | GPIO8 | GPIO9 | 0x3C |
| MAX30102 | 3V3 | GND | GPIO8 | GPIO9 | 0x57 |
| MLX90614 (GY-906) | 3V3 | GND | GPIO8 | GPIO9 | 0x5A |

(Classic ESP32: SDA = GPIO21, SCL = GPIO22. Keep MAX30102 INT unconnected.)

## AD8232 ECG
| AD8232 | ESP32 |
|---|---|
| 3.3V | 3V3 |
| GND | GND |
| OUTPUT | GPIO4 |
| LO+ | GPIO10 |
| LO- | GPIO11 |
| SDN | leave open (or 3V3) |

Electrodes (3.5 mm cable): red = right arm (RA), yellow = left arm (LA), green = right leg/reference (RL). Place on clean, dry skin.

## Notes
- Don't use ADC2 pins for the ECG once Wi-Fi is on (ADC2 conflicts with Wi-Fi on ESP32); GPIO4 on S3 is ADC1, fine.
- Power from a LiPo battery for true wearable use; avoid wall-powered USB while attached to electrodes (safety).
- Not a medical device; use for research/education only.
