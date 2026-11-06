/**
 * PulseGuard Companion App Engine
 * Dual-Mode (Web Bluetooth & Wi-Fi) Client for ESP32-S3 Vitals Watch
 */

// Bluetooth GATT Configuration
const BLE_CONFIG = {
  DEVICE_NAME: 'Vitals-Watch',
  SERVICE_HRM: 'heart_rate',
  SERVICE_HRM_UUID: '0000180d-0000-1000-8000-00805f9b34fb',
  CHAR_HRM: '00002a37-0000-1000-8000-00805f9b34fb',
  SERVICE_VITALS: '19b10000-e8f2-537e-4f6c-d104768a1214',
  CHAR_VITALS_JSON: '19b10001-e8f2-537e-4f6c-d104768a1214',
  CHAR_ECG_STREAM: '19b10002-e8f2-537e-4f6c-d104768a1214',
  CHAR_WIFI_PROV: '19b10003-e8f2-537e-4f6c-d104768a1214'
};

// Application State
const state = {
  transport: 'none', // 'ble', 'wifi', 'none'
  connected: false,
  soundEnabled: false,
  vitals: {
    bpm: 0,
    spo2: 0,
    temp: 0,
    ebpm: 0,
    finger: false,
    leadsOff: true
  },
  stats: {
    hrMin: 0,
    hrMax: 0,
    hrSum: 0,
    hrCount: 0,
    spo2Min: 0,
    startTime: Date.now()
  },
  wifi: {
    ip: localStorage.getItem('pg_wifi_ip') || (window.location.hostname === '192.168.4.1' ? '192.168.4.1' : '192.168.0.196'),
    pollInterval: null,
    lastSeq: 0
  },
  ble: {
    device: null,
    server: null,
    charVitals: null,
    charEcg: null,
    charHrm: null
  },
  ecgBuffer: [],
  sessionLog: []
};

// UI Element Selector Helper
const $ = (id) => document.getElementById(id);

function logMsg(msg) {
  console.log('[PulseGuard]', msg);
  const logEl = $('appConsole');
  if (logEl) {
    const time = new Date().toLocaleTimeString();
    logEl.innerHTML = `<div><span style="color:#64748b;">${time}</span> ${msg}</div>` + logEl.innerHTML;
  }
}

// Audio Heartbeat Chime (Web Audio API)
let audioCtx = null;
function playHeartBeep() {
  if (!state.soundEnabled) return;
  try {
    if (!audioCtx) audioCtx = new (window.AudioContext || window.webkitAudioContext)();
    if (audioCtx.state === 'suspended') audioCtx.resume();
    const osc = audioCtx.createOscillator();
    const gain = audioCtx.createGain();
    osc.type = 'sine';
    osc.frequency.setValueAtTime(880, audioCtx.currentTime);
    gain.gain.setValueAtTime(0.08, audioCtx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.001, audioCtx.currentTime + 0.08);
    osc.connect(gain);
    gain.connect(audioCtx.destination);
    osc.start();
    osc.stop(audioCtx.currentTime + 0.08);
  } catch (e) {
    console.warn('Audio error:', e);
  }
}

// ---------------------------------------------------------------------
// 1. Web Bluetooth API Driver
// ---------------------------------------------------------------------
let blePollTimer = null;
let lastBlePacketTime = 0;

function decodeBleVitalsPacket(val, source = 'Notify') {
  if (!val || val.byteLength === 0) return;
  lastBlePacketTime = Date.now();

  // 1. Binary 8-byte packet check (Magic 0xA5)
  if (val.byteLength >= 8 && val.getUint8(0) === 0xA5) {
    const flags = val.getUint8(1);
    const bpm = val.getUint8(2);
    const spo2 = val.getUint8(3);
    const temp = val.getInt16(4, true) / 100.0;
    const ebpm = val.getUint8(6);
    const finger = (flags & 0x01) !== 0;
    const leadsOff = (flags & 0x02) !== 0;

    logMsg(`[BLE ${source}] Telemetry: HR=${bpm}bpm SpO2=${spo2}% Temp=${temp.toFixed(1)}°C (Finger: ${finger ? 'ON' : 'OFF'})`);
    handleVitalsPacket({
      bpm: bpm,
      spo2: spo2,
      temp: temp,
      ebpm: ebpm,
      finger: finger,
      leadsOff: leadsOff
    });
    return;
  }

  // 2. Full JSON string packet
  try {
    const decoder = new TextDecoder('utf-8');
    const jsonStr = decoder.decode(val);
    const d = JSON.parse(jsonStr);
    logMsg(`[BLE ${source} JSON] Telemetry: HR=${d.bpm}bpm SpO2=${d.spo2}% Temp=${d.temp}°C`);
    handleVitalsPacket({
      bpm: d.bpm,
      spo2: d.spo2,
      temp: d.temp,
      ebpm: d.ebpm,
      finger: d.finger === 1,
      leadsOff: d.leads === 1
    });
  } catch (errJson) {
    console.warn('JSON decode err:', errJson);
  }
}

