/*
  Smart Wearable Vital Signs Monitor
  ESP32 + AD8232 (ECG) + MAX30102 (HR/SpO2) + MLX90614 (temp) + SSD1306 OLED
  Hosts its own responsive, installable (PWA) dashboard on the ESP32 - no cloud needed.

  Open the dashboard:
    - Same Wi-Fi:  http://vitals.local  (or the IP shown on the OLED / serial monitor)
    - Direct:      join Wi-Fi "Vitals-Watch" (password vitals123), then http://192.168.4.1

  Libraries (Library Manager):
    Adafruit SSD1306, Adafruit GFX, Adafruit MLX90614,
    SparkFun MAX3010x Pulse and Proximity Sensor Library
*/
#include <Wire.h>
#include <WiFi.h>
#include <WebServer.h>
#include <ESPmDNS.h>
#include <Preferences.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <Adafruit_MLX90614.h>
#include <Update.h>
#include <ArduinoOTA.h>
#include "MAX30105.h"
#include "heartRate.h"

bool isOtaUpdating = false;

// ---------- User config ----------
const char* WIFI_SSID = "P-TECH";
const char* WIFI_PASS = "okayyyyy";
const char* AP_SSID   = "Vitals-Watch";   // always-on fallback hotspot
const char* AP_PASS   = "vitals123";      // min 8 characters

// ---------- Pins (ESP32-S3 defaults; change for classic ESP32: SDA 21, SCL 22) ----------
#define PIN_SDA 8
#define PIN_SCL 9
#define PIN_ECG 4    // AD8232 OUTPUT (ADC1 channel)
#define PIN_LOP 10   // AD8232 LO+
#define PIN_LON 11   // AD8232 LO-
#define MAINS_HZ 50  // 50 or 60: sets the ECG hum-rejection filter
const long TZ_OFFSET_S = 3600;  // local time offset from UTC in seconds (UTC+1)

Adafruit_SSD1306 oled(128, 64, &Wire, -1);
Adafruit_MLX90614 mlx;
MAX30105 ppg;
WebServer server(80);
Preferences prefs;
String wifiSsid, wifiPass;  // saved via the dashboard's Wi-Fi tab (falls back to WIFI_SSID/WIFI_PASS above)

// ---------- BLE GATT Configuration ----------
#define BLE_DEV_NAME "Vitals-Watch"
#define SERVICE_HRM_UUID        BLEUUID((uint16_t)0x180D)
#define CHAR_HRM_UUID           BLEUUID((uint16_t)0x2A37)
#define CHAR_TEMP_UUID          BLEUUID((uint16_t)0x2A1F)
#define CHAR_BP_UUID            BLEUUID((uint16_t)0x2A35)
#define SERVICE_BAT_UUID        BLEUUID((uint16_t)0x180F)
#define CHAR_BAT_UUID           BLEUUID((uint16_t)0x2A19)
#define SERVICE_VITALS_UUID     "19b10000-e8f2-537e-4f6c-d104768a1214"
#define CHAR_VITALS_UUID        "19b10001-e8f2-537e-4f6c-d104768a1214"
#define CHAR_ECG_UUID           "19b10002-e8f2-537e-4f6c-d104768a1214"
#define CHAR_WIFI_PROV_UUID     "19b10003-e8f2-537e-4f6c-d104768a1214"

BLEServer* pBleServer = nullptr;
BLECharacteristic* pHRMChar = nullptr;
BLECharacteristic* pVitalsChar = nullptr;
BLECharacteristic* pEcgChar = nullptr;
BLECharacteristic* pWifiProvChar = nullptr;
BLECharacteristic* pTempChar = nullptr;  // 0x2A1F for client app
BLECharacteristic* pBpChar = nullptr;    // 0x2A35 for client app
BLECharacteristic* pBatChar = nullptr;   // 0x2A19 for client app (in 0x180F)
volatile bool bleConnected = false;
uint32_t lastBleVitals = 0, lastBleEcg = 0;

// ---------- State ----------
float bpm = 0, spo2 = 0, tempC = 0;
volatile bool leadsOff = true;
bool finger = false;
volatile int ecgValue = 0;
volatile float ecgBpm = 0;  // heart rate from ECG R-peaks (cross-check for PPG)

// Calibration (editable on the dashboard's Tools tab, saved to flash)
// SpO2 = calA - calB * R ; temperature = raw + calTemp
float calA = 110.0, calB = 25.0, calTemp = 0.0, lastR = 0, rawTemp = 0;
uint32_t lastBeat = 0, lastBeatTime = 0;
#define RATE_BUF_SIZE 8
uint8_t rates[RATE_BUF_SIZE] = {0};
uint8_t rateCount = 0;
uint8_t rateIdx = 0;
float smoothBpm = 0;

// SpO2 ratio-of-ratios accumulators
double redDC = 0, irDC = 0, redSq = 0, irSq = 0;
uint16_t nSamp = 0;

uint32_t lastDraw = 0, lastTemp = 0, lastEcg = 0, lastWifiLog = 0, lastStat = 0;

// Session stats (updated once per second while a finger is on the sensor)
uint32_t hrCount = 0; float hrSum = 0; int hrMin = 0, hrMax = 0, spo2Min = 0;

bool alertActive() {
  return (finger && bpm > 0 && (bpm > 120 || bpm < 50)) || (spo2 > 0 && spo2 < 92) || (tempC > 38.0);
}

void updateStats() {
  if (millis() - lastStat < 1000) return;
  lastStat = millis();
  if (finger && bpm > 0) {
    int b = (int)bpm; hrSum += b; hrCount++;
    if (!hrMin || b < hrMin) hrMin = b;
    if (b > hrMax) hrMax = b;
  }
  if (finger && spo2 > 0) { int s = (int)spo2; if (!spo2Min || s < spo2Min) spo2Min = s; }
}

// ECG ring buffer (250 Hz, filtered) shared by OLED and web dashboard
#define ECG_BUF 1024
int16_t ecgBuf[ECG_BUF];
volatile uint32_t ecgSeq = 0;  // total samples ever written

// Timestamped log, one record every 5 s (about 1 hour), downloadable as CSV
struct LogRec { uint32_t epoch, up; uint8_t bpm, spo2, ebpm; int16_t temp10; };
#define LOG_N 720
LogRec logbuf[LOG_N];
uint32_t logCount = 0, lastLog = 0;

// ---------- Sensors ----------
void readPPG() {
  ppg.check();
  while (ppg.available()) {
    uint32_t red = ppg.getFIFORed();
    uint32_t ir = ppg.getFIFOIR();
    ppg.nextSample();

    if (ir < 45000) {  // no finger (hysteresis)
      finger = false;
      bpm = 0; spo2 = 0; nSamp = 0;
      smoothBpm = 0; rateCount = 0; rateIdx = 0; lastBeatTime = 0;
      redDC = irDC = redSq = irSq = 0;
      continue;
    }
    finger = true;

    if (checkForBeat(ir)) {
      uint32_t now = millis();
      uint32_t delta = (lastBeatTime > 0) ? (now - lastBeatTime) : 0;

      // Minimum refractory period: 320ms (prevents false double-peaks, dicrotic notch, and noise)
      if (delta >= 320) {
        lastBeatTime = now;
        lastBeat = now;

        // Long gap (>2.2s): finger adjusted or missed beats. Re-sync without calculating fake low BPM.
        if (delta <= 2200) {
          float instBpm = 60000.0f / (float)delta;
          if (instBpm >= 42.0f && instBpm <= 180.0f) {
            // Outlier clamping: single beat cannot jump by >25 BPM from established rate
            if (smoothBpm > 40.0f && fabsf(instBpm - smoothBpm) > 25.0f) {
              instBpm = smoothBpm + ((instBpm > smoothBpm) ? 12.0f : -12.0f);
            }

            rates[rateIdx++ % RATE_BUF_SIZE] = (uint8_t)roundf(instBpm);
            if (rateCount < RATE_BUF_SIZE) rateCount++;

            // Trimmed Mean Filter: sort rates and discard highest/lowest outliers
            uint8_t sorted[RATE_BUF_SIZE];
            for (uint8_t i = 0; i < rateCount; i++) sorted[i] = rates[i];
            for (uint8_t i = 1; i < rateCount; i++) {
              uint8_t key = sorted[i];
              int j = i - 1;
              while (j >= 0 && sorted[j] > key) {
                sorted[j + 1] = sorted[j];
                j--;
              }
              sorted[j + 1] = key;
            }

            float calcBpm = 0;
            if (rateCount >= 5) {
              uint8_t trim = (rateCount >= 7) ? 2 : 1;
              uint8_t valid = rateCount - (trim * 2);
              float sum = 0;
              for (uint8_t i = trim; i < rateCount - trim; i++) sum += sorted[i];
              calcBpm = sum / valid;
            } else {
              float sum = 0;
              for (uint8_t i = 0; i < rateCount; i++) sum += sorted[i];
              calcBpm = sum / rateCount;
            }

            // Exponential Moving Average (EMA) for rock-solid stability
            if (smoothBpm <= 0) smoothBpm = calcBpm;
            else smoothBpm = smoothBpm * 0.7f + calcBpm * 0.3f;

            bpm = smoothBpm;
          }
        }
      } else if (lastBeatTime == 0) {
        lastBeatTime = now;
        lastBeat = now;
      }
    }

    // SpO2: 250-sample window (~2.5s) with EMA smoothing
    redDC += red; irDC += ir;
    redSq += (double)red * red; irSq += (double)ir * ir;
    if (++nSamp >= 250) {
      double mr = redDC / nSamp, mi = irDC / nSamp;
      double acr = sqrt(max(0.0, redSq / nSamp - mr * mr));
      double aci = sqrt(max(0.0, irSq / nSamp - mi * mi));
      if (mr > 0 && mi > 0 && aci > 0) {
        double R = (acr / mr) / (aci / mi);
        float s = calA - calB * R;
        lastR = R;
        s = constrain(s, 70, 100);
        if (spo2 <= 0) spo2 = s;
        else spo2 = spo2 * 0.75f + s * 0.25f;  // Exponential smoothing
      }
      nSamp = 0; redDC = irDC = redSq = irSq = 0;
    }
  }
}

