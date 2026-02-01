function $(id) {
  return document.getElementById(id);
}

function formatBytes(bytes) {
  if (typeof bytes !== 'number' || Number.isNaN(bytes)) return '';
  const units = ['B', 'KB', 'MB', 'GB'];
  let v = bytes;
  let i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i += 1;
  }
  return `${v.toFixed(i === 0 ? 0 : 1)} ${units[i]}`;
}

function backendUrl() {
  return ($('backendUrl').value || 'http://localhost:3000').replace(/\/$/, '');
}

const AUTH_STORAGE_KEY = 'scoutai_auth_v1';

let mePortraitUrl = null;

function loadAuth() {
  try {
    const raw = localStorage.getItem(AUTH_STORAGE_KEY);
    if (!raw) return { token: null, me: null };
    const parsed = JSON.parse(raw);
    return { token: parsed.token || null, me: parsed.me || null };
  } catch {
    return { token: null, me: null };
  }
}

function saveAuth(state) {
  localStorage.setItem(AUTH_STORAGE_KEY, JSON.stringify(state));
}

function clearAuth() {
  localStorage.removeItem(AUTH_STORAGE_KEY);
}

function authHeader() {
  const { token } = loadAuth();
  if (!token) return {};
  return { Authorization: `Bearer ${token}` };
}

async function fetchJson(url, init) {
  const res = await fetch(url, init);
  if (!res.ok) {
    const txt = await res.text().catch(() => '');
    throw new Error(`${res.status} ${res.statusText} ${txt}`);
  }
  return res.json();
}

async function fetchJsonAuth(url, init) {
  const headers = { ...(init && init.headers ? init.headers : {}), ...authHeader() };
  return fetchJson(url, { ...(init || {}), headers });
}

async function refreshMe() {
  const state = loadAuth();
  if (!state.token) {
    setStatus($('authStatus'), 'Not logged in.');
    return;
  }
  try {
    const me = await fetchJsonAuth(`${backendUrl()}/auth/me`);
    saveAuth({ token: state.token, me });
    const role = me && me.role ? me.role : 'unknown';
    setStatus($('authStatus'), `Logged in as ${me.email || '-'} (${role})`);
    if (me && me.role === 'player') {
      if (typeof me.displayName === 'string' && me.displayName.trim()) $('cardName').value = me.displayName;
      if (typeof me.position === 'string' && me.position.trim()) $('cardPos').value = me.position;
      if (typeof me.nation === 'string' && me.nation.trim()) $('cardNation').value = me.nation;
      renderCardIdentity();
      if (lastCardComputed) renderPlayerCard();
    }
    await refreshMePortrait();
  } catch (e) {
    console.error(e);
    clearAuth();
    setStatus($('authStatus'), `Auth error: ${e.message}`);
  }
}

async function refreshMePortrait() {
  const state = loadAuth();
  if (!state.token || !state.me || state.me.role !== 'player') {
    mePortraitUrl = null;
    return;
  }
  try {
    const res = await fetch(`${backendUrl()}/me/portrait`, { headers: { ...authHeader() } });
    if (!res.ok) {
      mePortraitUrl = null;
      return;
    }
    const blob = await res.blob();
    if (!blob || !blob.size) {
      mePortraitUrl = null;
      return;
    }
    if (mePortraitUrl) URL.revokeObjectURL(mePortraitUrl);
    mePortraitUrl = URL.createObjectURL(blob);
    $('cardPortrait').src = mePortraitUrl;
    renderPlayerCard();
  } catch {
    mePortraitUrl = null;
  }
}

async function registerUser() {
  const email = ($('authEmail').value || '').trim();
  const password = $('authPassword').value || '';
  const role = $('authRole').value || 'player';
  const displayName = ($('authDisplayName') && $('authDisplayName').value ? $('authDisplayName').value : '').trim();
  const position = ($('authPosition') && $('authPosition').value ? $('authPosition').value : '').trim();
  const nation = ($('authNation') && $('authNation').value ? $('authNation').value : '').trim();
  if (!email || !password) {
    setStatus($('authStatus'), 'Enter email and password.');
    return;
  }
  setStatus($('authStatus'), 'Registering…');
  try {
    const res = await fetchJson(`${backendUrl()}/auth/signup`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password, role, displayName, position, nation }),
    });
    saveAuth({ token: res.accessToken, me: null });
    await refreshMe();

    const portraitInput = $('authPortrait');
    const portraitFile =
      portraitInput && portraitInput.files && portraitInput.files.length ? portraitInput.files[0] : null;
    if (portraitFile && loadAuth().me && loadAuth().me.role === 'player') {
      await uploadMePortrait(portraitFile);
      await refreshMe();
    }

    await loadVideos();
  } catch (e) {
    console.error(e);
    setStatus($('authStatus'), `Register error: ${e.message}`);
    return;
  }
}

