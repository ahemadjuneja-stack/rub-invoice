// Ruby Key - the admin panel for Ruby Invoice.
// Dark, mobile-first PWA. Manages the `users` and `subscriptions`
// collections plus the `config/app` remote-control document.
// v0.3.0: READ-ONLY support view of a user's shops/{uid} data (bills,
// ledger, inventory, purchases, returns) - "user ka sara data Ruby Key
// par". Writes to shops/{uid} stay impossible (firestore.rules v4).
//
// Security:
//   * Google sign-in only (no sign-up).
//   * window.RUBY_KEY_ADMIN_EMAIL whitelist - any other Gmail is signed
//     out instantly with "Unauthorized Access" (also enforced by the
//     Firestore security rules, so the UI check is just the first gate).

import { initializeApp } from 'https://www.gstatic.com/firebasejs/10.14.1/firebase-app.js';
import {
  getAuth, GoogleAuthProvider, signInWithPopup, onAuthStateChanged, signOut,
} from 'https://www.gstatic.com/firebasejs/10.14.1/firebase-auth.js';
import {
  getFirestore, collection, onSnapshot, doc, updateDoc, addDoc,
  getDoc, setDoc, serverTimestamp, Timestamp,
  getDocs, query, orderBy, limit,
} from 'https://www.gstatic.com/firebasejs/10.14.1/firebase-firestore.js';

const cfg = window.RUBY_FIREBASE_CONFIG || {};
const ADMIN_EMAIL = String(window.RUBY_KEY_ADMIN_EMAIL || '').toLowerCase();
const appEl = document.getElementById('app');

const app = initializeApp(cfg);
const auth = getAuth(app);
const db = getFirestore(app);

// ---------------------------------------------------------------- state
let users = [];          // live snapshot of the users collection
let adminUser = null;    // signed-in Google account
let adminOk = false;     // passed the whitelist
let unsubUsers = null;   // Firestore listener
let unsubConfig = null;  // config/app remote-control listener
let unsubLiveUi = null;  // app_config/live_ui live-UI listener (v0.4.0)
let searchTerm = '';
let openIds = new Set(); // expanded user cards
let remoteCfg = {};      // live config/app values
let cfgDirty = false;    // admin typed something not saved yet
let liveUiCfg = {};      // live app_config/live_ui values (v0.4.0)
let liveUiDirty = false; // admin typed something in Live UI not saved yet

// ---------------------------------------------------------------- utils
const esc = (s) => String(s ?? '')
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;').replace(/'/g, '&#39;');

function toast(msg, isErr = false) {
  let t = document.getElementById('toast');
  if (!t) {
    t = document.createElement('div');
    t.id = 'toast';
    document.body.appendChild(t);
  }
  t.textContent = msg;
  t.classList.toggle('err', isErr);
  t.classList.add('show');
  clearTimeout(t._timer);
  t._timer = setTimeout(() => t.classList.remove('show'), 2600);
}

function toDate(v) {
  if (!v) return null;
  if (v.toDate) return v.toDate();           // Firestore Timestamp
  if (typeof v === 'number') return new Date(v);
  if (typeof v === 'string') { const d = new Date(v); return isNaN(d) ? null : d; }
  return null;
}
const fmtDate = (d) => d
  ? d.toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' })
  : '-';

// v0.3.0: no trial anymore - validity = subscriptionEndDate ?? expiryDate.
// Legacy trialEndDate values are IGNORED (old accounts stay usable until
// the admin sets a real end date or blocks them).
function effectiveEnd(u) {
  return toDate(u.subscriptionEndDate) || toDate(u.expiryDate);
}

function daysLeft(u) {
  const end = effectiveEnd(u);
  if (!end) return null;
  return Math.ceil((end.getTime() - Date.now()) / 86400000);
}

function userTag(u) {
  if (u.status === 'blocked') return ['blocked', 'BLOCKED'];
  if (u.status === 'pending') return ['pending', 'PENDING'];
  const dl = daysLeft(u);
  if (dl !== null && dl < 0) return ['expired', 'EXPIRED'];
  if (u.plan === 'paid' || toDate(u.subscriptionEndDate)) return ['paid', 'PAID'];
  return ['legacy', 'ACTIVE'];
}

function deviceCount(u) {
  const n = Array.isArray(u.registeredDevices) ? u.registeredDevices.length : 0;
  const max = Number(u.maxDevices ?? 2) || 2;
  return `${n}/${max}`;
}

const waLink = (mobile) => {
  let m = String(mobile || '').replace(/\D/g, '');
  if (m.length === 10) m = '91' + m;
  return m.length >= 11 ? `https://wa.me/${m}` : null;
};
const telLink = (mobile) => {
  const m = String(mobile || '').replace(/\D/g, '');
  return m.length >= 10 ? `tel:+${m}` : null;
};