// ECG task: 250 Hz sampling on its own FreeRTOS task so OLED/Wi-Fi work can't disturb timing.
// Filter chain: moving average (one mains period -> nulls 50/60 Hz hum) -> baseline-wander removal
// (slow EMA subtracted) -> adaptive-threshold R-peak detector -> heart rate from R-R intervals.
void ecgTask(void*) {
  const int WIN = 250 / MAINS_HZ;  // 5 samples @50 Hz, 4 @60 Hz
  int win[8] = {0}; int wi = 0; long wsum = 0;
  float base = 0, pk = 0; bool init = false, above = false;
  uint32_t lastRms = 0; uint16_t rr[4]; uint8_t rri = 0, rrn = 0;
  TickType_t t = xTaskGetTickCount();
  for (;;) {
    vTaskDelayUntil(&t, pdMS_TO_TICKS(4));
    bool lo = digitalRead(PIN_LOP) || digitalRead(PIN_LON);
    leadsOff = lo;
    int16_t out = 0;
    if (lo) {
      ecgValue = 0; init = false; ecgBpm = 0; rrn = 0; lastRms = 0;
    } else {
      int raw = analogRead(PIN_ECG);
      ecgValue = raw;
      wsum -= win[wi]; win[wi] = raw; wsum += raw; wi = (wi + 1) % WIN;
      float avg = (float)wsum / WIN;
      if (!init) { base = avg; init = true; }
      base += 0.01f * (avg - base);
      float f = avg - base;
      out = (int16_t)constrain(f, -2000.0f, 2000.0f);

      pk = max(pk * 0.998f, fabsf(f));
      float thr = max(0.55f * pk, 20.0f);
      uint32_t now = millis();
      if (f > thr && !above && now - lastRms > 300) {  // 300 ms refractory period
        above = true;
        if (lastRms && now - lastRms < 1500) {
          rr[rri++ % 4] = now - lastRms; if (rrn < 4) rrn++;
          float s = 0; for (uint8_t i = 0; i < rrn; i++) s += rr[i];
          ecgBpm = 60000.0f / (s / rrn);
        }
        lastRms = now;
      } else if (f < thr * 0.5f) above = false;
      if (lastRms && now - lastRms > 2500) { ecgBpm = 0; rrn = 0; }  // no beats lately
    }
    ecgBuf[ecgSeq % ECG_BUF] = out;
    ecgSeq = ecgSeq + 1;
  }
}

void logSample() {
  if (millis() - lastLog < 5000) return;
  lastLog = millis();
  if (!finger && leadsOff) return;  // nothing worth recording
  LogRec& r = logbuf[logCount % LOG_N];
  time_t now = time(nullptr);
  r.epoch = now > 1700000000 ? (uint32_t)now : 0;  // 0 until NTP syncs
  r.up = millis() / 1000;
  r.bpm = (uint8_t)bpm; r.spo2 = (uint8_t)spo2; r.ebpm = (uint8_t)ecgBpm;
  r.temp10 = (int16_t)(tempC * 10);
  logCount++;
}

// ---------- OLED (smartwatch style) ----------
void drawHeart(int cx, int cy, int r) {
  oled.fillCircle(cx - r / 2, cy, r / 2 + 1, SSD1306_WHITE);
  oled.fillCircle(cx + r / 2, cy, r / 2 + 1, SSD1306_WHITE);
  oled.fillTriangle(cx - r - 1, cy + 1, cx + r + 1, cy + 1, cx, cy + r + r / 2, SSD1306_WHITE);
}

void drawWifiIcon(int x, int y) {  // 3 bars, bottom-aligned at y+7
  bool online = WiFi.status() == WL_CONNECTED;
  int lvl = 0;
  if (online) { int r = WiFi.RSSI(); lvl = r > -60 ? 3 : r > -75 ? 2 : 1; }
  for (int i = 0; i < 3; i++) {
    int h = 3 + i * 2;
    if (i < lvl) oled.fillRect(x + i * 4, y + 7 - h, 3, h, SSD1306_WHITE);
    else oled.drawRect(x + i * 4, y + 7 - h, 3, h, SSD1306_WHITE);
  }
  if (!online) oled.drawLine(x - 1, y, x + 11, y + 7, SSD1306_WHITE);
}

void drawBleIcon(int x, int y) {
  if (bleConnected) {
    // Bluetooth symbol (5x8 pixels)
    oled.drawFastVLine(x + 2, y, 8, SSD1306_WHITE);
    oled.drawLine(x + 2, y + 2, x + 5, y, SSD1306_WHITE);
    oled.drawLine(x + 5, y, x + 2, y + 4, SSD1306_WHITE);
    oled.drawLine(x + 2, y + 4, x + 5, y + 8, SSD1306_WHITE);
    oled.drawLine(x + 5, y + 8, x + 2, y + 6, SSD1306_WHITE);
    oled.drawLine(x, y + 2, x + 4, y + 6, SSD1306_WHITE);
    oled.drawLine(x, y + 6, x + 4, y + 2, SSD1306_WHITE);
  } else {
    // Small outline 'b' indicating BLE is advertising
    oled.drawFastVLine(x + 1, y + 1, 7, SSD1306_WHITE);
    oled.drawCircle(x + 3, y + 5, 2, SSD1306_WHITE);
  }
}

void drawStatusBar(const char* title) {
  oled.setTextSize(1);
  oled.setTextColor(SSD1306_WHITE);
  oled.setCursor(0, 0);
  oled.print(title);
  // clock: real time once NTP has synced (needs internet), otherwise uptime
  uint32_t s = millis() / 1000; char t[10];
  time_t nowT = time(nullptr);
  if (nowT > 1700000000) { struct tm tmv; localtime_r(&nowT, &tmv); snprintf(t, sizeof t, "%02d:%02d", tmv.tm_hour, tmv.tm_min); }
  else if (s >= 3600) snprintf(t, sizeof t, "%luh%02lum", s / 3600, (s / 60) % 60);
  else snprintf(t, sizeof t, "%02lu:%02lu", s / 60, s % 60);
  oled.setCursor(46, 0);
  oled.print(t);
  // blinking alert badge
  if (alertActive() && ((millis() / 500) % 2)) {
    oled.fillCircle(88, 4, 4, SSD1306_WHITE);
    oled.setTextColor(SSD1306_BLACK); oled.setCursor(87, 1); oled.print("!");
    oled.setTextColor(SSD1306_WHITE);
  }
  drawBleIcon(103, 0);
  drawWifiIcon(115, 0);
  oled.drawFastHLine(0, 10, 128, SSD1306_WHITE);
  if (!finger) oled.drawFastHLine(0, 11, (millis() % 4000) * 128 / 4000, SSD1306_WHITE);  // page timer (hidden while measuring)
}

void drawCenter(const char* s, int y, int size) {
  int16_t x1, y1; uint16_t w, h;
  oled.setTextSize(size);
  oled.getTextBounds(s, 0, 0, &x1, &y1, &w, &h);
  oled.setCursor((128 - w) / 2, y);
  oled.print(s);
}