async function connectBluetooth() {
  if (!navigator.bluetooth) {
    alert('Web Bluetooth is not supported in this browser. Please open in Google Chrome or Microsoft Edge on Windows/Mac/Android, or Bluefy on iOS.');
    return;
  }

  // Automatically open the activity console so user can see pairing progress
  const consoleEl = $('consoleDrawer');
  if (consoleEl) consoleEl.style.display = 'block';

  try {
    updateStatus('Searching BLE...', 'none');
    logMsg('Opening Bluetooth pairing dialog... Please select "Vitals-Watch"');

    // Request device with name filter and optional services
    const device = await navigator.bluetooth.requestDevice({
      filters: [
        { name: BLE_CONFIG.DEVICE_NAME },
        { namePrefix: 'Vitals' },
        { services: ['heart_rate'] }
      ],
      optionalServices: [
        'heart_rate',
        BLE_CONFIG.SERVICE_VITALS
      ]
    });

    logMsg(`Selected device: ${device.name || 'Vitals-Watch'}`);
    state.ble.device = device;
    device.addEventListener('gattserverdisconnected', onBleDisconnected);

    updateStatus('Connecting GATT...', 'none');
    logMsg('Connecting to device GATT server...');
    const server = await device.gatt.connect();
    state.ble.server = server;
    logMsg('GATT server connected successfully!');

    let subscribedAny = false;

    // 1. Subscribe to Custom Vitals Service (Binary / JSON & ECG stream)
    try {
      const vitalsService = await server.getPrimaryService(BLE_CONFIG.SERVICE_VITALS);
      logMsg('Found Custom Vitals Service');

      try {
        state.ble.charVitals = await vitalsService.getCharacteristic(BLE_CONFIG.CHAR_VITALS_JSON);
        await state.ble.charVitals.startNotifications();
        state.ble.charVitals.addEventListener('characteristicvaluechanged', (e) => {
          decodeBleVitalsPacket(e.target.value, 'Notify');
        });
        subscribedAny = true;
        logMsg('Subscribed to Live Vitals notifications');
        // Initial immediate read to display vitals immediately
        try {
          const initVal = await state.ble.charVitals.readValue();
          decodeBleVitalsPacket(initVal, 'InitRead');
        } catch (eInit) {}
      } catch (errChar) {
        logMsg('Could not subscribe to vitals char: ' + errChar.message);
      }

      await new Promise(r => setTimeout(r, 200));

      // ECG Stream
      try {
        state.ble.charEcg = await vitalsService.getCharacteristic(BLE_CONFIG.CHAR_ECG_STREAM);
        await state.ble.charEcg.startNotifications();
        state.ble.charEcg.addEventListener('characteristicvaluechanged', (e) => {
          if (e.target.value.byteLength >= 2) {
            const sample = e.target.value.getInt16(0, true);
            pushEcgSample(sample);
          }
        });
        subscribedAny = true;
        logMsg('Subscribed to Live ECG Waveform stream');
      } catch (errEcg) {
        logMsg('Could not subscribe to ECG char: ' + errEcg.message);
      }

    } catch (errCustom) {
      logMsg('Custom vitals service not found: ' + errCustom.message);
    }

    await new Promise(r => setTimeout(r, 200));

    // 2. ALSO Subscribe to Standard Heart Rate Service (0x180D) for redundant BPM stream
    try {
      const hrService = await server.getPrimaryService('heart_rate');
      logMsg('Found Standard Heart Rate Service (0x180D)');
      state.ble.charHrm = await hrService.getCharacteristic('00002a37-0000-1000-8000-00805f9b34fb');
      await state.ble.charHrm.startNotifications();
      state.ble.charHrm.addEventListener('characteristicvaluechanged', (e) => {
        const val = e.target.value;
        const flags = val.getUint8(0);
        const hr = (flags & 0x01) ? val.getUint16(1, true) : val.getUint8(1);
        handleVitalsPacket({
          bpm: hr,
          finger: (flags & 0x06) === 0x06 || hr > 0
        });
      });
      subscribedAny = true;
      logMsg('Subscribed to Standard Heart Rate (0x2A37) notifications');
    } catch (errHrm) {
      logMsg('Standard HRM not accessible: ' + errHrm.message);
    }

    // 3. Fallback active polling every 1.5 seconds if notifications are delayed or suppressed by Windows
    if (blePollTimer) clearInterval(blePollTimer);
    blePollTimer = setInterval(async () => {
      if (state.transport !== 'ble' || !state.connected || !state.ble.server || !state.ble.server.connected) return;
      if (Date.now() - lastBlePacketTime < 1800) return; // Notifications are healthy
      if (state.ble.charVitals) {
        try {
          const val = await state.ble.charVitals.readValue();
          decodeBleVitalsPacket(val, 'Poll');
        } catch (e) {}
      }
    }, 1500);

    if (!subscribedAny && !state.ble.charVitals) {
      throw new Error('Could not access telemetry characteristics');
    }

    state.transport = 'ble';
    state.connected = true;
    updateStatus('Connected via BLE', 'ble');
    syncConnectButtons(true, 'ble');
    logMsg('Bluetooth streaming active and receiving live vitals!');
  } catch (err) {
    console.error('BLE connection error:', err);
    logMsg('BLE connection cancelled or error: ' + (err.message || err));
    updateStatus('BLE Disconnected', 'none');
    syncConnectButtons(false, 'ble');
  }
}