async function uploadMePortrait(file) {
  const form = new FormData();
  form.append('file', file);
  await fetchJsonAuth(`${backendUrl()}/me/portrait`, {
    method: 'POST',
    body: form,
  });
}

async function loginUser() {
  const email = ($('authEmail').value || '').trim();
  const password = $('authPassword').value || '';
  if (!email || !password) {
    setStatus($('authStatus'), 'Enter email and password.');
    return;
  }
  setStatus($('authStatus'), 'Logging in…');
  try {
    const res = await fetchJson(`${backendUrl()}/auth/signin`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password }),
    });
    saveAuth({ token: res.accessToken, me: null });
    await refreshMe();
    await loadVideos();
  } catch (e) {
    console.error(e);
    setStatus($('authStatus'), `Login error: ${e.message}`);
    return;
  }
}

async function logoutUser() {
  clearAuth();
  if (mePortraitUrl) {
    URL.revokeObjectURL(mePortraitUrl);
    mePortraitUrl = null;
  }
  setStatus($('authStatus'), 'Logged out.');
  await loadVideos();
}

function setStatus(el, msg) {
  el.textContent = msg;
}

let player;
let overlay;
let ctx;
let currentVideo = null;
let selection = null;
let dragging = null;
let analysisPositions = null;
let analysisSelectionSize = null;
let analysisCursor = 0;
let analysisRange = null;
let calibPickMode = null;
let playerWrap = null;
let lastCardComputed = null;

function clamp(n, min, max) {
  if (!Number.isFinite(n)) return min;
  return Math.max(min, Math.min(max, n));
}

function scoreFromRange(value, min, max) {
  if (!Number.isFinite(value)) return null;
  const t = (value - min) / Math.max(1e-6, max - min);
  return clamp(Math.round(t * 99), 1, 99);
}

function angleDiff(a, b) {
  let d = a - b;
  while (d > Math.PI) d -= 2 * Math.PI;
  while (d < -Math.PI) d += 2 * Math.PI;
  return d;
}

function computePathStats(positions) {
  if (!positions || positions.length < 2) {
    return {
      totalPx: 0,
      avgPxPerS: 0,
      maxPxPerS: 0,
      maxPxPerS2: 0,
      turnDegPerS: 0,
      smoothness: 0,
    };
  }
  let totalPx = 0;
  let maxPxPerS = 0;
  let maxPxPerS2 = 0;
  let lastSpeed = null;
  let lastHeading = null;
  let turnSum = 0;
  let turnCount = 0;

  for (let i = 1; i < positions.length; i += 1) {
    const a = positions[i - 1];
    const b = positions[i];
    const dt = (b.t ?? 0) - (a.t ?? 0);
    if (!Number.isFinite(dt) || dt <= 0) continue;
    const dx = (b.cx ?? 0) - (a.cx ?? 0);
    const dy = (b.cy ?? 0) - (a.cy ?? 0);
    if (!Number.isFinite(dx) || !Number.isFinite(dy)) continue;
    const d = Math.sqrt(dx * dx + dy * dy);
    const speed = d / dt;
    totalPx += d;
    if (speed > maxPxPerS) maxPxPerS = speed;
    if (lastSpeed !== null) {
      const acc = (speed - lastSpeed) / dt;
      if (acc > maxPxPerS2) maxPxPerS2 = acc;
    }
    const heading = Math.atan2(dy, dx);
    if (lastHeading !== null && speed > 5) {
      const dtheta = Math.abs(angleDiff(heading, lastHeading));
      const turnRate = (dtheta * 180) / Math.PI / dt;
      if (Number.isFinite(turnRate)) {
        turnSum += turnRate;
        turnCount += 1;
      }
    }
    lastHeading = heading;
    lastSpeed = speed;
  }

  const duration = (positions[positions.length - 1].t ?? 0) - (positions[0].t ?? 0);
  const avgPxPerS = Number.isFinite(duration) && duration > 0 ? totalPx / duration : 0;
  const smoothness = maxPxPerS > 0 ? avgPxPerS / maxPxPerS : 0;
  const turnDegPerS = turnCount ? turnSum / turnCount : 0;

  return {
    totalPx,
    avgPxPerS,
    maxPxPerS,
    maxPxPerS2,
    turnDegPerS,
    smoothness,
  };
}

