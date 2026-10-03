const API = "http://localhost:8000";

/* ─────────────────────────────────────────────
   Core fetch helpers
───────────────────────────────────────────── */
async function apiFetch(path, opts = {}) {
  const token = localStorage.getItem('token');
  const headers = { 'Content-Type': 'application/json', ...(opts.headers || {}) };
  if (token) headers['X-Token'] = token;
  let res;
  try { res = await fetch(API + path, { ...opts, headers }); }
  catch { throw new Error('Cannot reach server. Is the API running on port 8000?'); }
  let data;
  try { data = await res.json(); } catch { data = {}; }
  if (!res.ok) throw new Error(data.error || `Server error ${res.status}`);
  return data;
}

async function hotelFetch(path, opts = {}) {
  const key = localStorage.getItem('staff_key') || '';
  const headers = { 'Content-Type': 'application/json', 'X-Staff-Key': key, ...(opts.headers || {}) };
  let res;
  try { res = await fetch(API + path, { ...opts, headers }); }
  catch { throw new Error('Cannot reach server. Is the API running on port 8000?'); }
  let data;
  try { data = await res.json(); } catch { data = {}; }
  if (!res.ok) throw new Error(data.error || `Server error ${res.status}`);
  return data;
}

/* ─────────────────────────────────────────────
   Auth / role helpers
───────────────────────────────────────────── */
function getRole()  { return localStorage.getItem('role') || 'user'; }    // 'user' | 'hotel'
function getUser()  {
  return {
    token:      localStorage.getItem('token'),
    user_id:    localStorage.getItem('user_id'),
    name:       localStorage.getItem('name'),
    role:       getRole(),
    staff_key:  localStorage.getItem('staff_key'),
    hotel_name: localStorage.getItem('hotel_name'),
    hotel_id:   localStorage.getItem('hotel_id'),
  };
}

function requireLogin() {
  if (!localStorage.getItem('token') && !localStorage.getItem('staff_key')) {
    window.location.href = 'index.html';
  }
}
function requireUser() {
  if (getRole() !== 'user' || !localStorage.getItem('token')) {
    window.location.href = 'index.html';
  }
}
function requireHotel() {
  if (getRole() !== 'hotel' || !localStorage.getItem('staff_key')) {
    window.location.href = 'index.html';
  }
}

function logout() {
  ['token','user_id','name','role','staff_key','hotel_name','hotel_id'].forEach(k => localStorage.removeItem(k));
  window.location.href = 'index.html';
}

/* ─────────────────────────────────────────────
   UI helpers
───────────────────────────────────────────── */
function escHtml(str) {
  if (str == null) return '';
  return String(str)
    .replace(/&/g,'&amp;').replace(/</g,'&lt;')
    .replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}
function showAlert(el, msg, type = 'error') {
  if (!el) return;
  el.textContent = msg;
  el.className = 'alert show alert-' + type;
}
function clearAlert(el) {
  if (!el) return;
  el.textContent = '';
  el.className = 'alert';
}
function badge(status) {
  return `<span class="badge badge-${escHtml(status)}">${escHtml(status)}</span>`;
}

/* ─────────────────────────────────────────────
   Role-aware nav injection
   Call buildNav() at top of each page body
───────────────────────────────────────────── */
function buildNav() {
  const role = getRole();
  const nav  = document.querySelector('.nav');
  if (!nav) return;

  const page = location.pathname.split('/').pop() || 'index.html';

  let links = '';
  if (role === 'hotel') {
    links = `
      <a href="hotel.html">Dashboard</a>
      <a href="stats.html">Stats</a>`;
  } else {
    links = `
      <a href="restaurants.html">Restaurants</a>
      <a href="mybookings.html">My Bookings</a>
      <a href="feedback.html">Feedback</a>
      <a href="stats.html">Stats</a>`;
  }

  const user = getUser();
  const label = role === 'hotel'
    ? (user.hotel_name || 'Hotel')
    : (user.name || 'Account');

  nav.innerHTML = `
    <a class="nav-brand" href="index.html">🍽 Dine-In</a>
    ${links}
    <span style="margin-left:auto; display:flex; align-items:center; gap:0.75rem;">
      <span style="font-size:0.8rem; color:var(--text-muted);">👤 ${escHtml(label)}</span>
      <button onclick="logout()" class="btn btn-secondary btn-sm" style="padding:0.25rem 0.65rem;">Sign out</button>
    </span>`;

  nav.querySelectorAll('a[href]').forEach(a => {
    if (a.getAttribute('href') === page) a.classList.add('active');
  });
}