function onBleDisconnected() {
  if (blePollTimer) {
    clearInterval(blePollTimer);
    blePollTimer = null;
  }
  state.connected = false;
  state.transport = 'none';
  updateStatus('BLE Disconnected', 'none');
  syncConnectButtons(false, 'ble');
  logMsg('Watch disconnected from Bluetooth');
}

function disconnectBluetooth() {
  if (blePollTimer) {
    clearInterval(blePollTimer);
    blePollTimer = null;
  }
  if (state.ble.device && state.ble.device.gatt.connected) {
    state.ble.device.gatt.disconnect();
  }
}

// ---------------------------------------------------------------------
// 2. Wi-Fi Driver
// ---------------------------------------------------------------------
async function toggleWiFiConnection() {
  if (state.transport === 'wifi') {
    disconnectWiFi();
    return;
  }
  const ip = $('wifiIpInput').value.trim() || state.wifi.ip;
  state.wifi.ip = ip;
  localStorage.setItem('pg_wifi_ip', ip);
  startWiFiPolling();
}

function startWiFiPolling() {
  if (state.wifi.pollInterval) clearInterval(state.wifi.pollInterval);
  updateStatus('Connecting Wi-Fi...', 'none');
  logMsg(`Attempting Wi-Fi connection to ${state.wifi.ip}...`);

  let failCount = 0;
  const poll = async () => {
    try {
      // If served via local proxy, route through proxy with X-Target-IP; otherwise direct fetch
      const isProxy = window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1';
      const targetIp = state.wifi.ip || '192.168.0.196';
      const url = isProxy
        ? `/api/vitals?target=${encodeURIComponent(targetIp)}&since=${state.wifi.lastSeq}`
        : `http://${targetIp}/api/vitals?since=${state.wifi.lastSeq}`;

      const res = await fetch(url, {
        headers: { 'X-Target-IP': targetIp },
        cache: 'no-store'
      });
      if (!res.ok) throw new Error('HTTP ' + res.status);
      const d = await res.json();
      failCount = 0;

      if (!state.connected || state.transport !== 'wifi') {
        state.transport = 'wifi';
        state.connected = true;
        updateStatus(`Connected (Wi-Fi ${d.rssi || ''} dBm)`, 'wifi');
        syncConnectButtons(true, 'wifi');
        logMsg('Wi-Fi connection established! Receiving telemetry');
      }

      handleVitalsPacket({
        bpm: d.bpm,
        spo2: d.spo2,
        temp: d.temp,
        ebpm: d.ebpm,
        finger: d.finger,
        leadsOff: d.leads
      });

      if (d.ecg && Array.isArray(d.ecg)) {
        d.ecg.forEach((s) => pushEcgSample(s));
      }
      state.wifi.lastSeq = d.seq || 0;
    } catch (e) {
      failCount++;
      if (failCount > 2 && state.transport === 'wifi') {
        updateStatus('Wi-Fi Offline', 'none');
        state.connected = false;
        logMsg('Wi-Fi poll timeout: check that device is powered and reachable');
      }
    }
  };

  poll();
  state.wifi.pollInterval = setInterval(poll, 1000);
}