function computeCardStats(metrics, positions, debug, posLabel) {
  const path = computePathStats(positions);
  const meterPerPx = debug && Number.isFinite(debug.meterPerPx) ? debug.meterPerPx : null;
  const calibrated = debug && typeof debug.calibrated === 'boolean' ? debug.calibrated : false;

  let maxKmh = Number.isFinite(metrics.maxSpeedKmh) ? metrics.maxSpeedKmh : null;
  let avgKmh = Number.isFinite(metrics.avgSpeedKmh) ? metrics.avgSpeedKmh : null;
  let distanceM = Number.isFinite(metrics.distanceMeters) ? metrics.distanceMeters : null;
  let accel = Array.isArray(metrics.accelPeaks) && metrics.accelPeaks.length ? metrics.accelPeaks[0] : null;

  if ((!Number.isFinite(maxKmh) || !Number.isFinite(avgKmh) || !Number.isFinite(distanceM) || !Number.isFinite(accel)) && meterPerPx) {
    const maxMps = path.maxPxPerS * meterPerPx;
    const avgMps = path.avgPxPerS * meterPerPx;
    maxKmh = Number.isFinite(maxKmh) ? maxKmh : maxMps * 3.6;
    avgKmh = Number.isFinite(avgKmh) ? avgKmh : avgMps * 3.6;
    distanceM = Number.isFinite(distanceM) ? distanceM : path.totalPx * meterPerPx;
    accel = Number.isFinite(accel) ? accel : path.maxPxPerS2 * meterPerPx;
  }

  const durationS = positions && positions.length >= 2 ? (positions[positions.length - 1].t ?? 0) - (positions[0].t ?? 0) : 0;
  const distancePerMin = Number.isFinite(distanceM) && durationS > 0 ? (distanceM / durationS) * 60 : null;

  const pac = scoreFromRange(maxKmh, 18, 35);
  const shoBase = Number.isFinite(accel) ? accel : null;
  const sho = shoBase === null ? null : clamp(Math.round(0.6 * scoreFromRange(shoBase, 1.2, 6.0) + 0.4 * (pac ?? 50)), 1, 99);
  const pas = scoreFromRange(path.smoothness, 0.15, 0.75);
  const dri = scoreFromRange(path.turnDegPerS, 4, 55);
  const def = scoreFromRange(distancePerMin, 40, 170);
  const phyBase = distancePerMin === null ? null : clamp(Math.round(0.6 * (def ?? 50) + 0.4 * scoreFromRange(shoBase, 1.2, 6.0)), 1, 99);

  const stats = {
    PAC: pac ?? 50,
    SHO: sho ?? 50,
    PAS: pas ?? 50,
    DRI: dri ?? 50,
    DEF: def ?? 50,
    PHY: phyBase ?? 50,
  };

  const pos = String(posLabel || '').toUpperCase();
  let w;
  if (/(ST|CF|LW|RW)/.test(pos)) {
    w = { PAC: 0.24, SHO: 0.24, PAS: 0.10, DRI: 0.18, DEF: 0.10, PHY: 0.14 };
  } else if (/(CB|LB|RB)/.test(pos)) {
    w = { PAC: 0.16, SHO: 0.10, PAS: 0.12, DRI: 0.10, DEF: 0.32, PHY: 0.20 };
  } else {
    w = { PAC: 0.18, SHO: 0.12, PAS: 0.22, DRI: 0.20, DEF: 0.14, PHY: 0.14 };
  }

  const ovr = clamp(
    Math.round(
      stats.PAC * w.PAC + stats.SHO * w.SHO + stats.PAS * w.PAS + stats.DRI * w.DRI + stats.DEF * w.DEF + stats.PHY * w.PHY,
    ),
    1,
    99,
  );

  return {
    ovr,
    stats,
    calibrated,
    calibrationKind: debug && typeof debug.calibrationKind === 'string' ? debug.calibrationKind : null,
  };
}

async function capturePortrait(selVideo, t0) {
  if (!player || !selVideo) return null;
  if (!Number.isFinite(player.videoWidth) || !Number.isFinite(player.videoHeight) || player.videoWidth <= 0 || player.videoHeight <= 0) return null;

  const x = clamp(selVideo.x, 0, player.videoWidth - 1);
  const y = clamp(selVideo.y, 0, player.videoHeight - 1);
  const w = clamp(selVideo.w, 1, player.videoWidth - x);
  const h = clamp(selVideo.h, 1, player.videoHeight - y);

  const can = document.createElement('canvas');
  const outW = 220;
  const outH = 220;
  can.width = outW;
  can.height = outH;
  const c = can.getContext('2d');
  if (!c) return null;

  try {
    if (Number.isFinite(t0)) {
      player.currentTime = t0;
      await new Promise((resolve) => {
        const onSeeked = () => {
          player.removeEventListener('seeked', onSeeked);
          resolve();
        };
        player.addEventListener('seeked', onSeeked);
        setTimeout(resolve, 350);
      });
    }

    c.drawImage(player, x, y, w, h, 0, 0, outW, outH);
    return can.toDataURL('image/jpeg', 0.9);
  } catch (e) {
    console.warn('Portrait capture failed', e);
    return null;
  }
}

function renderCardIdentity() {
  $('cardNameOut').textContent = ($('cardName').value || '').toUpperCase() || 'SCOUT AI';
  $('cardPosOut').textContent = ($('cardPos').value || 'MOC').toUpperCase();
  $('cardNationOut').textContent = ($('cardNation').value || 'TN').toUpperCase();
}