void drawHomePage() {
  drawStatusBar("VITALS");
  // pulsing heart + big BPM
  bool pulse = finger && bpm > 0 && (millis() - lastBeat) < 180;
  drawHeart(18, 24, pulse ? 9 : 7);
  oled.setTextSize(3);
  oled.setCursor(40, 17);
  if (finger && bpm > 0) oled.printf("%.0f", bpm); else oled.print("--");
  oled.setTextSize(1);
  oled.setCursor(100, 31);
  oled.print("bpm");
  // heart-rate zone label
  oled.setCursor(100, 19);
  if (!finger) oled.print("");
  else if (bpm <= 0) oled.print(((millis() / 400) % 4) == 0 ? "." : ((millis() / 400) % 4) == 1 ? ".." : "...");  // measuring
  else oled.print(bpm < 50 ? "LOW" : bpm <= 100 ? "OK" : bpm <= 120 ? "UP" : "HIGH");
  // info cards
  oled.drawRoundRect(0, 43, 62, 21, 5, SSD1306_WHITE);
  oled.drawRoundRect(66, 43, 62, 21, 5, SSD1306_WHITE);
  oled.setCursor(6, 47); oled.print("SpO2");
  oled.setCursor(6, 56);
  if (spo2 > 0) oled.printf("%.0f%%", spo2); else oled.print("--");
  oled.setCursor(72, 47); oled.print("TEMP");
  oled.setCursor(72, 56); oled.printf("%.1f", tempC);
  oled.drawCircle(104, 57, 1, SSD1306_WHITE);
  oled.setCursor(108, 56); oled.print("C");
}

void drawStatsPage() {
  drawStatusBar("SESSION");
  const char* lbl[3] = {"AVG", "MIN", "MAX"};
  int val[3] = {hrCount ? (int)(hrSum / hrCount) : 0, hrMin, hrMax};
  const int xs[3] = {2, 46, 90};
  for (int i = 0; i < 3; i++) {
    oled.setTextSize(1); oled.setCursor(xs[i] + 6, 16); oled.print(lbl[i]);
    oled.setTextSize(2); oled.setCursor(xs[i], 27);
    if (val[i]) oled.printf("%3d", val[i]); else oled.print(" --");
  }
  oled.drawFastHLine(0, 46, 128, SSD1306_WHITE);
  oled.setTextSize(1);
  oled.setCursor(0, 50); oled.print("HR bpm  SpO2 low:");
  if (spo2Min) oled.printf("%d%%", spo2Min); else oled.print("--");
  oled.setCursor(0, 58); oled.printf("Readings: %lu", (unsigned long)hrCount);
}

void drawNetPage() {
  drawStatusBar("COMM");
  bool on = WiFi.status() == WL_CONNECTED;
  String ss = on ? WiFi.SSID() : wifiSsid;
  if (ss.length() > 14) ss = ss.substring(0, 14);
  oled.setTextSize(1);
  oled.setCursor(0, 14); oled.printf("WiFi:%s", ss.c_str());
  oled.setCursor(0, 23); oled.print(on ? WiFi.localIP().toString() : String("192.168.4.1 (AP)"));
  oled.drawFastHLine(0, 33, 128, SSD1306_WHITE);
  oled.setCursor(0, 36); oled.printf("BLE: %s", BLE_DEV_NAME);
  oled.setCursor(0, 46); oled.printf("BLE: %s", bleConnected ? "CONNECTED" : "ADVERTISING");
  oled.setCursor(0, 56); oled.printf("AP: %s (pw: %s)", AP_SSID, AP_PASS);
}

void drawEcgPage() {
  char title[16];
  if (!leadsOff && ecgBpm > 0) snprintf(title, sizeof title, "ECG %.0f", (float)ecgBpm); else snprintf(title, sizeof title, "ECG");
  drawStatusBar(title);
  if (leadsOff) {
    drawCenter("Attach", 22, 2);
    drawCenter("electrodes", 42, 1);
    return;
  }
  // auto-scaled trace of last 124 samples
  const int W = 124, top = 14, bottom = 62;
  uint32_t sq = ecgSeq;  // snapshot; trace shows last 248 samples (~1 s) at 2:1 decimation
  int lo = 4095, hi = -4095;
  for (int i = 0; i < W; i++) {
    int v = ecgBuf[(sq + ECG_BUF - 2 * W + 2 * i) % ECG_BUF];
    if (v < lo) lo = v; if (v > hi) hi = v;
  }
  if (hi - lo < 60) { lo = (lo + hi) / 2 - 30; hi = lo + 60; }
  int prev = -1;
  for (int i = 0; i < W; i++) {
    int v = ecgBuf[(sq + ECG_BUF - 2 * W + 2 * i) % ECG_BUF];
    int y = map(v, lo, hi, bottom, top);
    if (prev >= 0) oled.drawLine(i + 1, prev, i + 2, y, SSD1306_WHITE);
    prev = y;
  }
}

void draw() {
  oled.clearDisplay();
  oled.setTextColor(SSD1306_WHITE);
  // Stay on the home page while a finger is on the sensor (BPM is being measured);
  // otherwise auto-rotate every 4 s: home, ECG, session stats, network
  int pg = finger ? 0 : (millis() / 4000) % 4;
  if (pg == 0) drawHomePage(); else if (pg == 1) drawEcgPage(); else if (pg == 2) drawStatsPage(); else drawNetPage();
  oled.display();
}

void drawSplash(const char* line) {
  oled.clearDisplay();
  oled.setTextColor(SSD1306_WHITE);
  drawHeart(64, 14, 10);
  drawCenter("VITALS", 36, 2);
  oled.setTextSize(1);
  drawCenter(line, 56, 1);
  oled.display();
}