function disconnectWiFi() {
  if (state.wifi.pollInterval) {
    clearInterval(state.wifi.pollInterval);
    state.wifi.pollInterval = null;
  }
  if (state.transport === 'wifi') {
    state.transport = 'none';
    state.connected = false;
    updateStatus('Wi-Fi Disconnected', 'none');
    syncConnectButtons(false, 'wifi');
    logMsg('Wi-Fi disconnected');
  }
}

// ---------------------------------------------------------------------
// 3. Central Vitals Processing
// ---------------------------------------------------------------------
function handleVitalsPacket(data) {
  const v = state.vitals;
  if (data.bpm !== undefined && data.bpm >= 0) v.bpm = data.bpm;
  if (data.spo2 !== undefined && data.spo2 > 0) v.spo2 = data.spo2;
  if (data.temp !== undefined && data.temp > 0) v.temp = data.temp;
  if (data.ebpm !== undefined && data.ebpm >= 0) v.ebpm = data.ebpm;
  if (data.finger !== undefined) v.finger = !!data.finger;
  if (data.leadsOff !== undefined) v.leadsOff = !!data.leadsOff;

  // Heartbeat pulse effect
  if (v.finger && v.bpm > 0) {
    triggerHeartbeat();
    updateSessionStats(v.bpm, v.spo2);
  }

  // Update UI values
  $('bpmVal').textContent = v.bpm > 0 ? Math.round(v.bpm) : (v.finger ? 'Sampling...' : '--');
  $('spo2Val').textContent = v.spo2 > 0 ? Math.round(v.spo2) : '--';
  $('tempVal').textContent = v.temp > 0 ? v.temp.toFixed(1) : '--';

  // Progress Bar Widths
  $('bpmProgress').style.width = v.bpm > 0 ? Math.min(100, Math.max(0, (v.bpm - 40) / 1.4)) + '%' : '0%';
  $('spo2Progress').style.width = v.spo2 > 0 ? Math.min(100, Math.max(0, (v.spo2 - 70) * 3.33)) + '%' : '0%';
  $('tempProgress').style.width = v.temp > 0 ? Math.min(100, Math.max(0, (v.temp - 30) * 10)) + '%' : '0%';

  // Subtexts & Badges
  $('bpmSubtext').textContent = v.finger
    ? (v.bpm > 120 ? 'Tachycardia / Elevated' : v.bpm < 50 ? 'Bradycardia / Low' : 'Optimal Resting Range')
    : 'Place finger on pulse sensor';

  $('bpmBadge').textContent = v.finger && v.bpm > 0 ? (v.bpm < 50 ? 'LOW' : v.bpm > 100 ? 'ELEVATED' : 'NORMAL') : 'WAITING';
  $('spo2Badge').textContent = v.spo2 >= 95 ? 'OPTIMAL' : v.spo2 > 0 ? 'ALERT' : '--';
  $('tempBadge').textContent = v.temp > 37.8 ? 'FEVER' : v.temp > 0 ? 'NORMAL' : '--';

  // ECG Leads status
  $('ecgLeadsBadge').textContent = v.leadsOff ? 'LEADS DISCONNECTED' : (v.ebpm > 0 ? `ECG ${Math.round(v.ebpm)} BPM` : 'RECORDING');
  $('ecgLeadsBadge').style.color = v.leadsOff ? '#f87171' : '#34d399';

  updateBanner();

  if (v.finger && (v.bpm > 0 || !v.leadsOff)) {
    logSessionData();
  }
}

function triggerHeartbeat() {
  const el = $('heartIcon');
  el.classList.add('beating');
  setTimeout(() => el.classList.remove('beating'), 140);
  playHeartBeep();
}

function updateSessionStats(bpm, spo2) {
  const s = state.stats;
  s.hrSum += bpm;
  s.hrCount++;
  if (!s.hrMin || bpm < s.hrMin) s.hrMin = Math.round(bpm);
  if (bpm > s.hrMax) s.hrMax = Math.round(bpm);
  if (spo2 > 0 && (!s.spo2Min || spo2 < s.spo2Min)) s.spo2Min = Math.round(spo2);

  $('statHrAvg').textContent = s.hrCount ? Math.round(s.hrSum / s.hrCount) : '--';
  $('statHrMin').textContent = s.hrMin || '--';
  $('statHrMax').textContent = s.hrMax || '--';
  $('statSpo2Min').textContent = s.spo2Min ? s.spo2Min + '%' : '--';
}