function renderPlayerCard() {
  const root = $('playerCard');
  if (!lastCardComputed) {
    root.classList.add('hidden');
    return;
  }
  renderCardIdentity();
  $('cardOvr').textContent = String(lastCardComputed.ovr);
  $('statPAC').textContent = String(lastCardComputed.stats.PAC);
  $('statSHO').textContent = String(lastCardComputed.stats.SHO);
  $('statPAS').textContent = String(lastCardComputed.stats.PAS);
  $('statDRI').textContent = String(lastCardComputed.stats.DRI);
  $('statDEF').textContent = String(lastCardComputed.stats.DEF);
  $('statPHY').textContent = String(lastCardComputed.stats.PHY);

  const note = $('cardNote');
  const kind = lastCardComputed.calibrationKind;
  if (kind === 'auto_frame') note.textContent = 'Estimated card (auto calibration)';
  else if (lastCardComputed.calibrated) note.textContent = 'Calibrated card';
  else note.textContent = 'Uncalibrated card';

  root.classList.remove('hidden');
}

function syncOverlay() {
  if (!player || !overlay) return;
  const rect = player.getBoundingClientRect();
  overlay.width = Math.max(1, Math.floor(rect.width));
  overlay.height = Math.max(1, Math.floor(rect.height));
  drawTracking();
}

function rectFromPoints(a, b) {
  const x = Math.min(a.x, b.x);
  const y = Math.min(a.y, b.y);
  const w = Math.abs(a.x - b.x);
  const h = Math.abs(a.y - b.y);
  return { x, y, w, h };
}

function drawSelection(temp) {
  if (!ctx || !overlay) return;
  ctx.clearRect(0, 0, overlay.width, overlay.height);
  const rect = temp || selection;
  if (!rect) return;

  ctx.lineWidth = 2;
  ctx.strokeStyle = '#ff3b30';
  ctx.fillStyle = 'rgba(255, 59, 48, 0.2)';
  ctx.fillRect(rect.x, rect.y, rect.w, rect.h);
  ctx.strokeRect(rect.x, rect.y, rect.w, rect.h);
}

function resetAnalysisTracking() {
  analysisPositions = null;
  analysisSelectionSize = null;
  analysisCursor = 0;
  analysisRange = null;
  lastCardComputed = null;
  if ($('playerCard')) $('playerCard').classList.add('hidden');
}

function getTrackedPositionAt(time) {
  if (!analysisPositions || analysisPositions.length === 0) return null;
  while (analysisCursor < analysisPositions.length - 1 && analysisPositions[analysisCursor + 1].t <= time) {
    analysisCursor += 1;
  }
  const current = analysisPositions[analysisCursor];
  const next = analysisPositions[Math.min(analysisCursor + 1, analysisPositions.length - 1)];
  if (next && Math.abs(next.t - time) < Math.abs(current.t - time)) {
    return next;
  }
  return current;
}

function drawTracking() {
  if (!analysisPositions || !analysisPositions.length || !analysisSelectionSize) {
    drawSelection();
    return;
  }
  if (!player || !overlay) return;
  const now = player.currentTime || 0;
  if (analysisRange && (now < analysisRange.start - 0.2 || now > analysisRange.end + 0.2)) {
    ctx.clearRect(0, 0, overlay.width, overlay.height);
    return;
  }
  const pos = getTrackedPositionAt(now);
  if (!pos) {
    drawSelection();
    return;
  }
  const scaleX = player.videoWidth / overlay.width;
  const scaleY = player.videoHeight / overlay.height;
  if (!Number.isFinite(scaleX) || !Number.isFinite(scaleY) || scaleX <= 0 || scaleY <= 0) return;

  if (pos.bbox && pos.bbox.length === 4) {
    const x1 = pos.bbox[0];
    const y1 = pos.bbox[1];
    const x2 = pos.bbox[2];
    const y2 = pos.bbox[3];
    const x = x1 / scaleX;
    const y = y1 / scaleY;
    const w = (x2 - x1) / scaleX;
    const h = (y2 - y1) / scaleY;
    drawSelection({ x, y, w, h });
    return;
  }

  const w = analysisSelectionSize.w / scaleX;
  const h = analysisSelectionSize.h / scaleY;
  const x = (pos.cx - analysisSelectionSize.w / 2) / scaleX;
  const y = (pos.cy - analysisSelectionSize.h / 2) / scaleY;
  drawSelection({ x, y, w, h });
}

function selectionToVideo(sel) {
  if (!player || !overlay || !sel) return null;
  const scaleX = player.videoWidth / overlay.width;
  const scaleY = player.videoHeight / overlay.height;
  return {
    x: Math.max(0, Math.round(sel.x * scaleX)),
    y: Math.max(0, Math.round(sel.y * scaleY)),
    w: Math.max(1, Math.round(sel.w * scaleX)),
    h: Math.max(1, Math.round(sel.h * scaleY)),
  };
}

