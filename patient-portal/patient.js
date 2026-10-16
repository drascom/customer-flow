const API = "/api/v1";
const $ = (id) => document.getElementById(id);
const state = { token: localStorage.getItem("cfPatientToken") || sessionStorage.getItem("cfPatientToken") || "", user: null, cases: [], objectURLs: [] };

function escapeHTML(value) { const node = document.createElement("span"); node.textContent = value ?? ""; return node.innerHTML; }
function formatDate(value) { return value ? new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" }).format(new Date(value)) : ""; }
function setBusy(form, busy) { const button = form.querySelector("button[type=submit]"); if (button) button.disabled = busy; }
async function request(path, options = {}) {
  const headers = { Accept: "application/json", ...(options.headers || {}) };
  if (state.token) headers.Authorization = `Bearer ${state.token}`;
  const init = { ...options, headers };
  if (init.body && typeof init.body !== "string" && !(init.body instanceof Blob)) { headers["Content-Type"] = "application/json"; init.body = JSON.stringify(init.body); }
  const response = await fetch(`${API}${path}`, init);
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(payload.error?.message || "The request could not be completed.");
  return payload;
}
function saveToken(token, remember) {
  localStorage.removeItem("cfPatientToken"); sessionStorage.removeItem("cfPatientToken");
  (remember ? localStorage : sessionStorage).setItem("cfPatientToken", token); state.token = token;
}
function clearSession() { state.token = ""; state.user = null; localStorage.removeItem("cfPatientToken"); sessionStorage.removeItem("cfPatientToken"); }
function showAuth() { $("authView").hidden = false; $("portalView").hidden = true; $("signOutButton").hidden = true; }
function showPortal() { $("authView").hidden = true; $("portalView").hidden = false; $("signOutButton").hidden = false; $("welcomeName").textContent = `Hello, ${state.user.displayName}`; }
function selectAuth(mode) { const login = mode === "login"; $("loginForm").hidden = !login; $("accessView").hidden = login; $("showLogin").classList.toggle("active", login); $("showAccess").classList.toggle("active", !login); }

async function photoURL(id) {
  const response = await fetch(`${API}/patient/photos/${encodeURIComponent(id)}/thumbnail`, { headers: { Authorization: `Bearer ${state.token}` } });
  if (!response.ok) return "";
  const url = URL.createObjectURL(await response.blob()); state.objectURLs.push(url); return url;
}
async function renderCases() {
  state.objectURLs.forEach((url) => URL.revokeObjectURL(url)); state.objectURLs = [];
  const list = $("caseList"); list.innerHTML = ""; $("emptyCases").hidden = state.cases.length > 0;
  for (const item of state.cases) {
    const card = document.createElement("article"); card.className = "case-card"; card.dataset.caseId = item.id;
    card.innerHTML = `<div class="case-heading"><div><p class="eyebrow">${escapeHTML(item.reference)}</p><h2>${escapeHTML(item.agencyName || "Hair consultation")}</h2><p class="case-meta">${escapeHTML(item.doctorName ? `Doctor: ${item.doctorName} · ` : "")}Submitted ${escapeHTML(formatDate(item.uploadedAt))}</p></div><span class="status-pill">${escapeHTML(item.status)}</span></div><div class="photo-grid" aria-label="Consultation photos"></div><div class="updates">${item.updates.length ? item.updates.map((update) => `<div class="update"><p>${escapeHTML(update.text)}</p><time>${escapeHTML(formatDate(update.createdAt))}</time></div>`).join("") : "<p class=\"case-meta\">You have not added any follow-up information.</p>"}</div><form class="case-actions"><label>Additional information<textarea name="text" maxlength="4000" placeholder="Tell the clinic about changes or requests" required></textarea></label><button class="primary" type="submit">Send update</button></form><div class="upload-row"><input type="file" accept="image/jpeg,image/png,image/heic" multiple><button class="quiet upload-button" type="button">Upload photos</button></div><p class="error" role="alert"></p>`;
    list.appendChild(card);
    const grid = card.querySelector(".photo-grid");
    for (const photoID of item.photoIDs) { const url = await photoURL(photoID); if (url) { const image = new Image(); image.src = url; image.alt = "Patient consultation photo"; grid.appendChild(image); } }
  }
}
async function loadCases() { const result = await request("/patient/cases"); state.cases = result.cases; await renderCases(); }
async function enterPortal() { const result = await request("/patient/auth/me"); state.user = result.user; showPortal(); await loadCases(); }

$("showLogin").onclick = () => selectAuth("login");
$("showAccess").onclick = () => selectAuth("access");
$("loginForm").onsubmit = async (event) => { event.preventDefault(); setBusy(event.currentTarget, true); $("loginError").textContent = ""; try { const result = await request("/patient/auth/login", { method: "POST", body: { email: $("loginEmail").value.trim(), password: $("loginPassword").value } }); saveToken(result.token, $("rememberSession").checked); state.user = result.user; showPortal(); await loadCases(); } catch (error) { $("loginError").textContent = error.message; } finally { setBusy(event.currentTarget, false); } };
$("requestAccessForm").onsubmit = async (event) => { event.preventDefault(); setBusy(event.currentTarget, true); $("accessMessage").textContent = ""; try { const result = await request("/patient/auth/access/request", { method: "POST", body: { email: $("accessEmail").value.trim() } }); $("accessMessage").textContent = result.message; $("confirmAccessForm").hidden = false; } catch (error) { $("accessMessage").textContent = error.message; } finally { setBusy(event.currentTarget, false); } };
$("confirmAccessForm").onsubmit = async (event) => { event.preventDefault(); setBusy(event.currentTarget, true); $("confirmError").textContent = ""; try { const email = $("accessEmail").value.trim(); const password = $("accessPassword").value; await request("/patient/auth/access/confirm", { method: "POST", body: { email, code: $("accessCode").value.trim(), password } }); const result = await request("/patient/auth/login", { method: "POST", body: { email, password } }); saveToken(result.token, true); state.user = result.user; showPortal(); await loadCases(); } catch (error) { $("confirmError").textContent = error.message; } finally { setBusy(event.currentTarget, false); } };
$("caseList").onsubmit = async (event) => { const form = event.target.closest(".case-actions"); if (!form) return; event.preventDefault(); const card = form.closest(".case-card"); const errorNode = card.querySelector(".error"); setBusy(form, true); errorNode.textContent = ""; try { const result = await request(`/patient/cases/${card.dataset.caseId}/updates`, { method: "POST", body: { text: new FormData(form).get("text") } }); state.cases = state.cases.map((item) => item.id === result.case.id ? result.case : item); await renderCases(); } catch (error) { errorNode.textContent = error.message; } finally { setBusy(form, false); } };
$("caseList").onclick = async (event) => { const button = event.target.closest(".upload-button"); if (!button) return; const card = button.closest(".case-card"); const input = card.querySelector("input[type=file]"); const errorNode = card.querySelector(".error"); const files = [...input.files]; if (!files.length) { errorNode.textContent = "Choose at least one photo."; return; } button.disabled = true; errorNode.textContent = ""; try { let updated; for (const file of files) { updated = await request(`/patient/cases/${card.dataset.caseId}/photos`, { method: "POST", headers: { "Content-Type": file.type }, body: file }); } state.cases = state.cases.map((item) => item.id === updated.case.id ? updated.case : item); await renderCases(); } catch (error) { errorNode.textContent = error.message; } finally { button.disabled = false; } };
$("refreshButton").onclick = async () => { $("refreshButton").disabled = true; $("portalError").textContent = ""; try { await loadCases(); } catch (error) { $("portalError").textContent = error.message; } finally { $("refreshButton").disabled = false; } };
$("signOutButton").onclick = async () => { try { await request("/patient/auth/logout", { method: "POST", body: {} }); } catch (_) {} clearSession(); showAuth(); };

(async () => { if (!state.token) return showAuth(); try { await enterPortal(); } catch (_) { clearSession(); showAuth(); } })();