function updateBanner() {
  const b = $('alertBanner');
  const v = state.vitals;
  const alerts = [];

  if (v.finger && v.bpm > 120) alerts.push('Elevated Heart Rate (>120 bpm)');
  if (v.finger && v.bpm > 0 && v.bpm < 50) alerts.push('Low Heart Rate (<50 bpm)');
  if (v.spo2 > 0 && v.spo2 < 92) alerts.push('Low Blood Oxygen (<92%)');
  if (v.temp > 38.0) alerts.push('High Body Temperature (>38°C)');

  if (alerts.length > 0) {
    b.className = 'alert-banner warning';
    b.textContent = '⚠️ ' + alerts.join(' • ');
  } else if (!v.finger && v.leadsOff) {
    b.className = 'alert-banner idle';
    b.textContent = 'Touch the pulse sensor or attach ECG electrodes to begin monitoring';
  } else {
    b.className = 'alert-banner ok';
    b.textContent = '✓ All Vital Signs Within Normal Parameters';
  }
}

function updateStatus(text, mode) {
  const pill = $('connPill');
  const statusText = $('connStatusText');
  pill.className = 'conn-pill ' + mode;
  statusText.textContent = text;
}

function syncConnectButtons(connected, type) {
  const btnBleQuick = $('btnBleQuick');
  const btnWifiQuick = $('btnWifiQuick');
  const btnBleConnect = $('btnBleConnect');
  const btnWifiConnect = $('btnWifiConnect');

  if (connected) {
    if (type === 'ble') {
      if (btnBleQuick) btnBleQuick.textContent = 'Disconnect BLE';
      if (btnBleConnect) btnBleConnect.textContent = 'Disconnect BLE';
    } else {
      if (btnWifiQuick) btnWifiQuick.textContent = 'Disconnect Wi-Fi';
      if (btnWifiConnect) btnWifiConnect.textContent = 'Disconnect Wi-Fi';
    }
  } else {
    if (btnBleQuick) btnBleQuick.textContent = 'Connect Bluetooth';
    if (btnBleConnect) btnBleConnect.textContent = 'Connect via Bluetooth';
    if (btnWifiQuick) btnWifiQuick.textContent = 'Connect Wi-Fi';
    if (btnWifiConnect) btnWifiConnect.textContent = 'Connect via Wi-Fi';
  }
}

// ---------------------------------------------------------------------
// 4. Real-Time 60 FPS ECG Oscilloscope
// ---------------------------------------------------------------------
const MAX_ECG_POINTS = 600;
function pushEcgSample(sample) {
  state.ecgBuffer.push(sample);
  if (state.ecgBuffer.length > MAX_ECG_POINTS) {
    state.ecgBuffer.shift();
  }
}

function initEcgCanvas() {
  const canvas = $('ecgCanvas');
  const ctx = canvas.getContext('2d');

  function resize() {
    const dpr = window.devicePixelRatio || 1;
    canvas.width = canvas.clientWidth * dpr;
    canvas.height = canvas.clientHeight * dpr;
  }
  window.addEventListener('resize', resize);
  resize();

  function render() {
    const w = canvas.width;
    const h = canvas.height;
    ctx.clearRect(0, 0, w, h);

    // Grid
    ctx.strokeStyle = 'rgba(0, 255, 136, 0.06)';
    ctx.lineWidth = 1;
    const gridX = w / 24;
    const gridY = h / 8;
    for (let x = 0; x < w; x += gridX) {
      ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, h); ctx.stroke();
    }
    for (let y = 0; y < h; y += gridY) {
      ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(w, y); ctx.stroke();
    }

    const buf = state.ecgBuffer;
    if (state.vitals.leadsOff || buf.length < 2) {
      ctx.fillStyle = '#64748b';
      ctx.font = `${13 * (window.devicePixelRatio || 1)}px system-ui`;
      ctx.textAlign = 'center';
      ctx.fillText(state.vitals.leadsOff ? 'Attach ECG Electrodes' : 'Awaiting ECG Signal...', w / 2, h / 2);
      requestAnimationFrame(render);
      return;
    }

    // Auto-scale
    let min = Infinity, max = -Infinity;
    for (let i = 0; i < buf.length; i++) {
      if (buf[i] < min) min = buf[i];
      if (buf[i] > max) max = buf[i];
    }
    if (max - min < 80) {
      const mid = (max + min) / 2;
      min = mid - 40;
      max = mid + 40;
    }

    // Neon trace
    ctx.strokeStyle = '#00ff88';
    ctx.lineWidth = 2 * (window.devicePixelRatio || 1);
    ctx.lineJoin = 'round';
    ctx.shadowColor = '#00ff88';
    ctx.shadowBlur = 10;

    ctx.beginPath();
    for (let i = 0; i < buf.length; i++) {
      const x = (i / (MAX_ECG_POINTS - 1)) * w;
      const normalized = (buf[i] - min) / (max - min);
      const y = h - (normalized * (h * 0.78) + h * 0.11);
      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    }
    ctx.stroke();
    ctx.shadowBlur = 0;

    requestAnimationFrame(render);
  }
  requestAnimationFrame(render);
}