// ---------------------------------------------------------------- views
function renderLogin() {
  appEl.innerHTML = `
    <div class="center">
      <div class="boot-logo">R</div>
      <div class="big">Ruby Key</div>
      <div class="small">Admin panel for Ruby Invoice - users, validity, subscriptions and devices.</div>
      <button class="google-btn" id="loginBtn">
        <svg viewBox="0 0 48 48"><path fill="#EA4335" d="M24 9.5c3.5 0 6.6 1.2 9 3.5l6.8-6.8C35.6 2.4 30.2 0 24 0 14.6 0 6.5 5.4 2.6 13.2l7.9 6.2C12.4 13.6 17.7 9.5 24 9.5z"/><path fill="#4285F4" d="M46.5 24.5c0-1.6-.1-3.1-.4-4.5H24v9h12.7c-.6 3-2.3 5.5-4.8 7.2l7.7 6c4.5-4.2 6.9-10.3 6.9-17.7z"/><path fill="#FBBC05" d="M10.5 28.6c-.5-1.4-.8-3-.8-4.6s.3-3.2.8-4.6l-7.9-6.2C.9 16.4 0 20.1 0 24s.9 7.6 2.6 10.8l7.9-6.2z"/><path fill="#34A853" d="M24 48c6.2 0 11.4-2 15.2-5.6l-7.7-6c-2.1 1.4-4.7 2.3-7.5 2.3-6.3 0-11.6-4.1-13.5-9.9l-7.9 6.2C6.5 42.6 14.6 48 24 48z"/></svg>
        Continue with Google
      </button>
      <div class="small" style="font-size:11px">Only the owner's Gmail can open Ruby Key.</div>
    </div>`;
  document.getElementById('loginBtn').onclick = doLogin;
}

function renderUnauthorized(email) {
  appEl.innerHTML = `
    <div class="center">
      <div class="boot-logo" style="background:#3a2026">!</div>
      <div class="big">Unauthorized Access</div>
      <div class="small">${esc(email)} is not the admin Gmail.<br/>For security you have been signed out.</div>
      <button class="btn" id="againBtn">Back to login</button>
    </div>`;
  document.getElementById('againBtn').onclick = () => renderLogin();
}