function readNumberInput(id) {
  const el = $(id);
  const raw = (el && typeof el.value === 'string' ? el.value : '').trim();
  if (!raw) return null;
  const value = Number(raw);
  return Number.isFinite(value) ? value : null;
}

function setNumberInput(id, value) {
  $(id).value = Number.isFinite(value) ? String(Math.round(value)) : '';
}

function readCalibrationInputs() {
  return {
    distance: readNumberInput('calibDistance'),
    ax: readNumberInput('calibAx'),
    ay: readNumberInput('calibAy'),
    bx: readNumberInput('calibBx'),
    by: readNumberInput('calibBy'),
  };
}

function getCalibrationPayload() {
  const { distance, ax, ay, bx, by } = readCalibrationInputs();
  if (!Number.isFinite(distance) || distance <= 0) return null;
  if (!Number.isFinite(ax) || !Number.isFinite(ay) || !Number.isFinite(bx) || !Number.isFinite(by)) return null;
  const dx = bx - ax;
  const dy = by - ay;
  const dpx = Math.sqrt(dx * dx + dy * dy);
  if (!Number.isFinite(dpx) || dpx < 2) return null;
  return {
    type: 'two_points',
    x1: ax,
    y1: ay,
    x2: bx,
    y2: by,
    distance_m: distance,
  };
}

function updateCalibrationStatus(message) {
  const status = $('calibStatus');
  if (message) {
    status.textContent = message;
    return;
  }
  if (calibPickMode) {
    status.textContent = `Click on the video to set point ${calibPickMode}.`;
    return;
  }
  const { distance, ax, ay, bx, by } = readCalibrationInputs();
  const haveAny = [distance, ax, ay, bx, by].some((v) => v !== null);
  const payload = getCalibrationPayload();
  if (payload) {
    status.textContent = 'Calibration ready ✓';
    return;
  }
  if (!haveAny) {
    status.textContent = 'Pick two points and enter the distance for real stats.';
    return;
  }
  if (distance === null) {
    status.textContent = 'Calibration invalid: enter Distance A-B (meters).';
    return;
  }
  if (!Number.isFinite(distance) || distance <= 0) {
    status.textContent = 'Calibration invalid: distance must be > 0.';
    return;
  }
  if (![ax, ay, bx, by].every((v) => Number.isFinite(v))) {
    status.textContent = 'Calibration invalid: missing point coordinates.';
    return;
  }
  if (ax === bx && ay === by) {
    status.textContent = 'Calibration invalid: point A and B are the same. Pick two different points.';
    return;
  }
  status.textContent = 'Calibration invalid: points are too close. Pick points farther apart.';
}

function setCalibrationPickMode(mode) {
  calibPickMode = mode;
  if (playerWrap) {
    if (calibPickMode) playerWrap.classList.add('calib-pick');
    else playerWrap.classList.remove('calib-pick');
  }
  updateCalibrationStatus();
}

function clearCalibration() {
  calibPickMode = null;
  if (playerWrap) playerWrap.classList.remove('calib-pick');
  setNumberInput('calibAx', null);
  setNumberInput('calibAy', null);
  setNumberInput('calibBx', null);
  setNumberInput('calibBy', null);
  $('calibDistance').value = '';
  updateCalibrationStatus();
}

function handleCalibrationPick(e) {
  if (!currentVideo) return false;
  if (!calibPickMode) return false;
  e.preventDefault();
  e.stopPropagation();
  const point = pointerEventToVideoPoint(e);
  if (!point) return true;
  if (calibPickMode === 'A') {
    setNumberInput('calibAx', point.x);
    setNumberInput('calibAy', point.y);
  } else {
    setNumberInput('calibBx', point.x);
    setNumberInput('calibBy', point.y);
  }
  setCalibrationPickMode(null);
  updateCalibrationStatus();
  return true;
}

function pointerEventToVideoPoint(e) {
  if (!player) return null;
  const rect = player.getBoundingClientRect();
  const scaleX = player.videoWidth / rect.width;
  const scaleY = player.videoHeight / rect.height;
  if (!Number.isFinite(scaleX) || !Number.isFinite(scaleY) || scaleX <= 0 || scaleY <= 0) return null;
  const x = Math.max(0, Math.round((e.clientX - rect.left) * scaleX));
  const y = Math.max(0, Math.round((e.clientY - rect.top) * scaleY));
  return { x, y };
}

function getSamplingFps() {
  const value = Number($('samplingFps').value);
  if (!Number.isFinite(value) || value <= 0) return 3;
  return Math.max(1, Math.round(value));
}

function updateSelectionMeta() {
  const meta = $('selectionMeta');
  if (!selection || !player) {
    meta.textContent = 'No selection yet.';
    return;
  }

  const selVideo = selectionToVideo(selection);
  const t0 = player.currentTime || 0;
  meta.textContent = `Selection: x=${selVideo.x}, y=${selVideo.y}, w=${selVideo.w}, h=${selVideo.h} @ t0=${t0.toFixed(2)}s`;
}