// ---------------------------------------------------------------------
// 5. Data Logging & CSV Export
// ---------------------------------------------------------------------
let lastLogTime = 0;
function logSessionData() {
  const now = Date.now();
  if (now - lastLogTime < 3000) return;
  lastLogTime = now;

  const row = {
    timestamp: new Date().toLocaleTimeString(),
    bpm: Math.round(state.vitals.bpm),
    spo2: Math.round(state.vitals.spo2),
    temp: state.vitals.temp.toFixed(1),
    ecgBpm: Math.round(state.vitals.ebpm)
  };
  state.sessionLog.push(row);
  if (state.sessionLog.length > 500) state.sessionLog.shift();
}

function exportCsv() {
  if (state.sessionLog.length === 0) {
    alert('No active session data recorded yet.');
    return;
  }
  let csv = 'Timestamp,HeartRate_PPG,HeartRate_ECG,SpO2,Temperature_C\n';
  state.sessionLog.forEach((r) => {
    csv += `${r.timestamp},${r.bpm},${r.ecgBpm},${r.spo2},${r.temp}\n`;
  });
  const blob = new Blob([csv], { type: 'text/csv' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = `Vitals_Session_${Date.now()}.csv`;
  a.click();
}

// ---------------------------------------------------------------------
// 6. Navigation & Settings
// ---------------------------------------------------------------------
function setupNavigation() {
  const tabs = document.querySelectorAll('.nav-item');
  tabs.forEach((tab) => {
    tab.addEventListener('click', () => {
      tabs.forEach((t) => t.classList.remove('active'));
      tab.classList.add('active');
      const target = tab.dataset.tab;
      document.querySelectorAll('.tab-content').forEach((tc) => {
        tc.classList.toggle('active', tc.id === target);
      });
    });
  });
}

// ---------------------------------------------------------------------
// Initialization
// ---------------------------------------------------------------------
window.addEventListener('DOMContentLoaded', () => {
  initEcgCanvas();
  setupNavigation();

  // Bluetooth Buttons
  $('btnBleConnect').addEventListener('click', () => {
    if (state.transport === 'ble') disconnectBluetooth();
    else connectBluetooth();
  });
  $('btnBleQuick').addEventListener('click', () => {
    if (state.transport === 'ble') disconnectBluetooth();
    else connectBluetooth();
  });

  // Wi-Fi Buttons
  $('btnWifiConnect').addEventListener('click', toggleWiFiConnection);
  $('btnWifiQuick').addEventListener('click', toggleWiFiConnection);

  // Sound & Export
  $('btnExportCsv').addEventListener('click', exportCsv);
  $('btnSoundToggle').addEventListener('click', () => {
    state.soundEnabled = !state.soundEnabled;
    $('btnSoundToggle').classList.toggle('active', state.soundEnabled);
    logMsg(`Heartbeat chime: ${state.soundEnabled ? 'ON' : 'OFF'}`);
  });

  // Console toggle
  $('btnToggleConsole').addEventListener('click', () => {
    const el = $('consoleDrawer');
    el.style.display = el.style.display === 'none' ? 'block' : 'none';
  });

  $('wifiIpInput').value = state.wifi.ip;

  logMsg('PulseGuard app initialized. Ready to connect via Bluetooth or Wi-Fi.');

  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('./sw.js').catch((e) => {});
  }
});