function renderDashboard() {
  appEl.innerHTML = `
    <header class="topbar">
      <div class="logo">R</div>
      <div class="titles">
        <div class="t1">RUBY KEY</div>
        <div class="t2"><span class="live-dot"></span>Live - real-time</div>
      </div>
      <div class="chip-admin" id="adminChip"></div>
      <button class="btn-ghost" id="outBtn">Logout</button>
    </header>
    <div class="wrap">
      <section class="rc-card">
        <div class="rc-head" id="rcHead">
          <div class="rc-title">REMOTE CONTROL <span class="rc-dot"></span></div>
          <div class="rc-sub">Change the app on EVERY phone without an update - applies within seconds (WhatsApp / Blinkit style).</div>
        </div>
        <div class="rc-body" id="rcBody">
          <label class="rc-label">Announcement banner (empty = hidden)</label>
          <textarea id="rcNotice" rows="2" placeholder="e.g. GST bill format is live!"></textarea>
          <label class="rc-label">Force-update gate - minimum version (empty = off)</label>
          <input id="rcMin" type="text" inputmode="decimal" placeholder="e.g. 0.2.18 - older phones MUST update" />
          <label class="rc-label">Support WhatsApp number (10 digits, empty = email button)</label>
          <input id="rcSupport" type="tel" inputmode="numeric" maxlength="10" placeholder="e.g. 9876543210" />
          <div class="rc-toggles">
            <label class="rc-toggle"><input type="checkbox" id="rcFtLedger" /><span class="box"></span>Ledger</label>
            <label class="rc-toggle"><input type="checkbox" id="rcFtInventory" /><span class="box"></span>Inventory</label>
            <label class="rc-toggle"><input type="checkbox" id="rcFtReports" /><span class="box"></span>Reports</label>
            <label class="rc-toggle"><input type="checkbox" id="rcFtBackup" /><span class="box"></span>Backup</label>
            <label class="rc-toggle"><input type="checkbox" id="rcAutoApprove" /><span class="box"></span>Auto-approve new shops</label>
          </div>
          <button class="btn primary rc-save" id="rcSave">Save &amp; Apply Now</button>
          <div class="rc-note" id="rcNote">Live - no APK needed.</div>
        </div>
      </section>
      <section class="rc-card">
        <div class="rc-head" id="luHead">
          <div class="rc-title">LIVE UI CONTROL <span class="rc-dot"></span></div>
          <div class="rc-sub">v0.4.0 - banners, feature switches, button colour and custom menu cards, straight to every phone. No APK, no update.</div>
        </div>
        <div class="rc-body hidden" id="luBody">
          <div class="rc-toggles">
            <label class="rc-toggle"><input type="checkbox" id="luBilty" /><span class="box"></span>Billty photo upload</label>
            <label class="rc-toggle"><input type="checkbox" id="luGst" /><span class="box"></span>GST fields (purchase)</label>
            <label class="rc-toggle"><input type="checkbox" id="luPdf" /><span class="box"></span>PDF share buttons</label>
            <label class="rc-toggle"><input type="checkbox" id="luRzp" /><span class="box"></span>Online payments offer banner</label>
            <label class="rc-toggle danger"><input type="checkbox" id="luMaint" /><span class="box"></span>MAINTENANCE MODE (locks every phone)</label>
          </div>
          <label class="rc-label">Offer banner text + colours (banner off = hidden)</label>
          <textarea id="luBannerText" rows="2" placeholder="e.g. Diwali special - free delivery this week!"></textarea>
          <div style="display:flex; gap:8px">
            <input id="luBannerBg" type="color" style="width:48px;height:36px;padding:2px" title="Banner background colour" />
            <input id="luBannerFg" type="color" style="width:48px;height:36px;padding:2px" title="Banner text colour" />
            <span class="small" style="align-self:center;font-size:11px">Banner background &amp; text colour</span>
          </div>
          <label class="rc-label">Primary button - colour + label (label empty = classic + icon)</label>
          <div style="display:flex; gap:8px">
            <input id="luPrimaryColor" type="color" style="width:48px;height:36px;padding:2px" title="Primary button colour" />
            <input id="luPrimaryLabel" type="text" style="flex:1" placeholder="e.g. NEW BILL (empty = + icon button)" />
          </div>
          <label class="rc-label">Custom menu cards - ONE per line: <b>Label | icon | colour | action</b></label>
          <textarea id="luShortcuts" rows="4" placeholder="Offers | gift | #e91e63 | url:https://example.com\nSupport call | call | #0A3D62 | dial:9876543210\nNew Bill | bill | #9B111E | open:billing"></textarea>
          <div class="small" style="font-size:10.5px;line-height:1.5;margin-top:4px">
            icons: bill, receipt, customer, ledger, inventory, purchase, return, account, report, backup, sync, settings, whatsapp, call, offer, star, gift, link, share, shop
            &nbsp;&bull;&nbsp; actions: open:billing, open:customers, open:ledger, open:inventory, open:purchases, open:returns, open:accounts, open:backup, open:sync, open:settings, open:pdfformat, url:https://..., dial:number, none
          </div>
          <button class="btn primary rc-save" id="luSave">Save &amp; Apply to All Phones</button>
          <div class="rc-note" id="luNote">Live UI - applies within seconds, no APK needed.</div>
        </div>
      </section>
      <section class="stats" id="stats"></section>
      <div class="search">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#647182" stroke-width="2"><circle cx="11" cy="11" r="7"/><path d="M21 21l-4-4"/></svg>
        <input id="search" type="search" placeholder="Search shop, owner, mobile, city, email..." autocomplete="off" />
      </div>
      <div id="userList"></div>
    </div>`;
  document.getElementById('adminChip').textContent = adminUser.email;
  document.getElementById('outBtn').onclick = async () => {
    if (unsubUsers) { unsubUsers(); unsubUsers = null; }
    if (unsubConfig) { unsubConfig(); unsubConfig = null; }
    if (unsubLiveUi) { unsubLiveUi(); unsubLiveUi = null; }
    await signOut(auth);
  };
  const s = document.getElementById('search');
  s.addEventListener('input', () => { searchTerm = s.value.trim().toLowerCase(); paintUsers(); });
  paintStats();
  paintUsers();
  bindRemoteControl();
  bindLiveUiControl();
}

// ---------------------------------------------- remote control (config/app)
function bindRemoteControl() {
  const head = document.getElementById('rcHead');
  const body = document.getElementById('rcBody');
  if (!head || !body) return;
  body.classList.add('hidden');
  head.addEventListener('click', () => body.classList.toggle('hidden'));
  document.getElementById('rcSave').addEventListener('click', saveRemoteConfig);
  ['rcNotice', 'rcMin', 'rcSupport', 'rcFtLedger', 'rcFtInventory',
   'rcFtReports', 'rcFtBackup', 'rcAutoApprove'].forEach((id) => {
    const el = document.getElementById(id);
    if (el) el.addEventListener('input', () => { cfgDirty = true; });
  });
}

function fillRemoteForm() {
  if (cfgDirty) return; // never overwrite unsaved admin edits
  const g = (id) => document.getElementById(id);
  if (!g('rcNotice')) return;
  g('rcNotice').value = remoteCfg.notice || '';
  g('rcMin').value = remoteCfg.min_version || '';
  g('rcSupport').value = remoteCfg.support_mobile || '';
  const f = remoteCfg.features || {};
  // switches default ON - a feature is only off when stored false
  g('rcFtLedger').checked = f.ledger !== false;
  g('rcFtInventory').checked = f.inventory !== false;
  g('rcFtReports').checked = f.reports !== false;
  g('rcFtBackup').checked = f.backup !== false;
  g('rcAutoApprove').checked = remoteCfg.auto_approve !== false;
  const note = g('rcNote');
  if (note) {
    note.textContent = Object.keys(remoteCfg).length
      ? 'Live - last saved values loaded. Every phone applies changes within seconds.'
      : 'Not configured yet - saving creates config/app automatically.';
  }
}