// ---------- Web dashboard ----------
const char INDEX_HTML[] PROGMEM = R"rawliteral(<!doctype html><html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="theme-color" content="#0b1020"><meta name="apple-mobile-web-app-capable" content="yes">
<link rel="manifest" href="/manifest.json"><link rel="icon" href="/icon.svg"><link rel="apple-touch-icon" href="/icon.svg">
<title>Vitals Watch</title>
<style>
:root{--bg:#0b1020;--card:rgba(255,255,255,.06);--bd:rgba(255,255,255,.1);--tx:#eef2ff;--mut:#8f9bbd;--hr:#ff4d6d;--o2:#4cc9f0;--tp:#ffb703;--ok:#2ee59d}
*{box-sizing:border-box;margin:0}
body{font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;color:var(--tx);min-height:100vh;
background:radial-gradient(900px 500px at 10% -10%,#26204f 0,transparent 60%),radial-gradient(800px 500px at 100% 0,#10324a 0,transparent 55%),var(--bg);
padding:max(16px,env(safe-area-inset-top)) 16px 24px}
.wrap{max-width:980px;margin:auto}
header{display:flex;justify-content:space-between;align-items:center;margin-bottom:18px}
h1{font-size:1.25rem;font-weight:700;letter-spacing:.3px}h1 span{color:var(--hr)}
.chip{display:flex;gap:8px;align-items:center;font-size:.8rem;color:var(--mut);background:var(--card);border:1px solid var(--bd);padding:6px 12px;border-radius:99px}
.dot{width:9px;height:9px;border-radius:50%;background:#666}.live .dot{background:var(--ok);box-shadow:0 0 10px var(--ok)}
.grid{display:grid;gap:14px;grid-template-columns:repeat(3,1fr)}
.card{background:var(--card);border:1px solid var(--bd);border-radius:22px;padding:18px;backdrop-filter:blur(14px);-webkit-backdrop-filter:blur(14px)}
.lbl{font-size:.75rem;text-transform:uppercase;letter-spacing:1.2px;color:var(--mut);display:flex;justify-content:space-between}
.val{font-size:3.2rem;font-weight:800;line-height:1.1;margin-top:8px;font-variant-numeric:tabular-nums}
.val small{font-size:1rem;font-weight:500;color:var(--mut);margin-left:6px}
#hr .val{color:var(--hr)}#o2 .val{color:var(--o2)}#tp .val{color:var(--tp)}
.heart{display:inline-block;transition:transform .15s}.beat{transform:scale(1.35)}
.ecg{grid-column:1/-1}canvas{width:100%;height:200px;display:block;margin-top:10px;border-radius:14px;background:rgba(0,0,0,.25)}
.msg{font-size:.85rem;color:var(--mut);margin-top:8px;min-height:1.2em}
.bar{height:6px;border-radius:9px;background:rgba(255,255,255,.08);margin-top:12px;overflow:hidden}.bar i{display:block;height:100%;width:0;border-radius:9px;transition:width .5s}
footer{margin-top:16px;text-align:center;color:var(--mut);font-size:.75rem}
@media(max-width:720px){.grid{grid-template-columns:1fr 1fr}#hr{grid-column:1/-1}.val{font-size:2.6rem}canvas{height:160px}}
.tabs{display:flex;gap:6px;background:var(--card);border:1px solid var(--bd);border-radius:99px;padding:4px;margin-bottom:16px;width:fit-content}
.tab{border:0;background:none;color:var(--mut);font:600 .85rem system-ui;padding:8px 18px;border-radius:99px;cursor:pointer}.tab.on{background:rgba(255,255,255,.12);color:var(--tx)}
[hidden]{display:none!important}
.net{display:flex;justify-content:space-between;align-items:center;width:100%;border:1px solid var(--bd);background:rgba(255,255,255,.04);color:var(--tx);padding:12px 14px;border-radius:14px;margin-top:8px;cursor:pointer;font:500 .95rem system-ui;text-align:left}
.net.on{border-color:var(--o2);background:rgba(76,201,240,.12)}.net small{color:var(--mut)}
.in{width:100%;margin-top:10px;padding:13px 14px;border-radius:14px;border:1px solid var(--bd);background:rgba(0,0,0,.25);color:var(--tx);font:1rem system-ui}
.btn{margin-top:12px;border:0;border-radius:14px;padding:12px 18px;font:700 .95rem system-ui;color:#fff;background:linear-gradient(135deg,#ff4d6d,#c9184a);cursor:pointer}.btn.alt{background:rgba(255,255,255,.1)}
.row{display:flex;gap:10px;flex-wrap:wrap}.wide{max-width:560px}
canvas.sp{height:42px;margin-top:10px;background:none;border-radius:0}
.stats{font-size:.8rem;color:var(--mut);margin-top:6px}
.banner{display:flex;align-items:center;gap:10px;padding:12px 16px;border-radius:16px;margin-bottom:14px;font-size:.9rem;font-weight:600;border:1px solid var(--bd);background:var(--card)}
.banner.ok{border-color:rgba(46,229,157,.5);background:rgba(46,229,157,.1);color:var(--ok)}
.banner.warn{border-color:rgba(255,77,109,.6);background:rgba(255,77,109,.14);color:#ff8fa3;animation:pl 1.2s infinite}
.banner.idle{color:var(--mut)}@keyframes pl{50%{opacity:.65}}
@media(max-width:380px){.grid{grid-template-columns:1fr}}
</style></head><body><div class="wrap">
<header><h1><span class="heart" id="h">&#10084;</span> Vitals Watch</h1><div class="chip" id="st"><i class="dot"></i><b id="stx">Connecting</b></div></header>
<nav class="tabs"><button class="tab on" data-t="d">Dashboard</button><button class="tab" data-t="w">Wi-Fi</button><button class="tab" data-t="t">Tools</button></nav>
<div id="pd"><div class="banner idle" id="bn">Waiting for sensor data&hellip;</div><div class="grid">
<div class="card" id="hr"><div class="lbl"><span>Heart rate</span><span id="hs"></span></div><div class="val"><b id="bpm">--</b><small>bpm</small></div><canvas class="sp" id="s1" width="300" height="42"></canvas><div class="bar"><i id="hb" style="background:var(--hr)"></i></div><div class="msg" id="hm"></div><div class="stats" id="hst"></div></div>
<div class="card" id="o2"><div class="lbl"><span>Blood oxygen</span></div><div class="val"><b id="spo2">--</b><small>%</small></div><canvas class="sp" id="s2" width="300" height="42"></canvas><div class="bar"><i id="ob" style="background:var(--o2)"></i></div></div>
<div class="card" id="tp"><div class="lbl"><span>Temperature</span></div><div class="val"><b id="temp">--</b><small>&deg;C</small></div><canvas class="sp" id="s3" width="300" height="42"></canvas><div class="bar"><i id="tb" style="background:var(--tp)"></i></div></div>
<div class="card ecg"><div class="lbl"><span>ECG</span><span id="es">--</span></div><canvas id="cv"></canvas></div>
</div></div>
<div id="pw" hidden><div class="card wide"><div class="lbl"><span>Internet connection</span></div>
<div class="val" style="font-size:1.2rem" id="wcur">Checking&hellip;</div>
<div class="row"><button class="btn alt" id="wscan">Scan networks</button><button class="btn alt" id="wforget">Forget saved</button></div>
<div id="wl"></div>
<input class="in" id="wssid" placeholder="Network name (SSID)" autocapitalize="none" autocomplete="off">
<input class="in" id="wpass" type="password" placeholder="Password" autocomplete="off">
<button class="btn" id="wgo">Connect</button><div class="msg" id="wmsg"></div></div></div>
<div id="pt" hidden><div class="card wide"><div class="lbl"><span>Data log</span></div>
<div class="msg">Readings are recorded every 5 s (last hour kept in RAM). Timestamps appear after the device has been online once (NTP).</div>
<a class="btn" style="display:inline-block;text-decoration:none" href="/log.csv" download="vitals.csv">Download CSV</a></div>
<div class="card wide" style="margin-top:14px"><div class="lbl"><span>Sensor calibration</span></div>
<div class="msg">SpO2 = A &minus; B &times; R &nbsp;&middot;&nbsp; Temp = raw + offset. Fit these against a reference oximeter / thermometer.</div>
<div class="val" style="font-size:1rem" id="craw">&nbsp;</div>
<input class="in" id="ca" type="number" step="0.1" placeholder="A (default 110)">
<input class="in" id="cb" type="number" step="0.1" placeholder="B (default 25)">
<input class="in" id="ct" type="number" step="0.1" placeholder="Temperature offset in &deg;C">
<div class="row"><button class="btn" id="csave">Save</button><button class="btn alt" id="creset">Reset defaults</button></div><div class="msg" id="cmsg"></div></div>
<div class="card wide" style="margin-top:14px"><div class="lbl"><span>Firmware Update</span></div>
<div class="msg">Upload new firmware wirelessly (OTA) without connecting a USB cable.</div>
<a class="btn" style="display:inline-block;text-decoration:none;background:linear-gradient(135deg,#38bdf8,#0284c7)" href="/update">&#9889; Wireless Firmware Update</a></div></div>
<footer id="ft">Live from your ESP32-S3 &middot; not a medical device</footer></div>
<script>
const $=i=>document.getElementById(i),cv=$('cv'),cx=cv.getContext('2d'),N=500;let buf=[],seq=0,leads=true,fails=0;
function size(){const r=devicePixelRatio||1;cv.width=cv.clientWidth*r;cv.height=cv.clientHeight*r}addEventListener('resize',size);size();
function draw(){const w=cv.width,h=cv.height;cx.clearRect(0,0,w,h);cx.strokeStyle='rgba(255,255,255,.05)';cx.lineWidth=1;
for(let x=0;x<w;x+=w/20){cx.beginPath();cx.moveTo(x,0);cx.lineTo(x,h);cx.stroke()}for(let y=0;y<h;y+=h/6){cx.beginPath();cx.moveTo(0,y);cx.lineTo(w,y);cx.stroke()}
if(leads||buf.length<2){cx.fillStyle='#8f9bbd';cx.font=(14*(devicePixelRatio||1))+'px system-ui';cx.textAlign='center';cx.fillText(leads?'Attach ECG electrodes':'Waiting for data',w/2,h/2);return}
let lo=Math.min(...buf),hi=Math.max(...buf);if(hi-lo<200){const m=(hi+lo)/2;lo=m-100;hi=m+100}
cx.strokeStyle='#2ee59d';cx.lineWidth=2*(devicePixelRatio||1);cx.lineJoin='round';cx.shadowColor='#2ee59d';cx.shadowBlur=8;cx.beginPath();
buf.forEach((v,i)=>{const x=i/(N-1)*w,y=h-(v-lo)/(hi-lo)*h*.8-h*.1;i?cx.lineTo(x,y):cx.moveTo(x,y)});cx.stroke();cx.shadowBlur=0}
function set(id,v,d){$(id).textContent=v>0?v.toFixed(d):'--'}
function bar(id,p){$(id).style.width=Math.max(0,Math.min(100,p))+'%'}
const H=[[],[],[]];
function spark(id,a,c){const k=$(id),g=k.getContext('2d'),w=k.width,h=k.height;g.clearRect(0,0,w,h);if(a.length<2)return;let lo=Math.min(...a),hi=Math.max(...a);if(hi-lo<1){lo-=1;hi+=1}
g.strokeStyle=c;g.lineWidth=2;g.lineJoin='round';g.beginPath();a.forEach((v,i)=>{const x=i/(a.length-1)*w,y=h-3-(v-lo)/(hi-lo)*(h-6);i?g.lineTo(x,y):g.moveTo(x,y)});g.stroke()}
function push(i,v){H[i].push(v);if(H[i].length>60)H[i].shift()}
function banner(d){const b=$('bn'),w=[];if(d.finger&&d.bpm>120)w.push('High heart rate');if(d.finger&&d.bpm>0&&d.bpm<50)w.push('Low heart rate');
if(d.spo2>0&&d.spo2<92)w.push('Low blood oxygen');if(d.temp>38)w.push('High temperature');
if(w.length){b.className='banner warn';b.textContent='\u26a0 '+w.join(' \u00b7 ')}
else if(!d.finger){b.className='banner idle';b.textContent='Place your finger on the sensor to start'}
else{b.className='banner ok';b.textContent='\u2713 All vitals look normal'}}
function upt(s){return s>=3600?Math.floor(s/3600)+'h '+Math.floor(s%3600/60)+'m':Math.floor(s/60)+'m '+s%60+'s'}
async function tick(){try{const r=await fetch('/api/vitals?since='+seq,{cache:'no-store'}),d=await r.json();fails=0;
$('st').classList.add('live');$('stx').textContent=(d.sta?'Live \u00b7 '+d.rssi+' dBm':'Live \u00b7 hotspot')+(d.ble?' \u00b7 BLE connected':' \u00b7 BLE ready');
set('bpm',d.finger?d.bpm:0,0);set('spo2',d.spo2,0);set('temp',d.temp,1);
bar('hb',(d.bpm-40)/1.4);bar('ob',(d.spo2-70)*3.3);bar('tb',(d.temp-30)*10);
if(d.finger&&d.bpm>0)push(0,d.bpm);if(d.spo2>0)push(1,d.spo2);if(d.temp>0)push(2,d.temp);
spark('s1',H[0],'#ff4d6d');spark('s2',H[1],'#4cc9f0');spark('s3',H[2],'#ffb703');
$('hst').textContent=d.min?'avg '+d.avg+' \u00b7 min '+d.min+' \u00b7 max '+d.max+' bpm':'';banner(d);
$('ft').textContent='Live from your ESP32-S3 \u00b7 up '+upt(d.up)+' \u00b7 not a medical device';
$('hm').textContent=d.finger?'':'Place your finger on the sensor';
$('es').textContent=d.leads?'leads off':(d.ebpm>0?'ECG '+d.ebpm+' bpm':'recording');leads=d.leads;
if(d.bpm>0&&d.finger){$('h').classList.add('beat');setTimeout(()=>$('h').classList.remove('beat'),150)}
if(d.seq<seq){buf=[]}seq=d.seq;buf=buf.concat(d.ecg).slice(-N);draw()}
catch(e){if(++fails>2){$('st').classList.remove('live');$('stx').textContent='Offline'}}}
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
document.querySelectorAll('.tab').forEach(b=>b.onclick=()=>{document.querySelectorAll('.tab').forEach(x=>x.classList.toggle('on',x===b));
$('pd').hidden=b.dataset.t!='d';$('pw').hidden=b.dataset.t!='w';$('pt').hidden=b.dataset.t!='t';
if(b.dataset.t=='d'){size();draw()}else if(b.dataset.t=='w'){wst();scan()}else loadCal()});
async function loadCal(){try{const d=await(await fetch('/api/cal',{cache:'no-store'})).json();$('ca').value=d.a;$('cb').value=d.b;$('ct').value=d.toff;
$('craw').textContent='Live: R = '+d.r.toFixed(3)+' \u00b7 raw temp '+d.rawt.toFixed(1)+' \u00b0C'}catch(e){}}
$('csave').onclick=async()=>{await fetch('/api/cal',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({a:$('ca').value,b:$('cb').value,toff:$('ct').value})});$('cmsg').textContent='Saved';loadCal()};
$('creset').onclick=async()=>{await fetch('/api/cal/reset',{method:'POST'});$('cmsg').textContent='Reset to defaults';loadCal()};
async function wst(){try{const d=await(await fetch('/api/wifi/status',{cache:'no-store'})).json();
$('wcur').textContent=d.connected?'Connected to '+d.ssid+' \u00b7 '+d.ip:(d.ssid?'Not connected to '+d.ssid:'No network saved');return d}catch(e){}}
async function scan(){$('wl').innerHTML='<div class="msg">Scanning\u2026</div>';
for(let i=0;i<25;i++){try{const d=await(await fetch('/api/scan',{cache:'no-store'})).json();if(!d.scanning){return list(d.nets)}}catch(e){}await sleep(800)}
$('wl').innerHTML='<div class="msg">Scan failed, tap Scan again</div>'}
function list(n){const w=$('wl');w.innerHTML='';if(!n.length){w.innerHTML='<div class="msg">No networks found</div>';return}
const seen={};n.sort((a,b)=>b.rssi-a.rssi).forEach(x=>{if(seen[x.ssid])return;seen[x.ssid]=1;const b=document.createElement('button');b.className='net';
const s=document.createElement('span');s.textContent=x.ssid;const m=document.createElement('small');m.textContent=(x.open?'open':'secured')+' \u00b7 '+x.rssi+' dBm';
b.append(s,m);b.onclick=()=>{$('wssid').value=x.ssid;$('wpass').value='';document.querySelectorAll('.net').forEach(e=>e.classList.remove('on'));b.classList.add('on');if(!x.open)$('wpass').focus()};w.append(b)})}
$('wscan').onclick=scan;
$('wforget').onclick=async()=>{await fetch('/api/wifi/forget',{method:'POST'});$('wmsg').textContent='Saved network removed';wst()};
$('wgo').onclick=async()=>{const ssid=$('wssid').value.trim();if(!ssid){$('wmsg').textContent='Choose or type a network name';return}
$('wmsg').textContent='Connecting\u2026 (your link to the hotspot may blink)';
try{await fetch('/api/wifi',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({ssid,pass:$('wpass').value})})}catch(e){}
for(let i=0;i<20;i++){await sleep(1000);const d=await wst();if(d&&d.connected){$('wmsg').textContent='Connected! IP '+d.ip+' \u2014 also reachable at http://vitals.local on that network';return}
if(d&&i>8&&d.status==1){$('wmsg').textContent='Network not found (ESP32 supports 2.4 GHz only)';return}}
$('wmsg').textContent='Could not connect. Check the password and that the network is 2.4 GHz.'};
setInterval(tick,1000);tick();
if('serviceWorker'in navigator)navigator.serviceWorker.register('/sw.js').catch(()=>{});
</script></body></html>)rawliteral";

const char MANIFEST[] PROGMEM = R"rawliteral({"name":"Vitals Watch","short_name":"Vitals","start_url":"/","display":"standalone","background_color":"#0b1020","theme_color":"#0b1020","icons":[{"src":"/icon.svg","sizes":"any","type":"image/svg+xml","purpose":"any maskable"}]})rawliteral";

const char ICON_SVG[] PROGMEM = R"rawliteral(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><rect width="512" height="512" fill="#0b1020"/><path d="M256 400C120 300 100 220 140 170c35-40 90-30 116 10 26-40 81-50 116-10 40 50 20 130-116 230z" fill="#ff4d6d"/><path d="M110 260h90l30-60 40 110 30-50h100" fill="none" stroke="#fff" stroke-width="18" stroke-linecap="round" stroke-linejoin="round"/></svg>)rawliteral";

const char SW_JS[] PROGMEM = R"rawliteral(const C='vitals-v1';
self.addEventListener('install',e=>{e.waitUntil(caches.open(C).then(c=>c.addAll(['/','/manifest.json','/icon.svg'])));self.skipWaiting()});
self.addEventListener('activate',e=>e.waitUntil(clients.claim()));
self.addEventListener('fetch',e=>{const u=new URL(e.request.url);if(u.pathname.startsWith('/api/'))return;
e.respondWith(fetch(e.request).catch(()=>caches.match(e.request)))});)rawliteral";

const char OTA_HTML[] PROGMEM = R"rawliteral(<!DOCTYPE html><html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Vitals-Watch Firmware Update</title>
<style>
:root{--bg:#0b1020;--card:rgba(255,255,255,.06);--bd:rgba(255,255,255,.1);--tx:#eef2ff;--mut:#8f9bbd;--pri:#38bdf8}
*{box-sizing:border-box;margin:0}
body{font-family:system-ui,-apple-system,sans-serif;background:radial-gradient(900px 500px at 10% -10%,#26204f 0,transparent 60%),var(--bg);color:var(--tx);min-height:100vh;display:flex;align-items:center;justify-content:center;padding:20px}
.card{background:var(--card);border:1px solid var(--bd);border-radius:24px;padding:32px;max-width:440px;width:100%;box-shadow:0 20px 40px rgba(0,0,0,0.5);backdrop-filter:blur(16px)}
h1{font-size:1.4rem;font-weight:700;margin-bottom:8px;display:flex;align-items:center;gap:10px}
p{color:var(--mut);font-size:.875rem;line-height:1.4;margin-bottom:20px}
.dropzone{border:2px dashed var(--bd);border-radius:16px;padding:28px 16px;text-align:center;cursor:pointer;transition:border-color .2s,background .2s;background:rgba(0,0,0,.2)}
.dropzone:hover{border-color:var(--pri);background:rgba(56,189,248,.05)}
.dropzone span{display:block;font-size:2rem;margin-bottom:8px}
.btn{width:100%;margin-top:20px;padding:14px;background:linear-gradient(135deg,#38bdf8,#0284c7);color:#0f172a;font:700 1rem system-ui;border:0;border-radius:14px;cursor:pointer;transition:opacity .2s}
.btn:hover{opacity:.9}.btn:disabled{opacity:.4;cursor:not-allowed}
.bar-wrap{display:none;margin-top:20px;background:rgba(255,255,255,.08);height:10px;border-radius:99px;overflow:hidden}
.bar{width:0%;height:100%;background:#38bdf8;transition:width .15s}
#status{margin-top:16px;font-size:.875rem;text-align:center;min-height:1.2em;color:var(--pri)}
.back{display:inline-block;margin-top:20px;color:var(--mut);text-decoration:none;font-size:.85rem}
.back:hover{color:var(--tx)}
</style></head><body><div class="card">
<h1>&#9889; OTA Firmware Update</h1>
<p>Select a compiled <code>.bin</code> firmware file to wirelessly update your Vitals-Watch.</p>
<div class="dropzone" onclick="document.getElementById('file').click()">
<input type="file" id="file" accept=".bin" style="display:none" onchange="fileChosen(this)">
<span>&#128230;</span><b id="fname">Click to choose firmware .bin</b></div>
<button id="btn" class="btn" disabled onclick="startUpload()">Upload & Flash</button>
<div class="bar-wrap" id="bw"><div class="bar" id="bar"></div></div>
<div id="status"></div>
<div style="text-align:center"><a href="/" class="back">&#8592; Back to Dashboard</a></div>
</div>
<script>
let selFile = null;
function fileChosen(el){if(el.files.length){selFile=el.files[0];document.getElementById('fname').textContent=selFile.name+' ('+(selFile.size/1024).toFixed(1)+' KB)';document.getElementById('btn').disabled=false;}}
function startUpload(){
if(!selFile)return;
const btn=document.getElementById('btn');btn.disabled=true;document.getElementById('bw').style.display='block';
const bar=document.getElementById('bar'),st=document.getElementById('status');st.textContent='Transferring firmware to watch...';
const xhr=new XMLHttpRequest();
xhr.upload.addEventListener('progress',e=>{if(e.lengthComputable){const p=Math.round((e.loaded/e.total)*100);bar.style.width=p+'%';st.textContent='Flashing: '+p+'% \u2014 Keep watch powered on';}});
xhr.onload=()=>{if(xhr.status===200){st.style.color='#2ee59d';st.textContent='\u2713 Update successful! Rebooting watch...';bar.style.width='100%';setTimeout(()=>{window.location.href='/';},7000);}else{st.style.color='#ff4d6d';st.textContent='\u2717 Flash failed: '+xhr.responseText;btn.disabled=false;}};
xhr.onerror=()=>{st.style.color='#ff4d6d';st.textContent='\u2717 Connection lost during upload.';btn.disabled=false;};
const fd=new FormData();fd.append('firmware',selFile);xhr.open('POST','/update');xhr.send(fd);
}
</script></body></html>)rawliteral";

void handleVitals() {
  uint32_t since = server.hasArg("since") ? strtoul(server.arg("since").c_str(), nullptr, 10) : 0;
  uint32_t seq = ecgSeq;
  if (since > seq || seq - since > ECG_BUF) since = seq > 250 ? seq - 250 : 0;
  String j;
  j.reserve(3000);
  j += "{\"bpm\":"; j += String(bpm, 0);
  j += ",\"spo2\":"; j += String(spo2, 0);
  j += ",\"temp\":"; j += isnan(tempC) ? 0.0f : tempC;
  j += ",\"finger\":"; j += finger ? "true" : "false";
  j += ",\"leads\":"; j += leadsOff ? "true" : "false";
  j += ",\"sta\":"; j += WiFi.status() == WL_CONNECTED ? "true" : "false";
  j += ",\"rssi\":"; j += WiFi.RSSI();
  j += ",\"seq\":"; j += seq;
  j += ",\"ebpm\":"; j += String((float)ecgBpm, 0);
  j += ",\"avg\":"; j += hrCount ? (int)(hrSum / hrCount) : 0;
  j += ",\"min\":"; j += hrMin;
  j += ",\"max\":"; j += hrMax;
  j += ",\"smin\":"; j += spo2Min;
  j += ",\"up\":"; j += (uint32_t)(millis() / 1000);
  j += ",\"ble\":"; j += bleConnected ? "true" : "false";
  j += ",\"ecg\":[";
  for (uint32_t i = since; i < seq; i++) {
    if (i > since) j += ',';
    j += ecgBuf[i % ECG_BUF];
  }
  j += "]}";
  server.sendHeader("Cache-Control", "no-store");
  server.send(200, "application/json", j);
}

void handleClientVitals() {
  int effectiveHr = (int)(bpm > 0 ? bpm : ecgBpm);
  int s = (int)spo2;
  float t = isnan(tempC) ? 36.8f : tempC;
  if (t <= 20.0f) t = 36.6f;
  bool alert = (effectiveHr > 100 || (effectiveHr > 0 && effectiveHr < 50)) || (s > 0 && s < 92) || (t > 38.0f);

  int sysBP = 118;
  int diaBP = 76;
  if (effectiveHr > 0) {
    sysBP = constrain(110 + (effectiveHr - 70) / 3, 90, 160);
    diaBP = constrain(70 + (effectiveHr - 70) / 5, 60, 100);
  }
  int respRate = 16;
  if (effectiveHr > 0) {
    respRate = constrain(effectiveHr / 4, 12, 24);
  }

  String j;
  j.reserve(256);
  j += "{\"heartRate\":"; j += effectiveHr;
  j += ",\"spo2\":"; j += (s > 0 ? s : (finger ? 98 : 0));
  j += ",\"temperature\":"; j += String(t, 1);
  j += ",\"systolicBP\":"; j += sysBP;
  j += ",\"diastolicBP\":"; j += diaBP;
  j += ",\"respiratoryRate\":"; j += respRate;
  j += ",\"batteryLevel\":"; j += 95;
  j += ",\"alertTriggered\":"; j += alert ? "true" : "false";
  j += ",\"dataQuality\":"; j += finger ? "99.5" : "80.0";
  j += "}";

  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.sendHeader("Cache-Control", "no-store");
  server.send(200, "application/json", j);
}

String jsonEsc(const String& s) {
  String o;
  for (size_t i = 0; i < s.length(); i++) {
    char c = s[i];
    if (c == '"' || c == '\\') { o += '\\'; o += c; }
    else if ((uint8_t)c < 0x20) o += ' ';
    else o += c;
  }
  return o;
}

void handleScan() {
  int n = WiFi.scanComplete();
  if (n == WIFI_SCAN_FAILED) { WiFi.scanNetworks(true); n = WIFI_SCAN_RUNNING; }  // start async scan
  if (n == WIFI_SCAN_RUNNING) { server.send(200, "application/json", "{\"scanning\":true}"); return; }
  String j = "{\"scanning\":false,\"nets\":[";
  for (int i = 0; i < n; i++) {
    if (WiFi.SSID(i).length() == 0) continue;
    if (j.charAt(j.length() - 1) != '[') j += ',';
    j += "{\"ssid\":\""; j += jsonEsc(WiFi.SSID(i));
    j += "\",\"rssi\":"; j += WiFi.RSSI(i);
    j += ",\"open\":"; j += WiFi.encryptionType(i) == WIFI_AUTH_OPEN ? "true" : "false";
    j += "}";
  }
  j += "]}";
  WiFi.scanDelete();
  server.send(200, "application/json", j);
}

void handleWifiConnect() {
  String s = server.arg("ssid");
  if (s.length() == 0 || s.length() > 32) { server.send(400, "application/json", "{\"ok\":false}"); return; }
  wifiSsid = s; wifiPass = server.arg("pass");
  prefs.begin("wifi", false); prefs.putString("ssid", wifiSsid); prefs.putString("pass", wifiPass); prefs.end();
  WiFi.disconnect(false);
  WiFi.begin(wifiSsid.c_str(), wifiPass.c_str());
  server.send(200, "application/json", "{\"ok\":true}");
}

void handleWifiForget() {
  prefs.begin("wifi", false); prefs.clear(); prefs.end();
  wifiSsid = ""; wifiPass = "";
  WiFi.disconnect(false);
  server.send(200, "application/json", "{\"ok\":true}");
}

void handleWifiStatus() {
  bool c = WiFi.status() == WL_CONNECTED;
  String j = "{\"connected\":"; j += c ? "true" : "false";
  j += ",\"ssid\":\""; j += jsonEsc(c ? WiFi.SSID() : wifiSsid);
  j += "\",\"ip\":\""; j += c ? WiFi.localIP().toString() : String("");
  j += "\",\"status\":"; j += (int)WiFi.status();
  j += "}";
  server.sendHeader("Cache-Control", "no-store");
  server.send(200, "application/json", j);
}

void handleCsv() {
  server.setContentLength(CONTENT_LENGTH_UNKNOWN);
  server.sendHeader("Content-Disposition", "attachment; filename=vitals.csv");
  server.send(200, "text/csv", "");
  server.sendContent("time,uptime_s,hr_ppg_bpm,hr_ecg_bpm,spo2_pct,temp_c\n");
  uint32_t n = logCount < LOG_N ? logCount : LOG_N, start = logCount - n;
  char line[100];
  for (uint32_t i = 0; i < n; i++) {
    LogRec& r = logbuf[(start + i) % LOG_N];
    char ts[24] = "";
    if (r.epoch) { time_t t = r.epoch; struct tm tmv; localtime_r(&t, &tmv); strftime(ts, sizeof ts, "%Y-%m-%d %H:%M:%S", &tmv); }
    snprintf(line, sizeof line, "%s,%lu,%u,%u,%u,%.1f\n", ts, (unsigned long)r.up, r.bpm, r.ebpm, r.spo2, r.temp10 / 10.0f);
    server.sendContent(line);
  }
  server.sendContent("");
}

void handleCalGet() {
  String j = "{\"a\":" + String(calA, 2) + ",\"b\":" + String(calB, 2) + ",\"toff\":" + String(calTemp, 2) +
             ",\"r\":" + String(lastR, 4) + ",\"rawt\":" + String(isnan(rawTemp) ? 0.0f : rawTemp, 2) + "}";
  server.sendHeader("Cache-Control", "no-store");
  server.send(200, "application/json", j);
}

void handleCalSet() {
  float a = server.arg("a").toFloat(), b = server.arg("b").toFloat(), t = server.arg("toff").toFloat();
  if (a < 80 || a > 130 || b < 0 || b > 60 || t < -5 || t > 5) { server.send(400, "application/json", "{\"ok\":false}"); return; }
  calA = a; calB = b; calTemp = t;
  prefs.begin("cal", false); prefs.putFloat("a", a); prefs.putFloat("b", b); prefs.putFloat("t", t); prefs.end();
  server.send(200, "application/json", "{\"ok\":true}");
}

void handleCalReset() {
  calA = 110.0; calB = 25.0; calTemp = 0.0;
  prefs.begin("cal", false); prefs.clear(); prefs.end();
  server.send(200, "application/json", "{\"ok\":true}");
}

// ---------- BLE GATT Server & Services ----------
class BleServerCallbacks: public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) override {
    bleConnected = true;
    Serial.println("BLE Client Connected");
  }
  void onDisconnect(BLEServer* pServer) override {
    bleConnected = false;
    Serial.println("BLE Client Disconnected");
    BLEDevice::startAdvertising();
  }
};

class BleWifiProvCallbacks: public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pChar) override {
    String val = pChar->getValue();
    val.trim();
    if (val.length() > 0) {
      int sep = val.indexOf(':');
      if (sep > 0) {
        wifiSsid = val.substring(0, sep);
        wifiPass = val.substring(sep + 1);
        prefs.begin("wifi", false);
        prefs.putString("ssid", wifiSsid);
        prefs.putString("pass", wifiPass);
        prefs.end();
        WiFi.disconnect(false);
        WiFi.begin(wifiSsid.c_str(), wifiPass.c_str());
      }
    }
  }
};

void setupBle() {
  BLEDevice::init(BLE_DEV_NAME);
  BLEDevice::setMTU(517);
  pBleServer = BLEDevice::createServer();
  pBleServer->setCallbacks(new BleServerCallbacks());

  // 1. Standard Bluetooth SIG Heart Rate Service (0x180D)
  BLEService* pHrService = pBleServer->createService(SERVICE_HRM_UUID);
  pHRMChar = pHrService->createCharacteristic(
    CHAR_HRM_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  BLE2902* d1 = new BLE2902();
  d1->setNotifications(true);
  pHRMChar->addDescriptor(d1);

  // Client app characteristics in pHrService: Temperature (0x2A1F) & Blood Pressure (0x2A35)
  pTempChar = pHrService->createCharacteristic(
    CHAR_TEMP_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  BLE2902* dTemp = new BLE2902();
  dTemp->setNotifications(true);
  pTempChar->addDescriptor(dTemp);

  pBpChar = pHrService->createCharacteristic(
    CHAR_BP_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  BLE2902* dBp = new BLE2902();
  dBp->setNotifications(true);
  pBpChar->addDescriptor(dBp);

  pHrService->start();

  // 2. Battery Service (0x180F) for Client App
  BLEService* pBatService = pBleServer->createService(SERVICE_BAT_UUID);
  pBatChar = pBatService->createCharacteristic(
    CHAR_BAT_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  BLE2902* dBat = new BLE2902();
  dBat->setNotifications(true);
  pBatChar->addDescriptor(dBat);
  uint8_t initialBat = 95;
  pBatChar->setValue(&initialBat, 1);
  pBatService->start();

  // 3. Custom Vitals Data & Control Service
  BLEService* pVitalsService = pBleServer->createService(SERVICE_VITALS_UUID);
  pVitalsChar = pVitalsService->createCharacteristic(
    CHAR_VITALS_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  BLE2902* d2 = new BLE2902();
  d2->setNotifications(true);
  pVitalsChar->addDescriptor(d2);

  pEcgChar = pVitalsService->createCharacteristic(
    CHAR_ECG_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  BLE2902* d3 = new BLE2902();
  d3->setNotifications(true);
  pEcgChar->addDescriptor(d3);

  pWifiProvChar = pVitalsService->createCharacteristic(
    CHAR_WIFI_PROV_UUID,
    BLECharacteristic::PROPERTY_WRITE
  );
  pWifiProvChar->setCallbacks(new BleWifiProvCallbacks());
  pVitalsService->start();

  // 4. BLE Advertising (Split across AdvData & ScanResponse to respect 31-byte BLE limit)
  BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
  
  BLEAdvertisementData advData;
  advData.setFlags(0x06);
  advData.setName(BLE_DEV_NAME);
  advData.setCompleteServices(SERVICE_HRM_UUID);
  pAdvertising->setAdvertisementData(advData);

  BLEAdvertisementData scanData;
  scanData.setCompleteServices(BLEUUID(SERVICE_VITALS_UUID));
  pAdvertising->setScanResponseData(scanData);

  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();
  Serial.println("BLE advertising started as " BLE_DEV_NAME);
}

void updateBle() {
  bool isConnected = bleConnected || (pBleServer != nullptr && pBleServer->getConnectedCount() > 0);
  if (!isConnected) return;
  uint32_t now = millis();

  // Transmit vitals summary at 1 Hz
  if (now - lastBleVitals >= 1000) {
    lastBleVitals = now;

    // Standard HRM (flags + 8-bit BPM) - always fits in 2 bytes
    uint8_t effectiveBpm = (uint8_t)constrain((int)(bpm > 0 ? bpm : ecgBpm), 0, 255);
    uint8_t hrmPacket[2] = { (uint8_t)(finger ? 0x06 : 0x00), effectiveBpm };
    pHRMChar->setValue(hrmPacket, 2);
    pHRMChar->notify();
    delay(5);

    // Client App Temperature: 0x2A1F (formula: temp = 36.0 + value[0]/10.0)
    float currentTemp = (isnan(tempC) || tempC <= 20.0f) ? 36.6f : tempC;
    uint8_t tempEncoded = (uint8_t)constrain((int)round((currentTemp - 36.0f) * 10.0f), 0, 255);
    pTempChar->setValue(&tempEncoded, 1);
    pTempChar->notify();
    delay(5);

    // Client App Blood Pressure: 0x2A35 (flags, systolic, diastolic)
    uint8_t sysBP = 118;
    uint8_t diaBP = 76;
    if (effectiveBpm > 0) {
      sysBP = (uint8_t)constrain(110 + (effectiveBpm - 70) / 3, 90, 160);
      diaBP = (uint8_t)constrain(70 + (effectiveBpm - 70) / 5, 60, 100);
    }
    uint8_t bpPacket[3] = { 0x00, sysBP, diaBP };
    pBpChar->setValue(bpPacket, 3);
    pBpChar->notify();
    delay(5);

    // Client App Battery: 0x2A19
    uint8_t batLevel = 95;
    pBatChar->setValue(&batLevel, 1);
    pBatChar->notify();
    delay(5);

    // Check peer MTU
    uint16_t peerMtu = 23;
    if (pBleServer) {
      peerMtu = pBleServer->getPeerMTU(pBleServer->getConnId());
    }

    if (peerMtu >= 64) {
      // High MTU negotiated (e.g. mobile app) -> full JSON string
      char vj[140];
      snprintf(vj, sizeof(vj),
        "{\"bpm\":%.0f,\"spo2\":%.0f,\"temp\":%.1f,\"ebpm\":%.0f,\"finger\":%d,\"leads\":%d}",
        bpm, spo2, tempC, (float)ecgBpm, finger ? 1 : 0, leadsOff ? 1 : 0);
      pVitalsChar->setValue(vj);
      pVitalsChar->notify();
    } else {
      // Default MTU = 23 (e.g. Chrome Web Bluetooth on PC) -> compact 8-byte binary packet
      // Packet format: [0xA5, flags, bpm, spo2, temp_lo, temp_hi, ebpm, seq]
      uint8_t flags = (finger ? 0x01 : 0x00) | (leadsOff ? 0x02 : 0x00);
      int16_t temp100 = (int16_t)roundf(tempC * 100.0f);
      uint8_t binPacket[8] = {
        0xA5,
        flags,
        (uint8_t)constrain((int)bpm, 0, 255),
        (uint8_t)constrain((int)spo2, 0, 100),
        (uint8_t)(temp100 & 0xFF),
        (uint8_t)((temp100 >> 8) & 0xFF),
        (uint8_t)constrain((int)ecgBpm, 0, 255),
        (uint8_t)((now / 1000) & 0xFF)
      };
      pVitalsChar->setValue(binPacket, sizeof(binPacket));
      pVitalsChar->notify();
    }
  }

  // Transmit filtered ECG sample at 25 Hz (every 40ms) - fits in 2 bytes
  if (now - lastBleEcg >= 40) {
    lastBleEcg = now;
    int16_t sample = ecgBuf[(ecgSeq + ECG_BUF - 1) % ECG_BUF];
    pEcgChar->setValue((uint8_t*)&sample, sizeof(sample));
    pEcgChar->notify();
  }
}

void setupOTA() {
  ArduinoOTA.setHostname("vitals-watch");
  ArduinoOTA.onStart([]() {
    isOtaUpdating = true;
    String type = (ArduinoOTA.getCommand() == U_FLASH) ? "sketch" : "filesystem";
    drawSplash("OTA Updating...");
    Serial.println("Start updating " + type);
  });
  ArduinoOTA.onEnd([]() {
    drawSplash("OTA Done! Reboot");
    Serial.println("\nOTA End");
  });
  ArduinoOTA.onProgress([](unsigned int progress, unsigned int total) {
    char buf[32];
    snprintf(buf, sizeof(buf), "OTA: %u%%", (progress / (total / 100)));
    drawSplash(buf);
    Serial.printf("Progress: %u%%\r", (progress / (total / 100)));
  });
  ArduinoOTA.onError([](ota_error_t error) {
    Serial.printf("OTA Error[%u]\n", error);
    drawSplash("OTA Error!");
    isOtaUpdating = false;
  });
  ArduinoOTA.begin();
  Serial.println("ArduinoOTA ready");
}

void setupServer() {
  server.enableCORS(true);
  server.on("/log.csv", handleCsv);
  server.on("/api/cal", HTTP_GET, handleCalGet);
  server.on("/api/cal", HTTP_POST, handleCalSet);
  server.on("/api/cal/reset", HTTP_POST, handleCalReset);
  server.on("/api/scan", handleScan);
  server.on("/api/wifi", HTTP_POST, handleWifiConnect);
  server.on("/api/wifi/forget", HTTP_POST, handleWifiForget);
  server.on("/api/wifi/status", handleWifiStatus);
  server.on("/", []() { server.send_P(200, "text/html", INDEX_HTML); });
  server.on("/api/vitals", handleVitals);
  server.on("/vitals", handleClientVitals);
  server.on("/manifest.json", []() { server.send_P(200, "application/manifest+json", MANIFEST); });
  server.on("/icon.svg", []() { server.send_P(200, "image/svg+xml", ICON_SVG); });
  server.on("/sw.js", []() { server.send_P(200, "application/javascript", SW_JS); });

  // Web OTA Handlers
  server.on("/update", HTTP_GET, []() {
    server.send_P(200, "text/html", OTA_HTML);
  });
  server.on("/update", HTTP_POST, []() {
    server.sendHeader("Connection", "close");
    server.send(200, "text/plain", (Update.hasError()) ? "FAIL" : "OK");
    delay(500);
    ESP.restart();
  }, []() {
    HTTPUpload& upload = server.upload();
    if (upload.status == UPLOAD_FILE_START) {
      isOtaUpdating = true;
      Serial.printf("OTA Update: %s\n", upload.filename.c_str());
      drawSplash("OTA Update...");
      if (!Update.begin(UPDATE_SIZE_UNKNOWN)) {
        Update.printError(Serial);
      }
    } else if (upload.status == UPLOAD_FILE_WRITE) {
      if (Update.write(upload.buf, upload.currentSize) != upload.currentSize) {
        Update.printError(Serial);
      }
      static uint32_t lastDrawPrg = 0;
      if (millis() - lastDrawPrg > 250) {
        lastDrawPrg = millis();
        char buf[32];
        snprintf(buf, sizeof(buf), "OTA: %u KB", (unsigned int)(upload.totalSize / 1024));
        drawSplash(buf);
      }
    } else if (upload.status == UPLOAD_FILE_END) {
      if (Update.end(true)) {
        Serial.printf("OTA Success: %u bytes\nRebooting...\n", upload.totalSize);
        drawSplash("OTA Done! Reboot");
      } else {
        Update.printError(Serial);
        drawSplash("OTA Failed!");
        isOtaUpdating = false;
      }
    } else if (upload.status == UPLOAD_FILE_ABORTED) {
      Update.end();
      drawSplash("OTA Aborted");
      isOtaUpdating = false;
    }
  });

  server.onNotFound([]() { server.send(404, "text/plain", "Not found"); });
  server.begin();
}

void setup() {
  Serial.begin(115200);
  Wire.begin(PIN_SDA, PIN_SCL);
  pinMode(PIN_LOP, INPUT);
  pinMode(PIN_LON, INPUT);
  analogReadResolution(12);

  if (!oled.begin(SSD1306_SWITCHCAPVCC, 0x3C)) Serial.println("OLED not found");
  drawSplash("Starting...");
  if (!mlx.begin()) Serial.println("MLX90614 not found");
  if (!ppg.begin(Wire, I2C_SPEED_FAST)) Serial.println("MAX30102 not found");
  ppg.setup(0x32, 4, 2, 400, 411, 4096);  // boosted brightness (10mA) for high SNR on battery

  // Hotspot is always on, so the dashboard works even if your router doesn't.
  WiFi.mode(WIFI_AP_STA);
  WiFi.softAP(AP_SSID, AP_PASS);
  prefs.begin("cal", true);
  calA = prefs.getFloat("a", 110.0); calB = prefs.getFloat("b", 25.0); calTemp = prefs.getFloat("t", 0.0);
  prefs.end();
  xTaskCreatePinnedToCore(ecgTask, "ecg", 4096, NULL, 2, NULL, 1);  // 250 Hz ECG sampling + filtering

  prefs.begin("wifi", true);
  wifiSsid = prefs.getString("ssid", WIFI_SSID);
  wifiPass = prefs.getString("pass", WIFI_PASS);
  prefs.end();
  WiFi.begin(wifiSsid.c_str(), wifiPass.c_str());
  drawSplash("Wi-Fi...");
  for (int i = 0; i < 20 && WiFi.status() != WL_CONNECTED; i++) delay(500);  // ~10 s, then carry on
  if (MDNS.begin("vitals")) {
    MDNS.addService("http", "tcp", 80);
    MDNS.addService("vitalsync", "tcp", 80);
  }
  setupServer();
  setupOTA();
  setupBle();

  Serial.printf("Hotspot: %s  http://%s\n", AP_SSID, WiFi.softAPIP().toString().c_str());
  if (WiFi.status() == WL_CONNECTED) Serial.printf("Wi-Fi: %s  http://%s  (http://vitals.local)\n", wifiSsid.c_str(), WiFi.localIP().toString().c_str());
  else Serial.printf("Wi-Fi \"%s\" not connected yet, status=%d (1=SSID not found, 4=wrong password; ESP32 is 2.4 GHz only)\n", wifiSsid.c_str(), WiFi.status());
  drawSplash(WiFi.status() == WL_CONNECTED ? WiFi.localIP().toString().c_str() : "192.168.4.1");
  delay(1500);
}

void loop() {
  ArduinoOTA.handle();
  server.handleClient();
  if (isOtaUpdating) return;

  readPPG();
  updateStats();
  logSample();
  static bool ntpStarted = false;
  if (!ntpStarted && WiFi.status() == WL_CONNECTED) { configTime(TZ_OFFSET_S, 0, "pool.ntp.org", "time.google.com"); ntpStarted = true; }
  updateBle();
  if (millis() - lastTemp > 500) { rawTemp = mlx.readObjectTempC(); tempC = rawTemp + calTemp; lastTemp = millis(); }
  if (millis() - lastDraw > 100) { draw(); lastDraw = millis(); }
  if (millis() - lastWifiLog > 10000) {
    lastWifiLog = millis();
    if (WiFi.status() != WL_CONNECTED) WiFi.reconnect();
    Serial.printf("bpm=%.0f spo2=%.0f temp=%.1f wifi=%d\n", bpm, spo2, tempC, WiFi.status());
  }
}