function setAnalyzeEnabled(enabled) {
  const btn = $('analyzeBtn');
  btn.disabled = !enabled;
}

function clearSelection() {
  selection = null;
  dragging = null;
  resetAnalysisTracking();
  drawSelection();
  updateSelectionMeta();
  setAnalyzeEnabled(false);
}

function renderList(videos) {
  const root = $('videosList');
  root.innerHTML = '';

  if (!videos.length) {
    root.innerHTML = '<div class="muted">No videos uploaded yet.</div>';
    return;
  }

  for (const v of videos) {
    const div = document.createElement('div');
    div.className = 'item';

    const top = document.createElement('div');
    top.className = 'top';

    const name = document.createElement('div');
    name.className = 'name';
    name.textContent = v.originalName || v.filename || v._id;

    const actions = document.createElement('div');

    const playBtn = document.createElement('button');
    playBtn.className = 'btn';
    playBtn.textContent = 'Play';
    playBtn.onclick = () => playVideo(v);

    const copyBtn = document.createElement('button');
    copyBtn.className = 'btn';
    copyBtn.textContent = 'Copy stream URL';
    copyBtn.onclick = async () => {
      const url = `${backendUrl()}/videos/${v._id}/stream`;
      await navigator.clipboard.writeText(url);
      alert('Copied!');
    };

    actions.appendChild(playBtn);
    actions.appendChild(copyBtn);

    top.appendChild(name);
    top.appendChild(actions);

    const meta = document.createElement('div');
    meta.className = 'meta';
    meta.textContent = `id=${v._id} | type=${v.mimeType || '-'} | size=${formatBytes(v.size)} | path=${v.relativePath}`;

    div.appendChild(top);
    div.appendChild(meta);
    root.appendChild(div);
  }
}

async function loadVideos() {
  setStatus($('listStatus'), 'Loading…');
  try {
    const { me, token } = loadAuth();
    const useMe = Boolean(token) && me && me.role === 'player';
    const url = useMe ? `${backendUrl()}/me/videos` : `${backendUrl()}/videos`;
    const videos = useMe ? await fetchJsonAuth(url) : await fetchJson(url);
    renderList(videos);
    setStatus($('listStatus'), `Loaded ${videos.length} video(s).`);
  } catch (e) {
    console.error(e);
    setStatus($('listStatus'), `Error: ${e.message}`);
  }
}

function playVideo(v) {
  const url = `${backendUrl()}/videos/${v._id}/stream`;
  currentVideo = v;
  player.src = url;
  player.load();
  $('playerMeta').textContent = `Playing: ${v.originalName || v.filename} (${url})`;
  $('analysisResult').textContent = '';
  clearSelection();
  clearCalibration();
  if ($('playerCard')) $('playerCard').classList.add('hidden');
  setTimeout(syncOverlay, 0);
}