async function saveRemoteConfig() {
  const g = (id) => document.getElementById(id);
  const support = String(g('rcSupport').value || '').replace(/\D/g, '');
  if (support && support.length !== 10) {
    toast('Support number must be exactly 10 digits (or empty)', true);
    return;
  }
  const min = String(g('rcMin').value || '').trim();
  if (min && !/^\d+(\.\d+){0,2}$/.test(min)) {
    toast('Min version looks wrong - use like 0.2.18', true);
    return;
  }
  if (!confirm('Apply these settings to EVERY installed phone right now?')) return;
  try {
    await setDoc(doc(db, 'config', 'app'), {
      notice: String(g('rcNotice').value || '').trim(),
      min_version: min,
      support_mobile: support,
      features: {
        ledger: g('rcFtLedger').checked,
        inventory: g('rcFtInventory').checked,
        reports: g('rcFtReports').checked,
        backup: g('rcFtBackup').checked,
      },
      auto_approve: g('rcAutoApprove').checked,
      updatedAt: serverTimestamp(),
    }, { merge: true });
    cfgDirty = false;
    toast('Applied live - every phone picks it up in seconds');
  } catch (e) {
    toast('Failed: ' + (e.code || ''), true);
  }
}

function listenConfig() {
  if (unsubConfig) unsubConfig();
  unsubConfig = onSnapshot(doc(db, 'config', 'app'), (snap) => {
    remoteCfg = snap.data() || {};
    fillRemoteForm();
  }, () => {
    // read blocked / offline - the form still works, save may fail
  });
}

// --------------------------------------------- live UI control (v0.4.0)
// app_config/live_ui - banners, feature flags, primary button and
// admin-defined menu cards. Phones listen live; nothing to install.
const LIVE_UI_DEFAULT_SHORTCUTS = '';

function bindLiveUiControl() {
  const head = document.getElementById('luHead');
  const body = document.getElementById('luBody');
  if (!head || !body) return;
  head.addEventListener('click', () => body.classList.toggle('hidden'));
  document.getElementById('luSave').addEventListener('click', saveLiveUi);
  ['luBilty', 'luGst', 'luPdf', 'luRzp', 'luMaint',
   'luBannerText', 'luBannerBg', 'luBannerFg',
   'luPrimaryColor', 'luPrimaryLabel', 'luShortcuts'].forEach((id) => {
    const el = document.getElementById(id);
    if (el) el.addEventListener('input', () => { liveUiDirty = true; });
  });
}

function fillLiveUiForm() {
  if (liveUiDirty) return; // never overwrite unsaved admin edits
  const g = (id) => document.getElementById(id);
  if (!g('luBilty')) return;
  const f = liveUiCfg || {};
  // flags default ON (except maintenance + offer banner: default OFF)
  g('luBilty').checked = f.enable_bilty_upload !== false;
  g('luGst').checked = f.enable_gst_fields !== false;
  g('luPdf').checked = f.enable_pdf_share !== false;
  g('luRzp').checked = f.enable_razorpay_banner === true;
  g('luMaint').checked = f.maintenance_mode === true;
  const b = f.banner || {};
  g('luBannerText').value = b.text || '';
  g('luBannerBg').value = normHex(b.bg, '#9B111E');
  g('luBannerFg').value = normHex(b.fg, '#FFFFFF');
  g('luPrimaryColor').value = normHex(f.primary_color, '#9B111E');
  g('luPrimaryLabel').value = f.primary_label || '';
  const lines = (f.shortcuts || [])
    .map((s) => [s.label || '', s.icon || '', s.color || '', s.action || 'none'].join(' | '))
    .join('\n');
  g('luShortcuts').value = lines || LIVE_UI_DEFAULT_SHORTCUTS;
  const note = g('luNote');
  if (note) {
    note.textContent = Object.keys(f).length
      ? 'Live UI - last saved values loaded. Every phone applies changes within seconds.'
      : 'Not configured yet - saving creates app_config/live_ui automatically.';
  }
}

