// Session and API access. The token lives in sessionStorage (cleared when the tab closes).

export const API = '/api/v1';

export class ApiError extends Error {
  constructor(message, status) {
    super(message);
    this.status = status;
  }
}

export const session = {
  get access() { return sessionStorage.getItem('admin_access'); },
  get refresh() { return sessionStorage.getItem('admin_refresh'); },
  get who() { return sessionStorage.getItem('admin_who'); },
  set(tokens, who) {
    sessionStorage.setItem('admin_access', tokens.access_token);
    sessionStorage.setItem('admin_refresh', tokens.refresh_token);
    if (who) sessionStorage.setItem('admin_who', who);
  },
  clear() { sessionStorage.clear(); },
};

export function detailOf(body, status) {
  const d = body && body.detail;
  if (typeof d === 'string') return d;
  if (Array.isArray(d) && d[0] && d[0].msg) return String(d[0].msg).replace('Value error, ', '');
  return `Something went wrong (error ${status}).`;
}

let onSessionEnd = () => {};
/** The app tells us what to do when the session is over (show the login form). */
export const setSessionEndHandler = (fn) => { onSessionEnd = fn; };

let refreshing = null;
function refreshTokens() {
  if (!session.refresh) return Promise.resolve(false);
  // One refresh at a time, so several requests failing together do not each spend the refresh token.
  refreshing ??= (async () => {
    try {
      const r = await fetch(`${API}/auth/refresh`, {
        method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ refresh_token: session.refresh }),
      });
      if (!r.ok) return false;
      session.set(await r.json());
      return true;
    } catch { return false; } finally { refreshing = null; }
  })();
  return refreshing;
}

export async function api(path, { method = 'GET', body, blob = false } = {}) {
  const send = () => fetch(API + path, {
    method,
    headers: { ...(session.access ? { authorization: `Bearer ${session.access}` } : {}), ...(body ? { 'content-type': 'application/json' } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  let r;
  try { r = await send(); } catch { throw new ApiError('Cannot reach the server. Check the connection and try again.', 0); }
  if (r.status === 401 && (await refreshTokens())) r = await send();
  if (r.status === 401) {
    session.clear();
    onSessionEnd('Your session ended. Log in again.');
    throw new ApiError('Session expired', 401);
  }
  if (!r.ok) throw new ApiError(detailOf(await r.json().catch(() => null), r.status), r.status);
  if (r.status === 204) return null;
  return blob ? r.blob() : r.json();
}

export async function login(identifier, password) {
  let r;
  try {
    r = await fetch(`${API}/auth/admin/login`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ identifier, password }) });
  } catch { throw new ApiError('Cannot reach the server. Check the connection and try again.', 0); }
  if (!r.ok) throw new ApiError(r.status === 401 ? 'Invalid email, mobile number or password' : detailOf(await r.json().catch(() => null), r.status), r.status);
  session.set(await r.json(), identifier);
}