async function analyzeSelection() {
  if (!currentVideo) {
    alert('Select a video first.');
    return;
  }
  if (!selection) {
    alert('Draw a selection on the player first.');
    return;
  }

  const selVideo = selectionToVideo(selection);
  if (!selVideo || selVideo.w < 10 || selVideo.h < 10) {
    alert('Selection too small. Draw a bigger box around the player.');
    return;
  }
  const payload = {
    selection: {
      t0: Number((player.currentTime || 0).toFixed(2)),
      x: selVideo.x,
      y: selVideo.y,
      w: selVideo.w,
      h: selVideo.h,
    },
    samplingFps: getSamplingFps(),
  };
  const calibration = getCalibrationPayload();
  if (calibration) {
    payload.calibration = calibration;
  }

  const startedAt = performance.now();
  console.log('Analyze payload', payload);

  const resultEl = $('analysisResult');
  resultEl.textContent = 'Analyzing…';
  setAnalyzeEnabled(false);

  try {
    const { me, token } = loadAuth();
    if (!token || !me) {
      resultEl.textContent = 'Sign in as a scouter to run analysis.';
      return;
    }
    if (me.role !== 'scouter') {
      resultEl.textContent = 'Only scouters can run AI analysis.';
      return;
    }

    const res = await fetchJsonAuth(`${backendUrl()}/videos/${currentVideo._id}/analyze`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });

    const elapsedS = (performance.now() - startedAt) / 1000;
    console.log('Analyze response', res);

    const positions = res.positions || [];
    if (!positions.length) {
      resultEl.textContent = 'No tracked positions. Try a bigger box and analyze again.';
      return;
    }

    analysisPositions = positions;
    analysisSelectionSize = { w: selVideo.w, h: selVideo.h };
    analysisCursor = 0;
    analysisRange = {
      start: positions[0].t ?? payload.selection.t0,
      end: positions[positions.length - 1].t ?? payload.selection.t0,
    };
    drawTracking();

    if (Number.isFinite(payload.selection.t0)) {
      player.currentTime = payload.selection.t0;
      player.play().catch(() => {
        // Autoplay might be blocked; user can press play.
      });
    }

    const metrics = res.metrics || res;
    const lines = [];
    const aiDebug = res.debug || null;
    const hasCalibration = aiDebug && typeof aiDebug.calibrated === 'boolean' ? aiDebug.calibrated : Boolean(payload.calibration);
    const calibKind = aiDebug && typeof aiDebug.calibrationKind === 'string' ? aiDebug.calibrationKind : null;
    const distanceMeters = Number.isFinite(metrics.distanceMeters) ? metrics.distanceMeters : null;
    const distanceLabel = distanceMeters === null ? 'n/a (needs calibration)' : distanceMeters.toFixed(2);
    const distanceKmLabel = distanceMeters === null ? null : (distanceMeters / 1000).toFixed(2);
    const avgLabel = metrics.avgSpeedKmh ?? 'n/a (needs calibration)';
    const maxLabel = metrics.maxSpeedKmh ?? 'n/a (needs calibration)';
    const accelPeak = Array.isArray(metrics.accelPeaks) && metrics.accelPeaks.length ? metrics.accelPeaks[0] : null;
    const estSuffix = calibKind === 'auto_frame' ? ' (estimated)' : '';

    lines.push(
      distanceKmLabel
        ? `distance: ${distanceLabel} m${estSuffix} (${distanceKmLabel} km)`
        : `distance: ${distanceLabel} m${estSuffix}`,
    );
    lines.push(`avg speed: ${avgLabel} km/h`);
    lines.push(`max speed: ${maxLabel} km/h`);
    lines.push(`sprints: ${hasCalibration ? metrics.sprintCount ?? 'n/a' : 'n/a (needs calibration)'}`);
    lines.push(`accel peak: ${hasCalibration ? accelPeak ?? 'n/a' : 'n/a (needs calibration)'} m/s²`);

    if (distanceMeters === null) {
      let totalPx = 0;
      let maxPxPerS = 0;
      for (let i = 1; i < positions.length; i += 1) {
        const a = positions[i - 1];
        const b = positions[i];
        const dt = (b.t ?? 0) - (a.t ?? 0);
        if (!Number.isFinite(dt) || dt <= 0) continue;
        const dx = (b.cx ?? 0) - (a.cx ?? 0);
        const dy = (b.cy ?? 0) - (a.cy ?? 0);
        if (!Number.isFinite(dx) || !Number.isFinite(dy)) continue;
        const d = Math.sqrt(dx * dx + dy * dy);
        totalPx += d;
        const v = d / dt;
        if (v > maxPxPerS) maxPxPerS = v;
      }
      const duration = (positions[positions.length - 1].t ?? 0) - (positions[0].t ?? 0);
      const avgPxPerS = Number.isFinite(duration) && duration > 0 ? totalPx / duration : 0;
      lines.push(`distance(px): ${totalPx.toFixed(1)} px`);
      lines.push(`avg speed(px/s): ${avgPxPerS.toFixed(1)}`);
      lines.push(`max speed(px/s): ${maxPxPerS.toFixed(1)}`);
    }
    const aiCalib = aiDebug && typeof aiDebug.calibrated === 'boolean' ? (aiDebug.calibrated ? 'yes' : 'no') : 'unknown';
    const aiFrames = aiDebug && Number.isFinite(aiDebug.framesSampled) ? aiDebug.framesSampled : 'n/a';
    const aiWindow =
      aiDebug && typeof aiDebug.windowMode === 'boolean'
        ? aiDebug.windowMode
          ? `on(${aiDebug.windowStart ?? '?'}..${aiDebug.windowEnd ?? '?'})`
          : 'off'
        : 'unknown';
    lines.push(
      `debug: elapsed=${elapsedS.toFixed(2)}s positions=${positions.length} samplingFps=${payload.samplingFps} payloadCalib=${payload.calibration ? 'yes' : 'no'} aiCalib=${aiCalib} window=${aiWindow} framesSampled=${aiFrames}`,
    );
    resultEl.textContent = lines.join('\n');

    // Render FIFA-style player card
    const posLabel = ($('cardPos').value || 'MOC').toUpperCase();
    lastCardComputed = computeCardStats(metrics, positions, aiDebug, posLabel);
    if (mePortraitUrl) {
      $('cardPortrait').src = mePortraitUrl;
    } else {
      const portraitUrl = await capturePortrait(selVideo, payload.selection.t0);
      if (portraitUrl) {
        $('cardPortrait').src = portraitUrl;
      } else {
        $('cardPortrait').removeAttribute('src');
      }
    }
    renderPlayerCard();
  } catch (e) {
    console.error(e);
    resultEl.textContent = `Error: ${e.message}`;
  } finally {
    setAnalyzeEnabled(true);
  }
}