// "#a1b2c3" / "a1b2c3" -> "#A1B2C3"; anything else -> fallback.
function normHex(v, fallback) {
  let s = String(v || '').trim().replace(/^#/, '').toUpperCase();
  if (/^[0-9A-F]{6}$/.test(s)) return '#' + s;
  return fallback;
}

async function saveLiveUi() {
  const g = (id) => document.getElementById(id);
  const bannerText = String(g('luBannerText').value || '').trim();
  const maint = g('luMaint').checked;
  if (maint && !confirm(
    'MAINTENANCE MODE will show a maintenance screen on EVERY phone (except your admin Gmail).\n'
    + 'Customers cannot use the app until you turn this off. Continue?')) {
    return;
  }
  const shortcuts = [];
  const lines = String(g('luShortcuts').value || '').split('\n');
  for (const line of lines) {
    const t = line.trim();
    if (!t) continue;
    const [label, icon, color, action] = t.split('|').map((p) => p.trim());
    if (!label) continue;
    shortcuts.push({
      id: 'sc_' + Math.random().toString(36).slice(2, 9),
      label,
      icon: icon || 'link',
      color: normHex(color, ''),
      action: action || 'none',
      visible: true,
    });
  }
  if (!confirm('Apply this UI to EVERY installed phone right now?')) return;
  try {
    await setDoc(doc(db, 'app_config', 'live_ui'), {
      maintenance_mode: maint,
      enable_bilty_upload: g('luBilty').checked,
      enable_gst_fields: g('luGst').checked,
      enable_razorpay_banner: g('luRzp').checked,
      enable_pdf_share: g('luPdf').checked,
      banner: {
        enabled: bannerText.length > 0,
        text: bannerText,
        bg: normHex(g('luBannerBg').value, '#9B111E'),
        fg: normHex(g('luBannerFg').value, '#FFFFFF'),
      },
      primary_color: normHex(g('luPrimaryColor').value, '#9B111E'),
      primary_label: String(g('luPrimaryLabel').value || '').trim(),
      shortcuts,
      updatedAt: serverTimestamp(),
    }, { merge: true });
    liveUiDirty = false;
    toast('Live UI applied - every phone updates in seconds');
  } catch (e) {
    toast('Failed: ' + (e.code || ''), true);
  }
}

function listenLiveUi() {
  if (unsubLiveUi) unsubLiveUi();
  unsubLiveUi = onSnapshot(doc(db, 'app_config', 'live_ui'), (snap) => {
    liveUiCfg = snap.data() || {};
    fillLiveUiForm();
  }, () => {
    // read blocked / offline - the form still works, save may fail
  });
}

function paintStats() {
  const el = document.getElementById('stats');
  if (!el) return;
  let free = 0, paid = 0, expired = 0, blocked = 0;
  for (const u of users) {
    const [tag] = userTag(u);
    if (tag === 'paid') paid++;
    else if (tag === 'expired') expired++;
    else if (tag === 'blocked') blocked++;
    else free++;
  }
  el.innerHTML = `
    <div class="stat"><div class="n">${users.length}</div><div class="l">Total Users</div></div>
    <div class="stat amber"><div class="n">${free}</div><div class="l">Active (free)</div></div>
    <div class="stat green"><div class="n">${paid}</div><div class="l">Paid Subs</div></div>
    <div class="stat"><div class="n" style="color:#ff8a8f">${expired}</div><div class="l">Expired</div></div>
    <div class="stat"><div class="n" style="color:#ff8a8f">${blocked}</div><div class="l">Blocked</div></div>`;
}

function matches(u) {
  if (!searchTerm) return true;
  const hay = [u.businessName, u.ownerName, u.mobile, u.phone, u.city, u.email]
    .join(' ').toLowerCase();
  return hay.includes(searchTerm);
}

function paintUsers() {
  const list = document.getElementById('userList');
  if (!list) return;
  const rows = users.filter(matches);
  if (!rows.length) {
    list.innerHTML = `<div class="empty">${searchTerm ? 'No shop matches the search.' : 'No users yet - new registrations appear here live.'}</div>`;
    return;
  }
  list.innerHTML = rows.map(userCard).join('');
  rows.forEach((u) => bindCard(u));
}

function userCard(u) {
  const [tag, tagLabel] = userTag(u);
  const id = u._id;
  const open = openIds.has(id);
  const wa = waLink(u.mobile || u.phone);
  const tel = telLink(u.mobile || u.phone);
  const dl = daysLeft(u);
  return `
  <div class="user ${open ? 'open' : ''}" id="uc-${cssId(id)}">
    <div class="head" data-act="toggle" data-id="${esc(id)}">
      <div class="u-row1">
        <div class="u-name">${esc(u.businessName || '(no shop name)')}</div>
        <div class="tag ${tag}">${tagLabel}</div>
      </div>
      <div class="u-sub"><b>${esc(u.ownerName || '-')}</b> &nbsp;|&nbsp; ${esc(u.city || '-')} &nbsp;|&nbsp; ${esc(u.mobile || u.phone || '-')}</div>
      <div class="pill-row">
        <div class="pill">${esc(u.email || '')}</div>
        <div class="pill ${dl !== null && dl < 0 ? 'warn' : 'ok'}">Valid till ${fmtDate(effectiveEnd(u))}</div>
        <div class="pill">Devices ${deviceCount(u)}</div>
        <div class="pill">Plan ${esc(u.plan || 'legacy')}</div>
      </div>
    </div>
    <div class="details">
      <div class="kv"><div class="k">Address</div><div class="v">${esc(u.address || '-')}</div></div>
      <div class="kv"><div class="k">GST</div><div class="v">${esc(u.gst || '-')}</div></div>
      <div class="kv"><div class="k">Subscription end</div><div class="v">${fmtDate(toDate(u.subscriptionEndDate))}</div></div>
      <div class="kv"><div class="k">Registered</div><div class="v">${fmtDate(toDate(u.createdAt))}</div></div>
      <div class="dev-list" id="dev-${cssId(id)}">
        ${(u.registeredDevices || []).map((d, i) => `
          <div class="dev">
            <span>📱</span>
            <span class="mdi">Device ${i + 1} - ${esc((u.deviceModels && u.deviceModels[d]) || 'Phone')} (${esc(String(d).slice(-6))})</span>
            <button class="btn red" data-act="rmdev" data-id="${esc(id)}" data-dev="${esc(d)}">Remove</button>
          </div>`).join('') || '<div class="dev"><span class="mdi">No devices registered</span></div>'}
      </div>
      <div class="extend-row">
        <button class="btn primary" data-act="ext" data-id="${esc(id)}" data-days="30">+30 days</button>
        <button class="btn primary" data-act="ext" data-id="${esc(id)}" data-days="365">+1 year</button>
        <input type="date" id="dt-${cssId(id)}" />
        <button class="btn" data-act="extd" data-id="${esc(id)}">Extend to date</button>
      </div>
    </div>
    <div class="actions">
      ${u.status === 'blocked'
        ? `<button class="btn green" data-act="unblock" data-id="${esc(id)}">Unblock</button>`
        : `<button class="btn red" data-act="block" data-id="${esc(id)}">Block</button>`}
      <button class="btn" data-act="resetdev" data-id="${esc(id)}">Reset Devices</button>
      <button class="btn" data-act="viewdata" data-id="${esc(id)}">Data</button>
      ${wa ? `<a class="btn wa" href="${wa}" target="_blank" rel="noopener">WhatsApp</a>` : ''}
      ${tel ? `<a class="btn tel" href="${tel}">Call</a>` : ''}
    </div>
  </div>`;
}

function bindCard(u) {
  const card = document.getElementById(`uc-${cssId(u._id)}`);
  if (!card) return;
  card.querySelectorAll('[data-act]').forEach((btn) => {
    btn.addEventListener('click', (e) => {
      e.preventDefault();
      const act = btn.dataset.act;
      const id = btn.dataset.id;
      const u2 = users.find((x) => x._id === id);
      if (!u2) return;
      if (act === 'toggle') {
        if (openIds.has(id)) openIds.delete(id); else openIds.add(id);
        paintUsers();
      } else if (act === 'block') { blockUser(u2); }
      else if (act === 'unblock') { unblockUser(u2); }
      else if (act === 'resetdev') { resetDevices(u2); }
      else if (act === 'rmdev') { removeDevice(u2, btn.dataset.dev); }
      else if (act === 'viewdata') { openUserData(u2); }
      else if (act === 'ext') { extendUser(u2, Number(btn.dataset.days)); }
      else if (act === 'extd') {
        const v = document.getElementById(`dt-${cssId(id)}`).value;
        if (!v) { toast('Pick a date first', true); return; }
        extendUser(u2, null, new Date(v + 'T23:59:59'));
      }
    });
  });
}

const cssId = (id) => id.replace(/[^a-zA-Z0-9_-]/g, '_');

// ------------------------------------------------------------- actions
async function blockUser(u) {
  if (!confirm(`Block "${u.businessName}"?\nThe app locks on their phone within seconds.`)) return;
  try {
    await updateDoc(doc(db, 'users', u._id), { status: 'blocked', updatedAt: serverTimestamp() });
    toast(`${u.businessName} blocked`);
  } catch (e) { toast('Failed: ' + e.code, true); }
}

async function unblockUser(u) {
  if (!confirm(`Unblock "${u.businessName}"?`)) return;
  try {
    await updateDoc(doc(db, 'users', u._id), { status: 'active', updatedAt: serverTimestamp() });
    toast(`${u.businessName} unblocked`);
  } catch (e) { toast('Failed: ' + e.code, true); }
}

async function resetDevices(u) {
  const n = (u.registeredDevices || []).length;
  if (!n) { toast('This account has no registered devices'); return; }
  if (!confirm(`Reset devices for "${u.businessName}"?\nAll ${n} registered device(s) are removed; they can sign in again on new phones.`)) return;
  try {
    await updateDoc(doc(db, 'users', u._id), { registeredDevices: [], deviceModels: {}, updatedAt: serverTimestamp() });
    toast('Devices reset');
  } catch (e) { toast('Failed: ' + e.code, true); }
}

async function removeDevice(u, devId) {
  if (!confirm('Remove this one device from the account?')) return;
  const rest = (u.registeredDevices || []).filter((d) => d !== devId);
  const models = { ...(u.deviceModels || {}) };
  delete models[devId];
  try {
    await updateDoc(doc(db, 'users', u._id), { registeredDevices: rest, deviceModels: models, updatedAt: serverTimestamp() });
    toast('Device removed');
  } catch (e) { toast('Failed: ' + e.code, true); }
}

async function extendUser(u, days, customDate = null) {
  const base = (() => {
    const cur = effectiveEnd(u);
    if (customDate) return customDate;
    const from = cur && cur.getTime() > Date.now() ? cur : new Date();
    return new Date(from.getTime() + days * 86400000);
  })();
  const label = customDate
    ? `Extend "${u.businessName}" until ${fmtDate(base)}?`
    : `Add ${days} day(s) to "${u.businessName}"?\nNew validity: ${fmtDate(base)}`;
  if (!confirm(label)) return;
  const ts = Timestamp.fromDate(base);
  try {
    await updateDoc(doc(db, 'users', u._id), {
      status: 'active',
      plan: 'paid',
      subscriptionEndDate: ts,
      updatedAt: serverTimestamp(),
    });
    // subscriptions ledger row - Razorpay-ready schema
    await addDoc(collection(db, 'subscriptions'), {
      userId: u._id,
      shopName: u.businessName || '',
      planId: 'manual',
      amount: 0,
      currency: 'INR',
      razorpayOrderId: '',
      razorpayPaymentId: '',
      status: 'active',
      validUntil: ts,
      note: days ? `manual +${days}d (Ruby Key)` : 'manual date (Ruby Key)',
      createdAt: serverTimestamp(),
    });
    toast(`Extended till ${fmtDate(base)}`);
  } catch (e) { toast('Failed: ' + e.code, true); }
}

// ------------------------------------------------- user data (support)
// Read-only browser of a user's own shop data (rules v4 allow the admin
// to READ shops/{uid}; no write path exists). Used for support: "kya
// problem aa rahi hai" can be answered from the real records.
const SHOP_COLLECTIONS = [
  ['bills', 'Bills'],
  ['payments', 'Payments (jama)'],
  ['customers', 'Customers'],
  ['products', 'Inventory'],
  ['purchases', 'Purchases'],
  ['suppliers', 'Purchase parties'],
  ['purchase_returns', 'Purchase returns'],
  ['sales_returns', 'Sales returns'],
];

let dataOverlay = null;

async function openUserData(u) {
  closeDataOverlay();
  dataOverlay = document.createElement('div');
  dataOverlay.className = 'data-overlay';
  dataOverlay.innerHTML = `
    <div class="data-panel">
      <div class="data-head">
        <div>
          <div class="data-title">${esc(u.businessName || 'User data')}</div>
          <div class="data-sub">${esc(u.email || '')} - read-only support view</div>
        </div>
        <button class="btn" id="dataClose">Close</button>
      </div>
      <div class="data-grid" id="dataGrid"><div class="empty">Loading...</div></div>
      <div class="data-list" id="dataList"></div>
    </div>`;
  document.body.appendChild(dataOverlay);
  document.getElementById('dataClose').onclick = closeDataOverlay;

  const grid = document.getElementById('dataGrid');
  const list = document.getElementById('dataList');
  const counts = [];
  for (const [name, label] of SHOP_COLLECTIONS) {
    let n = null;
    try {
      const snap = await getDocs(query(collection(db, 'shops', u._id, name), limit(300)));
      n = snap.size;
    } catch (e) { n = -1; }
    counts.push({ name, label, n });
    if (grid.querySelector('.empty')) grid.innerHTML = '';
    grid.insertAdjacentHTML('beforeend', `
      <button class="data-cell ${n > 0 ? 'has' : ''}" data-coll="${name}">
        <div class="n">${n < 0 ? '!' : n}</div>
        <div class="l">${esc(label)}</div>
      </button>`);
  }
  grid.querySelectorAll('[data-coll]').forEach((cell) => {
    cell.addEventListener('click', () => showCollection(u, cell.dataset.coll, cell.querySelector('.l').textContent));
  });

  async function showCollection(u2, coll, label) {
    list.innerHTML = `<div class="empty">Loading ${esc(label)}...</div>`;
    try {
      const snap = await getDocs(query(
        collection(db, 'shops', u2._id, coll),
        orderBy('updated_at', 'desc'), limit(10)));
      if (!snap.size) { list.innerHTML = `<div class="empty">Empty.</div>`; return; }
      list.innerHTML = `<div class="data-list-head">${esc(label)} - latest ${snap.size}</div>` +
        snap.docs.map((d) => {
          const v = d.data();
          return `<div class="data-row"><pre>${esc(summarize(coll, v))}</pre></div>`;
        }).join('');
    } catch (e) {
      list.innerHTML = `<div class="empty">Read failed: ${esc(e.code || '')}</div>`;
    }
  }
}

function summarize(coll, v) {
  const money = (p) => '₹' + (Number(p || 0) / 100).toLocaleString('en-IN', { minimumFractionDigits: 2 });
  const dt = (ms) => { const d = toDate(ms); return d ? fmtDate(d) : '-'; };
  switch (coll) {
    case 'bills':
      return `Bill #${v.bill_no} - ${v.customer_name || ''}
${dt(v.bill_date)}  ${money(v.total_paise)}`
        + (Array.isArray(v.items) ? `
${v.items.length} items: `
          + v.items.slice(0, 5).map((i) => i.product_name).join(', ') + (v.items.length > 5 ? '...' : '') : '');
    case 'payments':
      return `Payment - ${money(v.amount_paise)}
${dt(v.pay_date)}  ${v.mode || 'cash'} ${v.note ? '- ' + v.note : ''}`;
    case 'customers':
      return `${v.name || ''} (${v.city || '-'})
${v.phone || ''}  opening ${money(v.opening_balance_paise)}`;
    case 'products':
      return `${v.name || ''}
rate ${money(v.default_price_paise)}  stock ${v.stock_qty ?? '-'} ${v.unit || ''}`;
    case 'purchases':
      return `Purchase #${v.purchase_no} - ${v.supplier_name || ''}
${dt(v.purchase_date)}  ${money(v.amount_paise)}`
        + (v.party_bill_no ? `  (party bill ${v.party_bill_no})` : '')
        + (Array.isArray(v.items) ? `
${v.items.length} items: `
          + v.items.slice(0, 5).map((i) => i.product_name).join(', ') + (v.items.length > 5 ? '...' : '') : '');
    case 'suppliers':
      return `${v.name || ''} (${v.city || '-'})
${v.phone || ''}  opening ${money(v.opening_balance_paise)}`;
    case 'purchase_returns':
      return `Return #${v.return_no} - ${v.supplier_name || ''}
${dt(v.return_date)}  ${money((v.amount_paise || 0) + (v.gst_total_paise || 0))}`;
    case 'sales_returns':
      return `Sales return #${v.return_no} - ${v.customer_name || ''}
${dt(v.return_date)}  ${money(v.amount_paise)}`;
    default:
      return JSON.stringify(v, null, 1).slice(0, 400);
  }
}

function closeDataOverlay() {
  if (dataOverlay) { dataOverlay.remove(); dataOverlay = null; }
}

// ---------------------------------------------------------------- login
async function doLogin() {
  try {
    const provider = new GoogleAuthProvider();
    await signInWithPopup(auth, provider);
  } catch (e) {
    toast('Google sign-in failed: ' + (e.code || ''), true);
  }
}

// ------------------------------------------------------------- wiring
onAuthStateChanged(auth, (user) => {
  if (!user) {
    adminUser = null; adminOk = false;
    if (unsubUsers) { unsubUsers(); unsubUsers = null; }
    if (unsubConfig) { unsubConfig(); unsubConfig = null; }
    if (unsubLiveUi) { unsubLiveUi(); unsubLiveUi = null; }
    renderLogin();
    return;
  }
  const email = String(user.email || '').toLowerCase();
  if (email !== ADMIN_EMAIL) {
    // Not the owner's Gmail - sign out immediately (spec).
    signOut(auth);
    renderUnauthorized(user.email);
    return;
  }
  adminUser = user; adminOk = true;
  renderDashboard();
  listenUsers();
  listenConfig();
  listenLiveUi();
});

function listenUsers() {
  if (unsubUsers) unsubUsers();
  unsubUsers = onSnapshot(collection(db, 'users'), (snap) => {
    users = snap.docs.map((d) => ({ _id: d.id, ...d.data() }));
    users.sort((a, b) => {
      const ta = toDate(a.createdAt)?.getTime() || 0;
      const tb = toDate(b.createdAt)?.getTime() || 0;
      return tb - ta;
    });
    paintStats();
    paintUsers();
  }, (err) => {
    toast('Live read blocked by rules: ' + err.code, true);
  });
}

// ---------------------------------------------------------------- PWA
// Service worker registration moved here from index.html so the strict
// CSP can forbid inline scripts entirely (no behaviour change).
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('./sw.js').catch(() => {});
  });
}

// ---------------------------------------------------------------- notes
// TRUST MODEL (security audit v0.2.21):
//   * This panel keeps NO security state in localStorage/sessionStorage.
//     The session is Firebase Auth's own IndexedDB persistence, and the
//     admin identity + every write is re-verified SERVER-SIDE by the
//     Firestore security rules on every request. A tampered local
//     storage cannot promote a non-admin to admin.
//   * Subscription validity shown here is read live from Firestore -
//     never from a cached local flag; the phones re-verify the same
//     fields against Firestore on every launch and every sync tick.
//   * Only the public Firebase web config lives in firebase-config.js
//     (safe by design: it identifies, not authorizes, the project).