async function uploadVideo() {
  const file = $('fileInput').files && $('fileInput').files[0];
  if (!file) {
    alert('Select a video file first.');
    return;
  }

  const btn = $('uploadBtn');
  btn.disabled = true;
  setStatus($('uploadStatus'), 'Uploading…');

  try {
    const form = new FormData();
    form.append('file', file);

    const { me, token } = loadAuth();
    const useMe = Boolean(token) && me && me.role === 'player';
    const url = useMe ? `${backendUrl()}/me/videos` : `${backendUrl()}/videos`;
    const res = useMe
      ? await fetchJsonAuth(url, {
          method: 'POST',
          body: form,
        })
      : await fetchJson(url, {
          method: 'POST',
          body: form,
        });

    setStatus($('uploadStatus'), `Uploaded: ${res._id}`);
    await loadVideos();
  } catch (e) {
    console.error(e);
    setStatus($('uploadStatus'), `Error: ${e.message}`);
  } finally {
    btn.disabled = false;
  }
}

window.addEventListener('DOMContentLoaded', () => {
  player = $('player');
  overlay = $('overlay');
  ctx = overlay.getContext('2d');
  playerWrap = overlay ? overlay.parentElement : null;

  renderCardIdentity();
  ['cardName', 'cardPos', 'cardNation'].forEach((id) => {
    $(id).addEventListener('input', () => renderPlayerCard());
  });

  overlay.addEventListener('pointerdown', (e) => {
    if (handleCalibrationPick(e)) return;
  });

  player.addEventListener('pointerdown', (e) => {
    if (!currentVideo) return;
    if (handleCalibrationPick(e)) return;
    const rect = player.getBoundingClientRect();
    const start = { x: e.clientX - rect.left, y: e.clientY - rect.top };
    dragging = { start, current: start, active: false };
    if (player.setPointerCapture) player.setPointerCapture(e.pointerId);
  });

  player.addEventListener('pointermove', (e) => {
    if (!dragging) return;
    const rect = player.getBoundingClientRect();
    dragging.current = { x: e.clientX - rect.left, y: e.clientY - rect.top };
    const selectionRect = rectFromPoints(dragging.start, dragging.current);
    if (!dragging.active && (selectionRect.w >= 5 || selectionRect.h >= 5)) {
      dragging.active = true;
      resetAnalysisTracking();
    }
    if (dragging.active) {
      drawSelection(selectionRect);
    }
  });

  player.addEventListener('pointerup', (e) => {
    if (!dragging) return;
    if (player.releasePointerCapture) player.releasePointerCapture(e.pointerId);
    const rect = rectFromPoints(dragging.start, dragging.current);
    const wasActive = dragging.active;
    dragging = null;
    if (!wasActive) {
      return;
    }
    if (rect.w < 5 || rect.h < 5) {
      clearSelection();
      return;
    }
    selection = rect;
    drawSelection();
    updateSelectionMeta();
    setAnalyzeEnabled(true);
  });

  player.addEventListener('pointercancel', () => {
    dragging = null;
    drawSelection();
  });

  player.addEventListener('loadedmetadata', syncOverlay);
  player.addEventListener('timeupdate', () => {
    if (!dragging) drawTracking();
  });
  player.addEventListener('seeking', () => {
    analysisCursor = 0;
    if (!dragging) drawTracking();
  });
  window.addEventListener('resize', syncOverlay);

  if ($('registerBtn')) $('registerBtn').addEventListener('click', () => registerUser());
  if ($('registerPlayerBtn'))
    $('registerPlayerBtn').addEventListener('click', () => {
      $('authRole').value = 'player';
      registerUser();
    });
  if ($('registerScouterBtn'))
    $('registerScouterBtn').addEventListener('click', () => {
      $('authRole').value = 'scouter';
      registerUser();
    });
  if ($('loginBtn')) $('loginBtn').addEventListener('click', () => loginUser());
  if ($('logoutBtn')) $('logoutBtn').addEventListener('click', () => logoutUser());

  $('reloadBtn').addEventListener('click', loadVideos);
  $('uploadBtn').addEventListener('click', uploadVideo);
  $('analyzeBtn').addEventListener('click', analyzeSelection);
  $('clearSelectionBtn').addEventListener('click', clearSelection);
  $('pickCalibA').addEventListener('click', () => setCalibrationPickMode('A'));
  $('pickCalibB').addEventListener('click', () => setCalibrationPickMode('B'));
  $('clearCalibBtn').addEventListener('click', clearCalibration);
  ['calibDistance', 'calibAx', 'calibAy', 'calibBx', 'calibBy'].forEach((id) => {
    $(id).addEventListener('input', () => updateCalibrationStatus());
  });
  updateCalibrationStatus();

  const state = loadAuth();
  if (state.me && state.me.email) {
    $('authEmail').value = state.me.email;
  }
  refreshMe().finally(() => {
    loadVideos();
  });
});
