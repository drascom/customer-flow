const API = "/api/v1";
const state = {
  token: localStorage.getItem("cfToken") || sessionStorage.getItem("cfToken"),
  user: null, users: [], agencies: [], cases: [], notifications: [], unreadNotifications: 0,
  clientVersionPolicy: null,
  view: "cases", selectedCaseID: null,
  pendingFiles: [], duplicate: { matches: [], confirmed: false, existingPatientID: null }, blobURLs: new Map(),
  photoItems: [], photoIndex: 0, liveRevision: -1, liveGeneration: 0,
  filters: { caseStatus: "", caseAssignment: "", caseAgency: "", caseDoctor: "", userRole: "", userStatus: "", userAgency: "" }
};

const $ = (id) => document.getElementById(id);
const escapeHTML = (value) => String(value ?? "").replace(/[&<>'"]/g, (c) => ({"&":"&amp;","<":"&lt;",">":"&gt;","'":"&#39;",'"':"&quot;"}[c]));
const isManagement = () => ["admin", "manager"].includes(state.user?.role);
const canMutateAdmin = () => state.user?.role === "admin";
const patientName = (item) => item.patient?.name || item.patientName || "Patient";
const patientID = (item) => item.patient?.id || item.patientID;
const doctorID = (item) => item.patient?.assignedDoctorID || item.assignedDoctorID || item.doctorID;
const caseNote = (item) => item.agentNote || item.note || "";
const caseGrafts = (item) => item.finalGrafts || item.agentGrafts || item.grafts || "—";
const casePrice = (item) => item.finalPrice || item.agentPrice || item.price || "—";
const photoIDs = (item) => item.photoIDs || (item.photos || []).filter((p) => !p.deleted && p.available !== false).map((p) => p.id);
const latestMessage = (item) => item.latestMessage || [...(item.messages || [])].reverse().find((m) => !m.deletedAt && m.role !== "system");
const validPermanentPassword = (value) => value.length >= 6 && /\d/.test(value) && /[^\p{L}\p{N}\s]/u.test(value);
const unreadCaseNotifications = (caseID) => state.notifications.filter((item) =>
  !item.readAt && item.caseID && String(item.caseID).toLowerCase() === String(caseID).toLowerCase());

function caseNotificationBadgeHTML(caseID) {
  const count = unreadCaseNotifications(caseID).length;
  return count ? `<span class="case-notification-badge" aria-label="${count} unread notification${count === 1 ? "" : "s"}">🔔 ${count}</span>` : "";
}

async function api(path, options = {}) {
  const headers = { Accept: "application/json", ...(options.headers || {}) };
  if (state.token) headers.Authorization = `Bearer ${state.token}`;
  const request = { ...options, headers };
  if (request.body && !(request.body instanceof Blob) && typeof request.body !== "string") {
    headers["Content-Type"] = "application/json";
    request.body = JSON.stringify(request.body);
  }
  const response = await fetch(`${API}${path}`, request);
  if (options.raw) {
    if (!response.ok) throw await responseError(response);
    return response;
  }
  const payload = await response.json().catch(() => ({}));
  if (response.status === 401 && !path.startsWith("/auth/login")) {
    signOut(false);
    throw new Error("Your session expired. Sign in again.");
  }
  if (!response.ok) throw new Error(payload.error?.message || `Request failed (${response.status}).`);
  return payload;
}

async function loadDeploymentInfo() {
  try {
    const health = await api("/health");
    document.querySelectorAll("[data-deploy-commit]").forEach((node) => {
      node.textContent = health.commit || "unknown";
    });
  } catch {
    document.querySelectorAll("[data-deploy-commit]").forEach((node) => {
      node.textContent = "unavailable";
    });
  }
}

async function responseError(response) {
  const payload = await response.json().catch(() => ({}));
  return new Error(payload.error?.message || `Request failed (${response.status}).`);
}

function showLogin(message = "") {
  $("loginView").hidden = false; $("appView").hidden = true; $("loginError").textContent = message;
}

function applyRoleVisibility() {
  document.querySelectorAll(".management-only").forEach((node) => { node.hidden = !isManagement(); });
  document.querySelectorAll(".admin-only").forEach((node) => { node.hidden = !canMutateAdmin(); });
  document.querySelectorAll(".agent-only").forEach((node) => { node.hidden = state.user.role !== "agent"; });
  $("caseCards").hidden = isManagement();
  $("managementCaseTable").hidden = !isManagement();
  $("tabs").hidden = !isManagement();
  $("workspaceBar").hidden = !isManagement();
  $("newCaseButton").hidden = state.user.role !== "agent";
  $("refreshButton").hidden = state.user.role === "agent";
}

function showApp() {
  $("loginView").hidden = true; $("appView").hidden = false;
  $("accountName").textContent = state.user.displayName;
  $("accountRole").textContent = state.user.role === "manager" ? "Manager · Read only" : state.user.role;
  $("accountAvatar").textContent = initials(state.user.displayName);
  applyRoleVisibility();
  switchView(isManagement() ? state.view : "cases");
}

function initials(name) { return String(name || "CF").split(/\s+/).slice(0, 2).map((part) => part[0]).join("").toUpperCase(); }

async function signOut(callServer = true) {
  state.liveGeneration += 1;
  if (callServer && state.token) await api("/auth/logout", { method: "POST", body: {} }).catch(() => {});
  localStorage.removeItem("cfToken"); sessionStorage.removeItem("cfToken");
  state.token = null; state.user = null; state.cases = []; state.notifications = [];
  if ($("requiredPasswordDialog").open) $("requiredPasswordDialog").close();
  state.unreadNotifications = 0; showLogin();
}

async function restore() {
  if (!state.token) return showLogin();
  try {
    state.user = (await api("/auth/me")).user;
    if (state.user.mustChangePassword) return showRequiredPasswordChange();
    showApp(); await loadData(); startLiveUpdates();
  } catch (error) {
    localStorage.removeItem("cfToken"); sessionStorage.removeItem("cfToken"); state.token = null; showLogin(error.message);
  }
}

async function loadData({ silent = false } = {}) {
  if (!silent) $("refreshButton").disabled = true;
  try {
    const notificationRequest = api("/notifications?limit=100");
    if (isManagement()) {
      const [users, agencies, cases] = await Promise.all([api("/admin/users"), api("/admin/agencies"), api("/admin/cases")]);
      state.users = users.users; state.agencies = agencies.agencies; state.cases = cases.cases;
      renderAgencyOptions();
    } else {
      state.cases = (await api("/cases")).cases;
    }
    const inbox = await notificationRequest;
    state.notifications = inbox.notifications; state.unreadNotifications = inbox.unreadCount;
    renderFilterChips(); updateOverview(); renderCurrentView(); renderNotifications();
  } finally { $("refreshButton").disabled = false; }
}

function notificationTime(value) {
  const seconds = Math.max(0, Math.floor((Date.now() - new Date(value).getTime()) / 1000));
  if (seconds < 60) return "Now";
  if (seconds < 3600) return `${Math.floor(seconds / 60)} min`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)} hr`;
  if (seconds < 604800) return `${Math.floor(seconds / 86400)} day`;
  return new Intl.DateTimeFormat(undefined, { dateStyle: "medium" }).format(new Date(value));
}

function renderNotifications() {
  const unread = state.unreadNotifications;
  $("notificationBadge").hidden = unread === 0;
  $("notificationBadge").textContent = unread > 99 ? "99+" : String(unread);
  $("notificationSummary").textContent = unread ? `${unread} unread` : "You're all caught up";
  $("markAllNotificationsRead").hidden = unread === 0;
  $("notificationEmpty").hidden = state.notifications.length > 0;
  $("notificationList").innerHTML = state.notifications.map((item) => `
    <button class="notification-item ${item.readAt ? "" : "unread"}" type="button"
      data-notification-id="${escapeHTML(item.id)}" data-notification-case="${escapeHTML(item.caseID || "")}">
      <strong>${escapeHTML(item.title)}</strong>
      <p>${escapeHTML(item.body)}</p>
      <footer><span>${escapeHTML(item.caseReference || "Customer Flow")}</span><time>${escapeHTML(notificationTime(item.createdAt))}</time></footer>
    </button>`).join("");
  document.querySelectorAll("[data-notification-id]").forEach((button) => {
    button.onclick = () => openNotification(button.dataset.notificationId, button.dataset.notificationCase);
  });
}

async function openNotification(notificationID, caseID) {
  const item = state.notifications.find((entry) => entry.id === notificationID);
  if (!caseID && item && !item.readAt) {
    item.readAt = new Date().toISOString();
    state.unreadNotifications = Math.max(0, state.unreadNotifications - 1);
    renderNotifications();
    await api("/notifications/read", { method: "POST", body: { notificationIDs: [notificationID] } }).catch(() => {});
  }
  setNotificationMenu(false);
  if (caseID) await openCase(caseID);
}

async function markCaseNotificationsRead(caseID) {
  if (!caseID || state.unreadNotifications === 0) return;
  const unread = unreadCaseNotifications(caseID);
  const previousUnreadCount = state.unreadNotifications;
  const now = new Date().toISOString();
  unread.forEach((item) => { item.readAt = now; });
  state.unreadNotifications = Math.max(0, state.unreadNotifications - unread.length);
  if (unread.length) {
    renderNotifications();
    if (state.view === "cases") renderCases();
  }
  try {
    const result = await api("/notifications/read", { method: "POST", body: { caseID } });
    state.unreadNotifications = Math.max(0, previousUnreadCount - Math.max(result.updatedCount, unread.length));
    renderNotifications();
  } catch (_) {
    const inbox = await api("/notifications?limit=100").catch(() => null);
    if (inbox) {
      state.notifications = inbox.notifications;
      state.unreadNotifications = inbox.unreadCount;
      renderNotifications();
      if (state.view === "cases") renderCases();
    }
  }
}

function startLiveUpdates() {
  const generation = ++state.liveGeneration;
  const loop = async () => {
    while (generation === state.liveGeneration && state.token) {
      try {
        const result = await api(`/events?since=${Math.max(-1, state.liveRevision)}`);
        state.liveRevision = result.revision ?? state.liveRevision;
        if (result.changed) await loadData({ silent: true });
      } catch (error) { if (!state.token) return; await new Promise((resolve) => setTimeout(resolve, 2500)); }
    }
  };
  loop();
}

function updateOverview() {
  const active = (status) => state.cases.filter((c) => c.status === status && !c.completedAt).length;
  const values = [state.cases.length, active("waiting"), active("answered"),
    state.cases.filter((c) => c.status === "closed").length,
    state.cases.filter((c) => Boolean(c.completedAt)).length];
  values.forEach((value, i) => { $(`overviewValue${i + 1}`).textContent = value; });
  if (state.user.role === "doctor") {
    $("overviewLabel1").textContent = "All Cases";
    $("overviewLabel2").textContent = "In Review";
    $("overviewLabel3").textContent = "Answered";
    $("overviewLabel4").textContent = "Confirmed";
    $("overviewLabel5").textContent = "Closed";
  } else if (state.user.role === "agent") {
    $("overviewLabel1").textContent = "All Cases";
    $("overviewLabel2").textContent = "In Review";
    $("overviewLabel3").textContent = "Action Needed";
    $("overviewLabel4").textContent = "Confirmed";
    $("overviewLabel5").textContent = "Closed";
  }
}

function setChipGroup(id, items, selected, key) {
  const node = $(id); if (!node) return;
  node.innerHTML = items.map(([value, label]) => `<button type="button" class="filter-chip ${value === selected ? "active" : ""}" data-filter-key="${escapeHTML(key)}" data-filter-value="${escapeHTML(value)}">${escapeHTML(label)}</button>`).join("");
}

function renderFilterChips() {
  const agencies = state.agencies.slice().sort((a, b) => a.name.localeCompare(b.name));
  const doctors = state.users.filter((u) => u.role === "doctor").sort((a, b) => a.displayName.localeCompare(b.displayName));
  const statusFilters = state.user?.role === "agent"
    ? [["", "All Cases"], ["waiting", "In Review"], ["answered", "Action Needed"], ["closed", "Confirmed"], ["completed", "Closed"]]
    : state.user?.role === "doctor"
      ? [["", "All Cases"], ["waiting", "In Review"], ["answered", "Answered"], ["closed", "Confirmed"], ["completed", "Closed"]]
    : [["", "All"], ["waiting", "Waiting"], ["answered", "Action needed"], ["closed", "Confirmed"], ["completed", "Closed"]];
  setChipGroup("caseStatusChips", statusFilters, state.filters.caseStatus, "caseStatus");
  setChipGroup("caseAssignmentChips", [["", "All"], ["assigned", "Assigned"], ["unassigned", "Unassigned"]], state.filters.caseAssignment, "caseAssignment");
  setChipGroup("caseAgencyChips", [["", "All"], ...agencies.map((a) => [a.name, a.name])], state.filters.caseAgency, "caseAgency");
  setChipGroup("caseDoctorChips", [["", "All"], ...doctors.map((d) => [d.id, d.displayName])], state.filters.caseDoctor, "caseDoctor");
  setChipGroup("userRoleChips", [["", "All"], ["agent", "Agents"], ["doctor", "Doctors"], ["manager", "Managers"], ["admin", "Admins"]], state.filters.userRole, "userRole");
  setChipGroup("userStatusChips", [["", "All"], ["active", "Active"], ["inactive", "Inactive"]], state.filters.userStatus, "userStatus");
  setChipGroup("userAgencyChips", [["", "All"], ...agencies.map((a) => [a.id, a.name])], state.filters.userAgency, "userAgency");
  document.querySelectorAll("[data-filter-key]").forEach((button) => button.onclick = () => {
    state.filters[button.dataset.filterKey] = button.dataset.filterValue; renderFilterChips(); renderCurrentView();
  });
  $("clearCaseFilters").hidden = !["caseStatus", "caseAssignment", "caseAgency", "caseDoctor"].some((k) => state.filters[k]);
  $("clearUserFilters").hidden = !["userRole", "userStatus", "userAgency"].some((k) => state.filters[k]);
}

function filteredCases() {
  const query = $("searchInput").value.trim().toLocaleLowerCase();
  const unreadActivityByCase = new Map();
  state.notifications.forEach((notification) => {
    if (notification.readAt || !notification.caseID) return;
    const caseID = String(notification.caseID).toLowerCase();
    const activityTime = Date.parse(notification.createdAt) || 0;
    unreadActivityByCase.set(caseID, Math.max(unreadActivityByCase.get(caseID) || 0, activityTime));
  });

  return state.cases.filter((item) => {
    const haystack = `${patientName(item)} ${item.reference || ""} ${item.agentName || ""} ${item.agencyName || ""} ${item.doctorName || ""} ${caseNote(item)}`.toLocaleLowerCase();
    const assignmentOK = !state.filters.caseAssignment || (state.filters.caseAssignment === "assigned" ? Boolean(doctorID(item)) : !doctorID(item));
    const statusOK = !state.filters.caseStatus
      || (state.filters.caseStatus === "completed" ? Boolean(item.completedAt) : item.status === state.filters.caseStatus && !item.completedAt);
    return (!query || haystack.includes(query)) && statusOK && assignmentOK
      && (!state.filters.caseAgency || item.agencyName === state.filters.caseAgency) && (!state.filters.caseDoctor || doctorID(item) === state.filters.caseDoctor);
  }).sort((left, right) => {
    const leftActivity = unreadActivityByCase.get(String(left.id).toLowerCase());
    const rightActivity = unreadActivityByCase.get(String(right.id).toLowerCase());
    if (leftActivity === undefined && rightActivity === undefined) return 0;
    if (leftActivity === undefined) return 1;
    if (rightActivity === undefined) return -1;
    return rightActivity - leftActivity;
  });
}

function renderCurrentView() {
  if (state.view === "cases") renderCases();
  else if (state.view === "users") renderUsers();
  else if (state.view === "agencies") renderAgencies();
  else renderClientVersion();
}

function renderCases() {
  const rows = filteredCases();
  if (!isManagement()) {
    $("caseCards").innerHTML = rows.map(caseCardHTML).join("");
    document.querySelectorAll("[data-open-case]").forEach((node) => node.onclick = () => openCase(node.dataset.openCase));
  } else renderManagementCases(rows);
  $("casesEmpty").hidden = rows.length > 0;
}

function caseCardHTML(item) {
  const latest = latestMessage(item); const status = statusPresentation(item.status, item.completedAt);
  const agent = item.agentName || "Agency representative"; const agency = item.agencyName || "No agency";
  const bandTone = item.completedAt ? "completed" : item.status === "closed" ? "closed" :
    ((state.user?.role === "agent" ? item.status === "answered" : item.status === "waiting") ? "needs-action" : "waiting-on-other");
  return `<button class="case-card" data-open-case="${escapeHTML(item.id)}" type="button">
    <div class="case-card-body">
      <div class="case-title-row"><strong>${escapeHTML(patientName(item))}</strong>${caseNotificationBadgeHTML(item.id)}<span class="case-age">${relativeTime(item.patient?.lastUpdated || item.uploadedAt)}</span></div>
      <div class="case-meta"><span class="agency-name">▦ ${escapeHTML(agency)}</span><span class="push">◉ ${escapeHTML(agent)}</span></div>
      <p class="case-summary">${escapeHTML(caseNote(item) || latest?.text || "Open the consultation to review patient details.")}</p>
      <div class="case-metrics"><span class="metric"><small>Est. grafts</small><strong>${escapeHTML(caseGrafts(item))}</strong></span><span class="metric"><small>Est. price</small><strong>£${escapeHTML(casePrice(item))}</strong></span><span class="metric"><small>Media</small><strong>${photoIDs(item).length} · ${(item.messages || []).length}</strong></span></div>
      ${latest ? `<div class="latest-row"><strong>${escapeHTML(latest.authorName || latest.author || "Update")}</strong><span class="message-preview">${escapeHTML(latest.text || "Photo sent")}</span><time>${relativeTime(latest.createdAt)}</time></div>` : ""}
    </div><div class="status-band ${escapeHTML(bandTone)}">${status.icon} ${escapeHTML(status.label)}</div></button>`;
}

function renderManagementCases(rows) {
  const doctors = state.users.filter((u) => u.role === "doctor" && u.active);
  $("casesBody").innerHTML = rows.map((item) => `<tr data-open-case="${escapeHTML(item.id)}">
    <td><div class="identity"><div class="case-patient-row"><strong>${escapeHTML(patientName(item))}</strong>${caseNotificationBadgeHTML(item.id)}</div><small>${escapeHTML(item.reference)}</small></div></td><td>${item.messageCount ?? item.messages?.length ?? 0}</td>
    <td><span class="status ${escapeHTML(statusPresentation(item.status, item.completedAt).className)}">${escapeHTML(statusPresentation(item.status, item.completedAt).label)}</span></td>
    <td><div class="identity"><strong>${escapeHTML(item.agentName)}</strong><small>${escapeHTML(item.agencyName || "No agency")}</small></div></td>
    <td>${state.user.role === "manager" ? escapeHTML(item.doctorName || "Unassigned") : `<select class="doctor-select" data-patient="${escapeHTML(patientID(item))}" data-previous="${escapeHTML(item.doctorID || "")}"><option value="">Unassigned</option>${doctors.map((d) => `<option value="${escapeHTML(d.id)}" ${d.id === item.doctorID ? "selected" : ""}>${escapeHTML(d.displayName)}</option>`).join("")}</select>`}</td>
    <td>${item.photoCount}</td><td><div class="identity"><strong>${escapeHTML(caseGrafts(item))}</strong><small>£${escapeHTML(casePrice(item))}</small></div></td><td>${formatDate(item.uploadedAt)}</td>
    <td><div class="row-actions"><button class="row-action" data-open-case="${escapeHTML(item.id)}">Open</button>${canMutateAdmin() ? `<button class="row-action danger" data-delete-case="${escapeHTML(item.id)}" data-case-reference="${escapeHTML(item.reference)}">Delete</button>` : ""}</div></td></tr>`).join("");
  document.querySelectorAll("[data-open-case]").forEach((node) => node.onclick = (event) => { event.stopPropagation(); openCase(node.dataset.openCase); });
  document.querySelectorAll(".doctor-select").forEach((node) => node.onchange = assignDoctor);
  document.querySelectorAll("[data-delete-case]").forEach((node) => node.onclick = deleteCase);
}

function statusPresentation(status, completedAt = null) {
  if (completedAt) return { label: "Closed", icon: "✓", className: "completed" };
  if (status === "waiting") return { label: "Waiting for doctor", icon: "◷", className: "waiting" };
  if (status === "answered") return { label: state.user?.role === "doctor" ? "Waiting for agent confirmation" : "Action needed", icon: "!", className: "answered" };
  return { label: "Confirmed", icon: "✓", className: "closed" };
}

function relativeTime(value) {
  if (!value) return ""; const seconds = Math.max(0, Math.floor((Date.now() - new Date(value)) / 1000));
  if (seconds < 3600) return `${Math.max(1, Math.round(seconds / 60))} min`;
  if (seconds < 86400) return `${Math.round(seconds / 3600)} hr`;
  return `${Math.round(seconds / 86400)} d`;
}

function formatDate(value) { return value ? new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" }).format(new Date(value)) : "—"; }
function formatDOB(value) { if (!value) return ""; const [y, m, d] = value.split("-"); return `${d}/${m}/${y}`; }

async function openCase(id) {
  state.selectedCaseID = id; let item = state.cases.find((c) => c.id === id);
  void markCaseNotificationsRead(id);
  $("caseDialogTitle").textContent = patientName(item); $("caseDialogEyebrow").textContent = "Loading consultation…";
  $("caseDialogContent").innerHTML = `<div class="loading">Loading patient details…</div>`; $("caseDialog").showModal();
  try {
    if (!isManagement()) item = (await api(`/cases/${encodeURIComponent(id)}`)).case;
    renderCaseDetail(item);
  } catch (error) { $("caseDialogContent").innerHTML = `<p class="form-error">${escapeHTML(error.message)}</p>`; }
}

function renderCaseDetail(item) {
  const patient = item.patient || { name: item.patientName, age: item.age, statedAge: item.statedAge, dateOfBirth: item.dateOfBirth, gender: item.gender, phone: item.patientPhone, email: item.patientEmail, address: item.patientAddress, city: item.city, region: item.region, occupation: item.occupation, profileNote: item.profileNote };
  const status = statusPresentation(item.status, item.completedAt); const ids = photoIDs(item); const messages = item.messages || [];
  $("caseDialogTitle").textContent = patient.name; $("caseDialogEyebrow").textContent = `${item.reference} · ${status.label}`;
  const details = [["Date of birth", formatDOB(patient.dateOfBirth)], ["Age", patient.age], ["Gender", prettyGender(patient.gender)], ["Phone", patient.phone], ["Email", patient.email], ["Address", patient.address], ["City", patient.city], ["Region", patient.region], ["Occupation", patient.occupation], ["Info", patient.profileNote]].filter(([, v]) => v !== null && v !== undefined && v !== "");
  const mayEdit = canEditAgentCase(item);
  $("caseDialogContent").innerHTML = `<section class="case-hero"><div><span class="status ${escapeHTML(status.className)}">${escapeHTML(status.label)}</span><h3>${escapeHTML(patient.name)}</h3><p>${escapeHTML(caseNote(item) || "Patient consultation")}</p></div><div class="case-metrics"><span class="metric"><small>${item.status === "closed" ? "Final" : "Estimated"} grafts</small><strong>${escapeHTML(caseGrafts(item))}</strong></span><span class="metric"><small>${item.status === "closed" ? "Final" : "Estimated"} price</small><strong>£${escapeHTML(casePrice(item))}</strong></span>${item.appointmentAt ? `<span class="metric"><small>Appointment</small><strong>${escapeHTML(formatDate(item.appointmentAt))}</strong></span>` : ""}</div></section>
    ${item.status === "closed" ? unconfirmControl(item) : (mayEdit && !item.completedAt && latestDoctorRecommendation(item) ? closeCaseForm(item) : "")}
    ${details.length || mayEdit ? patientDetailCard(item, patient, details, mayEdit && item.status !== "closed") : ""}
    <section class="detail-section"><div class="section-heading"><h3>Photos</h3><span>${ids.length} photos</span></div><div class="photo-grid">${renderPhotos(item)}</div>${mayEdit ? `<label class="upload-button">+ Add photos<input id="detailPhotoUpload" type="file" accept="image/*" multiple hidden></label>` : ""}</section>
    <section id="conversationSection" class="detail-section"><div class="section-heading"><h3>Conversation</h3><span>${messages.length} updates</span></div><div class="conversation">${messages.map((m) => messageHTML(item, m)).join("") || `<p>No messages yet.</p>`}</div>${completionControl(item)}${conversationForm(item)}</section>`;
  bindDetailActions(item);
}

// The API only returns cases belonging to the signed-in agent's agency and
// enforces the same agency boundary on every mutation. A case may have been
// created by the agency's MCP service account, so comparing its agent ID with
// the current employee would incorrectly make that shared case read-only.
function canEditAgentCase(_item) { return state.user.role === "agent"; }

function patientDetailCard(item, patient, details, editable) {
  return `<section class="detail-section patient-flip-card"><div id="patientFlipper" class="patient-flipper">
    <div class="patient-face patient-view-face"><div class="section-heading"><h3>Patient details</h3>${editable ? `<button id="showPatientEdit" class="row-action" type="button">Edit</button>` : ""}</div><dl class="patient-details">${details.map(([k, v]) => `<dt>${escapeHTML(k)}</dt><dd>${escapeHTML(v)}</dd>`).join("") || `<dd>No additional patient information.</dd>`}</dl></div>
    <div class="patient-face patient-edit-face"><form id="editCaseForm" class="inline-form edit-case-form"><div class="section-heading"><h3>Edit patient details</h3><button id="cancelPatientEdit" class="row-action" type="button">Cancel</button></div>
    <label>Patient name<input id="editPatientName" value="${escapeHTML(patient.name)}" required></label>
    <div class="inline-fields"><label>Estimated grafts<input id="editGrafts" value="${escapeHTML(item.agentGrafts || item.grafts || "")}" required></label><label>Estimated price (£)<input id="editPrice" value="${escapeHTML(item.agentPrice || item.price || "")}" required></label></div>
    <div class="inline-fields"><label>Date of birth<input id="editDOB" type="date" value="${escapeHTML(patient.dateOfBirth || "")}"></label><label>Age<input id="editAge" type="number" min="0" max="130" value="${escapeHTML(patient.statedAge || "")}"></label></div>
    <div class="inline-fields"><label>Gender<select id="editGender"><option value="">Not specified</option>${["male","female","non_binary","other","prefer_not_to_say"].map((v) => `<option value="${v}" ${patient.gender === v ? "selected" : ""}>${prettyGender(v)}</option>`).join("")}</select></label><label>Phone<input id="editPhone" value="${escapeHTML(patient.phone || "")}"></label></div>
    <div class="inline-fields"><label>Email<input id="editEmail" type="email" value="${escapeHTML(patient.email || "")}"></label><label>Occupation<input id="editOccupation" value="${escapeHTML(patient.occupation || "")}"></label></div>
    <label>Address<input id="editAddress" value="${escapeHTML(patient.address || "")}"></label>
    <div class="inline-fields"><label>City<input id="editCity" value="${escapeHTML(patient.city || "")}"></label><label>Region<input id="editRegion" value="${escapeHTML(patient.region || "")}"></label></div>
    <label>Short patient information<textarea id="editProfileNote" rows="2">${escapeHTML(patient.profileNote || "")}</textarea></label>
    <div class="section-actions"><button class="primary" type="submit">Save details</button></div></form></div>
  </div></section>`;
}

function prettyGender(value) { return value ? String(value).replaceAll("_", " ").replace(/\b\w/g, (c) => c.toUpperCase()) : ""; }

function renderPhotos(item) {
  const photos = item.photos || photoIDs(item).map((id, i) => ({ id, position: i + 1, available: true, deleted: false }));
  if (!photos.length) return `<div class="no-photos">No photos uploaded</div>`;
  const mayDelete = canEditAgentCase(item);
  return photos.map((photo, index) => `<div class="photo-tile ${photo.deleted ? "deleted-photo" : ""}" data-photo-id="${escapeHTML(photo.id)}" data-photo-index="${index}"><div class="image-placeholder">Loading…</div><span class="photo-number">${photo.position || index + 1}</span>${photo.deleted ? `<span class="deleted-overlay">Deleted${photo.deletedByName ? ` by ${escapeHTML(photo.deletedByName)}` : ""}</span>${canMutateAdmin() ? `<button class="photo-delete" data-purge-photo="${escapeHTML(photo.id)}">×</button>` : ""}` : mayDelete ? `<button class="photo-delete" data-delete-photo="${escapeHTML(photo.id)}">⌫</button>` : ""}</div>`).join("");
}

function messageHTML(item, message) {
  const deleted = Boolean(message.deletedAt); const author = message.authorName || message.author || "System";
  const own = message.authorID === state.user.id || author === state.user.displayName;
  const attachment = message.attachmentPhotoID || message.attachmentID;
  const role = message.role === "admin" ? "Operational" : (message.role || "");
  return `<article class="message ${deleted ? "deleted" : ""}"><div class="message-head"><strong>${escapeHTML(author)}</strong><span>${escapeHTML(role)}</span><time>${relativeTime(message.createdAt)}</time>${!deleted && own && ["agent", "doctor"].includes(state.user.role) ? `<button class="row-action danger" data-delete-message="${escapeHTML(message.id)}">Delete</button>` : ""}</div><p>${escapeHTML(deleted ? "Deleted message" : (message.text || "Photo sent"))}</p>${message.approximateGrafts ? `<small>Recommended grafts: ${escapeHTML(message.approximateGrafts)}</small>` : ""}${message.recommendedPrice ? `<small>Recommended price: ${escapeHTML(message.recommendedPrice)}</small>` : ""}${attachment && !deleted ? `<div class="message-photo image-placeholder" data-message-photo="${escapeHTML(attachment)}">Loading photo…</div>` : ""}</article>`;
}

function conversationForm(item) {
  if (isManagement()) return `<form id="managementReplyForm" class="inline-form"><h3>Add operational note</h3><textarea id="replyText" rows="3" placeholder="Write an operational note" required></textarea><p class="field-hint">Operational notes do not change the case status or medical assessment.</p><div class="section-actions"><button class="primary" type="submit">Send note</button></div></form>`;
  if (item.status === "closed") return "";
  if (state.user.role === "doctor") return `<form id="doctorReplyForm" class="inline-form"><h3>${item.completedAt ? "Send a message to reopen" : "Reply to agent"}</h3><div class="inline-fields"><input id="replyGrafts" placeholder="Grafts (optional)"><input id="replyPrice" placeholder="Price (optional)"></div><textarea id="replyText" rows="3" placeholder="Write your assessment or question" required></textarea><div class="section-actions"><button class="primary" type="submit">Send reply</button></div></form>`;
  if (!canEditAgentCase(item)) return "";
  return `<form id="agentReplyForm" class="inline-form"><h3>${item.completedAt ? "Send a message to reopen" : "Add an update or question"}</h3><textarea id="replyText" rows="3" placeholder="Write a follow-up for the doctor" required></textarea><div class="section-actions"><button class="primary" type="submit">Send update</button></div></form>`;
}

function completionControl(item) {
  if (item.completedAt) return `<div class="completion-panel"><div><strong>✓ Closed by ${escapeHTML(item.completedByName || "a team member")}</strong><small>${formatDate(item.completedAt)}</small></div><p>A new doctor or agent message will reopen this case automatically.</p></div>`;
  const canComplete = item.status !== "closed" && canEditAgentCase(item);
  return canComplete ? `<div class="completion-action"><span>Consultation finished?</span><button class="close-case-button compact" id="completeCaseButton" type="button">✓ Mark as closed</button></div>` : "";
}

function closeCaseForm(item) {
  const recommendation = latestDoctorRecommendation(item);
  const localDate = (date) => [date.getFullYear(), String(date.getMonth() + 1).padStart(2, "0"), String(date.getDate()).padStart(2, "0")].join("-");
  const today = new Date();
  const defaultAppointment = new Date(); defaultAppointment.setDate(defaultAppointment.getDate() + 1);
  return `<section class="detail-section confirmation-section"><form id="closeCaseForm" class="confirmation-form"><div class="confirmation-copy"><h3>Confirm appointment</h3><p>Finalise the agreed plan and schedule.</p></div><label>Final grafts<input id="finalGrafts" value="${escapeHTML(recommendation?.approximateGrafts || item.agentGrafts || "")}" placeholder="Grafts" required></label><label>Final price (£)<input id="finalPrice" value="${escapeHTML(String(recommendation?.recommendedPrice || item.agentPrice || "").replace(/[^0-9.,-]/g, ""))}" placeholder="Price" required></label><label>Appointment date<input id="appointmentDate" type="date" min="${localDate(today)}" value="${localDate(defaultAppointment)}" required></label><label>Time<input id="appointmentTime" type="time" value="09:00" required></label><button class="confirmation-submit" type="submit">✓ Confirm</button></form></section>`;
}

function latestDoctorRecommendation(item) {
  return [...(item.messages || [])].reverse().find((message) =>
    message.role === "doctor" && (message.approximateGrafts || message.recommendedPrice)
  );
}

function unconfirmControl(item) {
  if (state.user?.role !== "admin") return "";
  return `<section class="detail-section confirmation-section unconfirm-section"><div class="confirmation-copy"><h3>Confirmed appointment</h3><p>Undo the confirmation if the plan or appointment was recorded incorrectly.</p></div><button class="unconfirm-button" id="unconfirmCaseButton" type="button">Undo confirmation</button></section>`;
}

function bindDetailActions(item) {
  bindPatientFlipper();
  loadDetailImages(item);
  $("detailPhotoUpload")?.addEventListener("change", uploadDetailPhotos);
  $("doctorReplyForm")?.addEventListener("submit", submitDoctorReply);
  $("agentReplyForm")?.addEventListener("submit", submitAgentReply);
  $("managementReplyForm")?.addEventListener("submit", submitManagementReply);
  $("closeCaseForm")?.addEventListener("submit", submitCloseCase);
  $("unconfirmCaseButton")?.addEventListener("click", submitUnconfirmCase);
  $("completeCaseButton")?.addEventListener("click", submitCompleteCase);
  $("editCaseForm")?.addEventListener("submit", submitCaseEdit);
  document.querySelectorAll("[data-delete-message]").forEach((b) => b.onclick = deleteMessage);
  document.querySelectorAll("[data-delete-photo]").forEach((b) => b.onclick = deletePhoto);
  document.querySelectorAll("[data-purge-photo]").forEach((b) => b.onclick = purgePhoto);
}

function bindPatientFlipper() {
  const flipper = $("patientFlipper"); if (!flipper) return;
  const front = flipper.querySelector(".patient-view-face"), back = flipper.querySelector(".patient-edit-face");
  const fit = (face) => { flipper.style.height = `${face.scrollHeight}px`; };
  fit(front);
  $("showPatientEdit")?.addEventListener("click", () => { fit(back); flipper.classList.add("is-editing"); setTimeout(() => $("editPatientName")?.focus(), 220); });
  $("cancelPatientEdit")?.addEventListener("click", () => { fit(front); flipper.classList.remove("is-editing"); });
  const observer = new ResizeObserver(() => fit(flipper.classList.contains("is-editing") ? back : front));
  observer.observe(front); observer.observe(back);
}

async function submitCaseEdit(event) {
  event.preventDefault();
  const body = { patientName: $("editPatientName").value.trim(), grafts: $("editGrafts").value.trim(), currency: "GBP", price: $("editPrice").value.trim(), patientProfile: { dateOfBirth: $("editDOB").value || null, age: $("editDOB").value ? null : Number($("editAge").value) || null, gender: $("editGender").value || null, phone: $("editPhone").value.trim() || null, email: $("editEmail").value.trim() || null, address: $("editAddress").value.trim() || null, city: $("editCity").value.trim() || null, region: $("editRegion").value.trim() || null, occupation: $("editOccupation").value.trim() || null, profileNote: $("editProfileNote").value.trim() || null } };
  await mutate(`/cases/${state.selectedCaseID}/agent-values`, { method: "PATCH", body }, "Case details updated.");
}

async function authenticatedImage(path, cacheKey = path) {
  if (state.blobURLs.has(cacheKey)) return state.blobURLs.get(cacheKey);
  const response = await api(path, { raw: true }); const url = URL.createObjectURL(await response.blob()); state.blobURLs.set(cacheKey, url); return url;
}

async function loadDetailImages(item) {
  const tiles = [...$("caseDialogContent").querySelectorAll("[data-photo-id]")];
  await Promise.all(tiles.map(async (tile) => {
    try { const url = await authenticatedImage(`/photos/${encodeURIComponent(tile.dataset.photoId)}`); tile.querySelector(".image-placeholder").outerHTML = `<img src="${url}" alt="Patient photo">`; if (!tile.classList.contains("deleted-photo")) tile.onclick = (e) => { if (!e.target.closest("button")) openPhotoViewer(item, Number(tile.dataset.photoIndex)); }; } catch { tile.querySelector(".image-placeholder").textContent = "Photo unavailable"; }
  }));
  await Promise.all([...$("caseDialogContent").querySelectorAll("[data-message-photo]")].map(async (node) => {
    try { const url = await authenticatedImage(`/message-photos/${encodeURIComponent(node.dataset.messagePhoto)}`); node.outerHTML = `<img src="${url}" alt="Annotated patient photo">`; } catch { node.textContent = "Photo unavailable"; }
  }));
}

async function reloadSelected(message = "") {
  await loadData({ silent: true }); if (state.selectedCaseID) await openCase(state.selectedCaseID); if (message) toast(message);
}

async function submitDoctorReply(event) {
  event.preventDefault(); const body = { text: $("replyText").value.trim(), approximateGrafts: $("replyGrafts").value.trim() || null, recommendedPrice: $("replyPrice").value.trim() || null };
  await mutate(`/cases/${state.selectedCaseID}/doctor-messages`, { method: "POST", body }, "Reply sent.");
}
async function submitAgentReply(event) { event.preventDefault(); await mutate(`/cases/${state.selectedCaseID}/agent-updates`, { method: "POST", body: { text: $("replyText").value.trim() } }, "Update sent."); }
async function submitManagementReply(event) { event.preventDefault(); await mutate(`/cases/${state.selectedCaseID}/management-messages`, { method: "POST", headers: { "Idempotency-Key": crypto.randomUUID() }, body: { text: $("replyText").value.trim() } }, "Operational note sent."); }
async function submitCompleteCase() {
  if (!window.confirm("Mark this case as closed? A new doctor or agent message will reopen it automatically.")) return;
  await mutate(`/cases/${state.selectedCaseID}/complete`, { method: "POST", body: {} }, "Case marked as closed.");
}
async function submitCloseCase(event) {
  event.preventDefault();
  const appointmentAt = new Date(`${$("appointmentDate").value}T${$("appointmentTime").value}:00`);
  if (Number.isNaN(appointmentAt.getTime())) return toast("Choose a valid appointment date and time.");
  await mutate(`/cases/${state.selectedCaseID}/close`, {
    method: "POST",
    body: { finalGrafts: $("finalGrafts").value.trim(), finalPrice: $("finalPrice").value.trim(), appointmentAt: appointmentAt.toISOString() }
  }, "Appointment confirmed.");
}
async function submitUnconfirmCase() {
  if (!window.confirm("Undo this confirmation? The final grafts, price and appointment will be cleared, and the case will return to Waiting for agent.")) return;
  await mutate(`/admin/cases/${state.selectedCaseID}/unconfirm`, {
    method: "POST",
    body: {}
  }, "Confirmation removed.");
}
async function mutate(path, options, message) { try { await api(path, options); await reloadSelected(message); } catch (error) { toast(error.message); } }

async function uploadDetailPhotos(event) {
  for (const file of [...event.target.files]) await api(`/cases/${state.selectedCaseID}/photos`, { method: "POST", headers: { "Content-Type": file.type || "image/jpeg", "Idempotency-Key": crypto.randomUUID() }, body: file });
  await reloadSelected("Photos uploaded.");
}
async function deleteMessage(event) { if (!confirm("Remove this message from the conversation?")) return; await mutate(`/cases/${state.selectedCaseID}/messages/${event.currentTarget.dataset.deleteMessage}`, { method: "DELETE", body: {} }, "Message removed."); }
async function deletePhoto(event) { event.stopPropagation(); if (!confirm("Remove this photo from the agency and doctor views? The admin audit copy will remain.")) return; await mutate(`/cases/${state.selectedCaseID}/photos/${event.currentTarget.dataset.deletePhoto}`, { method: "DELETE", body: {} }, "Photo removed."); }
async function purgePhoto(event) { event.stopPropagation(); if (!confirm("Permanently delete this retained photo?")) return; await mutate(`/admin/photos/${event.currentTarget.dataset.purgePhoto}`, { method: "DELETE", body: {} }, "Photo permanently deleted."); }

function openPhotoViewer(item, index) {
  state.photoItems = photoIDs(item); state.photoIndex = Math.max(0, Math.min(index, state.photoItems.length - 1));
  $("editPhotoButton").hidden = !["agent", "doctor"].includes(state.user.role); $("photoDialog").showModal(); renderPhotoViewer();
}
async function renderPhotoViewer() {
  const id = state.photoItems[state.photoIndex]; $("photoCounter").textContent = `${state.photoIndex + 1} / ${state.photoItems.length}`;
  $("photoPreviewImage").src = await authenticatedImage(`/photos/${encodeURIComponent(id)}`);
  $("photoThumbnails").innerHTML = state.photoItems.map((pid, i) => `<button class="${i === state.photoIndex ? "active" : ""}" data-view-photo="${i}"><span>${i + 1}</span></button>`).join("");
  document.querySelectorAll("[data-view-photo]").forEach((b) => b.onclick = () => { state.photoIndex = Number(b.dataset.viewPhoto); renderPhotoViewer(); });
}

// Lightweight markup editor: pen drawing, undo, text, note and authenticated send.
const editor = { ctx: null, image: null, drawing: false, history: [], textItems: [] };
async function openEditor() {
  const src = $("photoPreviewImage").src; editor.image = await loadImage(src); $("photoMessageNote").value = ""; $("editorDialog").showModal();
  requestAnimationFrame(setupCanvas);
}
function closeEditor() { $("photoMessageNote").value = ""; $("editorDialog").close(); }
function loadImage(src) { return new Promise((resolve, reject) => { const image = new Image(); image.onload = () => resolve(image); image.onerror = reject; image.src = src; }); }
function setupCanvas() {
  const stage = $("canvasStage"), canvas = $("markupCanvas"), ratio = Math.min(stage.clientWidth / editor.image.naturalWidth, stage.clientHeight / editor.image.naturalHeight);
  canvas.width = editor.image.naturalWidth; canvas.height = editor.image.naturalHeight; canvas.style.width = `${editor.image.naturalWidth * ratio}px`; canvas.style.height = `${editor.image.naturalHeight * ratio}px`;
  editor.ctx = canvas.getContext("2d"); editor.ctx.drawImage(editor.image, 0, 0); editor.history = [editor.ctx.getImageData(0, 0, canvas.width, canvas.height)]; editor.textItems = []; $("textLayer").innerHTML = "";
  $("textLayer").style.width = canvas.style.width; $("textLayer").style.height = canvas.style.height;
}
function canvasPoint(event) { const canvas = $("markupCanvas"), rect = canvas.getBoundingClientRect(); return { x: (event.clientX - rect.left) * canvas.width / rect.width, y: (event.clientY - rect.top) * canvas.height / rect.height }; }
function editorPointerDown(event) { if (event.target !== $("markupCanvas")) return; editor.drawing = true; editor.ctx.beginPath(); const p = canvasPoint(event); editor.ctx.moveTo(p.x, p.y); }
function editorPointerMove(event) { if (!editor.drawing) return; const p = canvasPoint(event); editor.ctx.strokeStyle = $("penColor").value; editor.ctx.lineWidth = Number($("penWidth").value) * $("markupCanvas").width / $("markupCanvas").clientWidth; editor.ctx.lineCap = "round"; editor.ctx.lineJoin = "round"; editor.ctx.lineTo(p.x, p.y); editor.ctx.stroke(); }
function editorPointerUp() { if (!editor.drawing) return; editor.drawing = false; editor.history.push(editor.ctx.getImageData(0, 0, $("markupCanvas").width, $("markupCanvas").height)); }
function addEditorText() {
  const node = document.createElement("div"); node.className = "markup-text"; node.contentEditable = "true"; node.textContent = "Text"; node.style.left = "35%"; node.style.top = "40%"; node.style.fontSize = "28px"; node.innerHTML += `<span class="text-resize" contenteditable="false">↘</span>`; $("textLayer").append(node); editor.textItems.push(node); makeTextInteractive(node); node.focus(); document.execCommand("selectAll", false, null);
}
function makeTextInteractive(node) {
  let start = null; node.onpointerdown = (event) => { if (event.target.classList.contains("text-resize")) return; start = { x: event.clientX, y: event.clientY, l: node.offsetLeft, t: node.offsetTop }; node.setPointerCapture(event.pointerId); };
  node.onpointermove = (event) => { if (!start) return; node.style.left = `${start.l + event.clientX - start.x}px`; node.style.top = `${start.t + event.clientY - start.y}px`; }; node.onpointerup = () => { start = null; };
  const handle = node.querySelector(".text-resize"); let resize = null; handle.onpointerdown = (event) => { event.preventDefault(); resize = { x: event.clientX, size: parseFloat(getComputedStyle(node).fontSize) }; handle.setPointerCapture(event.pointerId); };
  handle.onpointermove = (event) => { if (resize) node.style.fontSize = `${Math.max(14, Math.min(90, resize.size + (event.clientX - resize.x) / 2))}px`; }; handle.onpointerup = () => { resize = null; };
}
async function sendEditedPhoto() {
  const canvas = $("markupCanvas"), rect = canvas.getBoundingClientRect();
  editor.textItems.forEach((node) => { const clone = node.cloneNode(true); clone.querySelector(".text-resize")?.remove(); const scale = canvas.width / rect.width; editor.ctx.font = `700 ${parseFloat(getComputedStyle(node).fontSize) * scale}px sans-serif`; editor.ctx.fillStyle = "white"; editor.ctx.strokeStyle = "rgba(0,0,0,.75)"; editor.ctx.lineWidth = 4 * scale; const text = clone.textContent.trim(); const x = node.offsetLeft * scale, y = (node.offsetTop + parseFloat(getComputedStyle(node).fontSize)) * scale; editor.ctx.strokeText(text, x, y); editor.ctx.fillText(text, x, y); });
  const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", .92)); const note = $("photoMessageNote").value.trim();
  try { await api(`/cases/${state.selectedCaseID}/message-photos`, { method: "POST", headers: { "Content-Type": "image/jpeg", "X-Message-Text": utf8Base64(note), "Idempotency-Key": crypto.randomUUID() }, body: blob }); closeEditor(); $("photoDialog").close(); await reloadSelected("Annotated photo sent."); requestAnimationFrame(() => $("conversationSection")?.scrollIntoView({ behavior: "smooth", block: "start" })); } catch (error) { toast(error.message); }
}
function utf8Base64(value) { const bytes = new TextEncoder().encode(value); let binary = ""; bytes.forEach((b) => { binary += String.fromCharCode(b); }); return btoa(binary); }

function openNewCase() { state.pendingFiles = []; state.duplicate = { matches: [], confirmed: false, existingPatientID: null }; $("newCaseForm").reset(); $("caseGrafts").value = "3200"; $("casePrice").value = "2850"; $("newCaseError").textContent = ""; renderPendingPhotos(); $("newCaseDialog").showModal(); setTimeout(() => $("casePatientName").focus(), 100); }
function renderPendingPhotos() { $("pendingPhotoGrid").innerHTML = state.pendingFiles.map((file, i) => `<div class="pending-photo"><img src="${URL.createObjectURL(file)}" alt="Selected photo"><button type="button" data-remove-pending="${i}">×</button></div>`).join(""); document.querySelectorAll("[data-remove-pending]").forEach((b) => b.onclick = () => { state.pendingFiles.splice(Number(b.dataset.removePending), 1); renderPendingPhotos(); }); }
async function checkPatientMatch() {
  const name = $("casePatientName").value.trim(); if (name.length < 3) return;
  try { state.duplicate.matches = (await api(`/patients/matches?name=${encodeURIComponent(name)}`)).matches || []; state.duplicate.confirmed = !state.duplicate.matches.length; state.duplicate.existingPatientID = null; renderMatchHint(); } catch (error) { $("patientMatchHint").textContent = error.message; }
}
function renderMatchHint() {
  const hint = $("patientMatchHint"); if (!state.duplicate.matches.length) { hint.textContent = ""; return; }
  hint.className = "field-hint warning"; hint.innerHTML = `A patient with this name is already registered. <span class="match-actions"><button type="button" class="row-action" id="openMatchedCase">Show details</button><button type="button" class="row-action" id="confirmSamePatient">Same patient · new case</button><button type="button" class="row-action" id="confirmDifferentPatient">Different patient</button></span>`;
  $("openMatchedCase").onclick = () => { const match = state.duplicate.matches[0]; const existing = state.cases.find((item) => patientID(item) === match.id); if (!existing) return toast("The previous consultation is not available in this view."); $("newCaseDialog").close(); openCase(existing.id); };
  $("confirmSamePatient").onclick = () => { state.duplicate.confirmed = true; state.duplicate.existingPatientID = state.duplicate.matches[0].id; hint.className = "field-hint"; hint.textContent = "Confirmed: a new consultation will be added to the existing patient."; };
  $("confirmDifferentPatient").onclick = () => { state.duplicate.confirmed = true; state.duplicate.existingPatientID = null; hint.className = "field-hint"; hint.textContent = "Confirmed as a different patient."; };
}
async function submitNewCase(event) {
  event.preventDefault(); if (state.pendingFiles.length < 1) return $("newCaseError").textContent = "Please add at least one photo.";
  if (state.duplicate.matches.length && !state.duplicate.confirmed) return $("newCaseError").textContent = "Confirm whether this is a different patient before continuing.";
  const submit = event.currentTarget.querySelector("button[type=submit]"); submit.disabled = true;
  try {
    const body = { patientName: $("casePatientName").value.trim(), grafts: $("caseGrafts").value.trim(), currency: "GBP", price: $("casePrice").value.trim(), note: $("caseNeed").value.trim(), photoCount: state.pendingFiles.length, duplicateConfirmedDifferent: state.duplicate.confirmed && !state.duplicate.existingPatientID, existingPatientID: state.duplicate.existingPatientID,
      patientProfile: { dateOfBirth: $("caseDateOfBirth").value || null, age: $("caseDateOfBirth").value ? null : Number($("caseAge").value) || null, gender: $("caseGender").value || null, phone: $("casePhone").value.trim() || null, email: $("caseEmail").value.trim() || null, address: $("caseAddress").value.trim() || null, city: $("caseCity").value.trim() || null, region: $("caseRegion").value.trim() || null, occupation: $("caseOccupation").value.trim() || null, profileNote: $("caseProfileNote").value.trim() || null } };
    const created = (await api("/cases", { method: "POST", headers: { "Idempotency-Key": crypto.randomUUID() }, body })).case;
    for (const file of state.pendingFiles) await api(`/cases/${created.id}/photos`, { method: "POST", headers: { "Content-Type": file.type || "image/jpeg", "Idempotency-Key": crypto.randomUUID() }, body: file });
    $("newCaseDialog").close(); await loadData(); toast("Case created."); await openCase(created.id);
  } catch (error) { $("newCaseError").textContent = error.message; } finally { submit.disabled = false; }
}

function renderUsers() {
  const q = $("searchInput").value.trim().toLocaleLowerCase(); const rows = state.users.filter((u) => `${u.displayName} ${u.username} ${u.role} ${u.agencyName || ""}`.toLocaleLowerCase().includes(q) && (!state.filters.userRole || u.role === state.filters.userRole) && (!state.filters.userStatus || (state.filters.userStatus === "active") === u.active) && (!state.filters.userAgency || u.agencyID === state.filters.userAgency));
  $("usersBody").innerHTML = rows.map((u) => `<tr><td><div class="identity"><strong>${escapeHTML(u.displayName)}</strong><small>${escapeHTML(u.id)}</small></div></td><td>${escapeHTML(u.username)}</td><td class="role">${escapeHTML(u.role)}</td><td>${escapeHTML(u.agencyName || "—")}</td><td>${u.role === "doctor" ? `${u.patientCount} patients` : u.role === "agent" ? `${u.caseCount} cases` : "System access"}</td><td><span class="${u.active ? "active-dot" : "inactive-dot"}">${u.active ? "Active" : "Inactive"}</span></td><td>${canMutateAdmin() && u.id !== state.user.id ? `<div class="row-actions"><button class="row-action" data-reset-password="${escapeHTML(u.id)}">Reset password</button><button class="row-action ${u.active ? "danger" : ""}" data-toggle-user="${escapeHTML(u.id)}">${u.active ? "Deactivate" : "Reactivate"}</button></div>` : ""}</td></tr>`).join("");
  $("usersEmpty").hidden = rows.length > 0; document.querySelectorAll("[data-toggle-user]").forEach((b) => b.onclick = toggleUser); document.querySelectorAll("[data-reset-password]").forEach((b) => b.onclick = resetUserPassword);
}
function renderAgencies() { const q = $("searchInput").value.trim().toLocaleLowerCase(); const rows = state.agencies.filter((a) => a.name.toLocaleLowerCase().includes(q)); $("agenciesBody").innerHTML = rows.map((a) => `<tr><td><strong>${escapeHTML(a.name)}</strong></td><td>${a.userCount}</td><td><span class="${a.mcpConfigured ? "active-dot" : "inactive-dot"}">${a.mcpConfigured ? "Connected" : "Not configured"}</span></td><td>${a.mcpRotatedAt ? formatDate(a.mcpRotatedAt) : "—"}</td><td>${canMutateAdmin() ? `<button class="row-action" data-agency-settings="${escapeHTML(a.id)}">Manage</button>` : ""}</td></tr>`).join(""); $("agenciesEmpty").hidden = rows.length > 0; document.querySelectorAll("[data-agency-settings]").forEach((b) => b.onclick = openAgencySettings); }

function renderClientVersion() {
  const policy = state.clientVersionPolicy;
  $("latestClientVersion").textContent = policy?.latestVersion || "Unavailable";
  $("minimumClientVersion").value = policy?.minimumVersion || "0.0.0";
  $("clientVersionStoreLink").href = policy?.storeURL || "https://apps.apple.com/gb/app/customerflow-by-natchatt/id6802274147";
  $("clientVersionCheckedAt").textContent = policy?.lastCheckedAt
    ? `Last checked ${formatDate(policy.lastCheckedAt)} · App ID ${policy.appID}`
    : "Apple could not be reached yet. Existing clients will not be blocked by this check.";
}

async function loadClientVersion() {
  if (!canMutateAdmin()) return;
  $("refreshClientVersion").disabled = true;
  $("clientVersionError").textContent = "";
  try {
    state.clientVersionPolicy = (await api("/admin/client-version/ios")).policy;
    renderClientVersion();
  } catch (error) {
    $("clientVersionError").textContent = error.message;
  } finally {
    $("refreshClientVersion").disabled = false;
  }
}

async function assignDoctor(event) { event.stopPropagation(); const select = event.currentTarget, previous = select.dataset.previous, doctor = select.value || null; let reason = ""; if (previous && previous !== (doctor || "")) { reason = prompt("Reason for changing the assigned doctor:", "Administrative reassignment") || ""; if (!reason.trim()) return select.value = previous; } try { await api(`/admin/patients/${encodeURIComponent(select.dataset.patient)}`, { method: "PATCH", body: { doctorID: doctor, reason } }); await loadData(); toast("Doctor assignment updated."); } catch (error) { select.value = previous; toast(error.message); } }
async function deleteCase(event) {
  event.stopPropagation();
  const button = event.currentTarget;
  if (!confirm(`Delete ${button.dataset.caseReference} from active records? Patient details, messages and photos will be retained.`)) return;
  await api(`/admin/cases/${button.dataset.deleteCase}`, { method: "DELETE" });
  await loadData();
  toast("Case deleted from active records.");
}
async function toggleUser(event) { const id = event.currentTarget.dataset.toggleUser, user = state.users.find((u) => u.id === id); if (user.active && !confirm("Deactivate this user and end active sessions?")) return; await api(`/admin/users/${id}`, { method: "PATCH", body: { active: !user.active } }); await loadData(); toast(user.active ? "User deactivated." : "User reactivated."); }
async function resetUserPassword(event) { const id = event.currentTarget.dataset.resetPassword, user = state.users.find((u) => u.id === id); if (!user || !confirm(`Reset ${user.displayName}'s password to demo123? All active sessions for this user will end, and they must choose a new password after signing in.`)) return; const button = event.currentTarget; button.disabled = true; try { await api(`/admin/users/${id}/reset-password`, { method: "POST", body: {} }); toast(`${user.displayName}'s password is now demo123. A password change will be required.`); } catch (error) { toast(error.message); } finally { button.disabled = false; } }

function renderAgencyOptions() { if (!$("newAgency")) return; $("newAgency").innerHTML = `<option value="">Select agency</option>${state.agencies.filter((a) => a.active).map((a) => `<option value="${escapeHTML(a.id)}">${escapeHTML(a.name)}</option>`).join("")}<option value="__new__">+ Add new agency…</option>`; updateAgencyFields(); }
function updateAgencyFields() { const agent = $("newRole").value === "agent", adding = agent && $("newAgency").value === "__new__"; $("agencyField").hidden = !agent; $("newAgency").required = agent; $("newAgencyField").hidden = !adding; $("newAgencyName").required = adding; }
async function openAgencySettings(event) { const agency = state.agencies.find((a) => a.id === event.currentTarget.dataset.agencySettings); $("agencyDialog").dataset.agencyID = agency.id; $("editAgencyName").value = agency.name; $("mcpTokenBox").hidden = true; $("agencyDialog").showModal(); try { updateMCPDialog((await api(`/admin/agencies/${agency.id}/mcp`)).connection); } catch (error) { $("agencyFormError").textContent = error.message; } }
function updateMCPDialog(c) { $("mcpStatus").textContent = c.configured ? `Active${c.rotatedAt ? ` · rotated ${formatDate(c.rotatedAt)}` : ""}` : "Not configured"; $("mcpEndpoint").value = c.endpointURL || ""; $("rotateMCPToken").textContent = c.configured ? "Rotate access token" : "Generate access token"; }

function switchView(view) { if (view === "client-version" && !canMutateAdmin()) view = "cases"; state.view = view; document.querySelectorAll(".tab").forEach((b) => b.classList.toggle("active", b.dataset.view === view)); $("casesView").hidden = view !== "cases"; $("usersView").hidden = view !== "users"; $("agenciesView").hidden = view !== "agencies"; $("clientVersionView").hidden = view !== "client-version"; $("addUserButton").hidden = view !== "users" || !canMutateAdmin(); $("searchInput").value = ""; $("searchInput").disabled = view === "client-version"; $("searchInput").placeholder = view === "users" ? "Search users" : view === "agencies" ? "Search agencies" : view === "client-version" ? "Version settings" : "Search patients or cases"; renderCurrentView(); if (view === "client-version") loadClientVersion(); }
let toastTimer; function toast(message) { clearTimeout(toastTimer); $("toast").textContent = message; $("toast").hidden = false; toastTimer = setTimeout(() => $("toast").hidden = true, 3200); }

// Authentication and global navigation.
function showRequiredPasswordChange() { showLogin(); $("loginError").textContent = ""; $("requiredPasswordError").textContent = ""; if (!$("requiredPasswordDialog").open) $("requiredPasswordDialog").showModal(); }
$("loginForm").onsubmit = async (event) => { event.preventDefault(); const submit = event.currentTarget.querySelector("button[type=submit]"); submit.disabled = true; $("loginError").textContent = ""; try { const result = await api("/auth/login", { method: "POST", body: { username: $("loginUsername").value.trim(), password: $("loginPassword").value } }); state.token = result.token; state.user = result.user; const storage = $("rememberSession").checked ? localStorage : sessionStorage; storage.setItem("cfToken", state.token); $("loginPassword").value = ""; if (state.user.mustChangePassword) return showRequiredPasswordChange(); showApp(); await loadData(); startLiveUpdates(); } catch (error) { $("loginError").textContent = error.message; } finally { submit.disabled = false; } };
$("requiredPasswordForm").onsubmit = async (event) => { event.preventDefault(); const submit = event.currentTarget.querySelector("button[type=submit]"); const currentPassword = $("requiredCurrentPassword").value, newPassword = $("requiredNewPassword").value, confirmation = $("requiredPasswordConfirmation").value; $("requiredPasswordError").textContent = ""; if (!validPermanentPassword(newPassword)) return $("requiredPasswordError").textContent = "Use at least 6 characters with at least one number and one symbol."; if (newPassword !== confirmation) return $("requiredPasswordError").textContent = "The passwords do not match."; submit.disabled = true; try { await api("/auth/change-password", { method: "POST", body: { currentPassword, newPassword } }); event.currentTarget.reset(); $("requiredPasswordDialog").close(); await signOut(true); showLogin("Password changed. Sign in with your new password."); } catch (error) { $("requiredPasswordError").textContent = error.message; } finally { submit.disabled = false; } };
$("requiredPasswordDialog").addEventListener("cancel", (event) => event.preventDefault());
$("requiredPasswordSignOut").onclick = () => signOut(true);
function setAccountMenu(open) { $("accountDropdown").hidden = !open; $("accountMenuButton").setAttribute("aria-expanded", String(open)); }
function setNotificationMenu(open) { $("notificationDropdown").hidden = !open; $("notificationButton").setAttribute("aria-expanded", String(open)); }
$("accountMenuButton").onclick = () => { setNotificationMenu(false); setAccountMenu($("accountDropdown").hidden); };
$("accountMenuButton").onkeydown = (event) => { if (event.key === "ArrowDown") { event.preventDefault(); setAccountMenu(true); $("profileButton").focus(); } };
$("notificationButton").onclick = () => { setAccountMenu(false); setNotificationMenu($("notificationDropdown").hidden); };
$("markAllNotificationsRead").onclick = async () => { await api("/notifications/read", { method: "POST", body: { all: true } }); state.notifications.forEach((item) => { item.readAt ||= new Date().toISOString(); }); state.unreadNotifications = 0; renderNotifications(); };
document.addEventListener("click", (event) => { if (!$("accountMenu").contains(event.target)) setAccountMenu(false); if (!$("notificationMenu").contains(event.target)) setNotificationMenu(false); });
document.addEventListener("keydown", (event) => { if (event.key === "Escape") { if (!$("accountDropdown").hidden) { setAccountMenu(false); $("accountMenuButton").focus(); } if (!$("notificationDropdown").hidden) { setNotificationMenu(false); $("notificationButton").focus(); } } });
$("logoutButton").onclick = () => { setAccountMenu(false); signOut(true); }; $("refreshButton").onclick = () => loadData(); $("searchInput").oninput = renderCurrentView; $("newCaseButton").onclick = openNewCase;
document.querySelectorAll(".tab").forEach((b) => b.onclick = () => switchView(b.dataset.view)); document.querySelectorAll("[data-overview-filter]").forEach((node) => node.onclick = () => { state.filters.caseStatus = node.dataset.overviewFilter === "all" ? "" : node.dataset.overviewFilter; renderFilterChips(); switchView("cases"); });
$("clearCaseFilters").onclick = () => { Object.assign(state.filters, { caseStatus: "", caseAssignment: "", caseAgency: "", caseDoctor: "" }); renderFilterChips(); renderCases(); };
$("clearUserFilters").onclick = () => { Object.assign(state.filters, { userRole: "", userStatus: "", userAgency: "" }); renderFilterChips(); renderUsers(); };
$("closeCaseDialog").onclick = () => $("caseDialog").close(); $("closeNewCase").onclick = $("cancelNewCase").onclick = () => $("newCaseDialog").close(); $("newCaseForm").onsubmit = submitNewCase; $("casePatientName").onblur = checkPatientMatch; $("casePatientName").oninput = () => { state.duplicate = { matches: [], confirmed: false, existingPatientID: null }; $("patientMatchHint").textContent = ""; }; $("casePhotos").onchange = (event) => { state.pendingFiles.push(...event.target.files); renderPendingPhotos(); event.target.value = ""; };
$("closePhotoDialog").onclick = () => $("photoDialog").close(); $("previousPhoto").onclick = () => { state.photoIndex = (state.photoIndex + state.photoItems.length - 1) % state.photoItems.length; renderPhotoViewer(); }; $("nextPhoto").onclick = () => { state.photoIndex = (state.photoIndex + 1) % state.photoItems.length; renderPhotoViewer(); }; $("editPhotoButton").onclick = openEditor;
$("editorClose").onclick = closeEditor; $("markupCanvas").addEventListener("pointerdown", editorPointerDown); $("markupCanvas").addEventListener("pointermove", editorPointerMove); $("markupCanvas").addEventListener("pointerup", editorPointerUp); $("markupCanvas").addEventListener("pointercancel", editorPointerUp); $("editorText").onclick = addEditorText; $("editorUndo").onclick = () => { if (editor.history.length > 1) editor.history.pop(); if (editor.history.length) editor.ctx.putImageData(editor.history.at(-1), 0, 0); }; $("sendEditedPhoto").onclick = sendEditedPhoto;

// Profile.
$("profileButton").onclick = () => { setAccountMenu(false); $("profileDisplayName").value = state.user.displayName || ""; $("profileEmail").value = state.user.email || ""; $("profilePhone").value = state.user.phone || ""; $("profileError").textContent = ""; $("profileDialog").showModal(); }; $("closeProfile").onclick = () => $("profileDialog").close();
$("profileForm").onsubmit = async (event) => { event.preventDefault(); try { state.user = (await api("/auth/profile", { method: "PATCH", body: { displayName: $("profileDisplayName").value.trim(), email: $("profileEmail").value.trim() || null, phone: $("profilePhone").value.trim() || null } })).user; showApp(); toast("Profile updated."); } catch (error) { $("profileError").textContent = error.message; } };
$("changePassword").onclick = async () => { const newPassword = $("newProfilePassword").value; $("profileError").textContent = ""; if (!validPermanentPassword(newPassword)) return $("profileError").textContent = "Use at least 6 characters with at least one number and one symbol."; try { await api("/auth/change-password", { method: "POST", body: { currentPassword: $("currentPassword").value, newPassword } }); $("currentPassword").value = $("newProfilePassword").value = ""; $("profileDialog").close(); await signOut(true); showLogin("Password changed. Sign in with your new password."); } catch (error) { $("profileError").textContent = error.message; } };

// Admin users and agencies.
$("addUserButton").onclick = () => { $("userForm").reset(); renderAgencyOptions(); $("userDialog").showModal(); }; $("closeDialog").onclick = $("cancelUser").onclick = () => $("userDialog").close(); $("newRole").onchange = updateAgencyFields; $("newAgency").onchange = updateAgencyFields;
$("userForm").onsubmit = async (event) => { event.preventDefault(); const submit = event.currentTarget.querySelector("button[type=submit]"); submit.disabled = true; try { let agencyID = $("newRole").value === "agent" ? $("newAgency").value : null; if (agencyID === "__new__") { const result = await api("/admin/agencies", { method: "POST", body: { name: $("newAgencyName").value.trim() } }); agencyID = result.agency.id; } await api("/admin/users", { method: "POST", body: { displayName: $("newDisplayName").value.trim(), username: $("newUsername").value.trim(), role: $("newRole").value, agencyID, password: $("newPassword").value } }); $("userDialog").close(); await loadData(); toast("User created."); } catch (error) { $("userFormError").textContent = error.message; } finally { submit.disabled = false; } };
$("closeAgencyDialog").onclick = $("cancelAgency").onclick = () => $("agencyDialog").close(); $("copyMCPToken").onclick = async () => { await navigator.clipboard.writeText($("mcpToken").textContent); toast("MCP token copied."); };
$("rotateMCPToken").onclick = async () => { const id = $("agencyDialog").dataset.agencyID, agency = state.agencies.find((a) => a.id === id); if (!confirm(agency.mcpConfigured ? "Rotate this token? The current token will stop working immediately." : "Generate an MCP token for this agency?")) return; try { const result = await api(`/admin/agencies/${id}/mcp/rotate`, { method: "POST", body: {} }); updateMCPDialog(result.connection); $("mcpToken").textContent = result.connection.accessToken; $("mcpTokenBox").hidden = false; await loadData({ silent: true }); } catch (error) { $("agencyFormError").textContent = error.message; } };
$("agencyForm").onsubmit = async (event) => { event.preventDefault(); try { await api(`/admin/agencies/${$("agencyDialog").dataset.agencyID}`, { method: "PATCH", body: { name: $("editAgencyName").value.trim() } }); await loadData(); toast("Agency updated."); } catch (error) { $("agencyFormError").textContent = error.message; } };

$("refreshClientVersion").onclick = loadClientVersion;
$("clientVersionForm").onsubmit = async (event) => {
  event.preventDefault();
  const submit = event.currentTarget.querySelector("button[type=submit]");
  submit.disabled = true; $("clientVersionError").textContent = "";
  try {
    state.clientVersionPolicy = (await api("/admin/client-version/ios", {
      method: "PATCH", body: { minimumVersion: $("minimumClientVersion").value.trim() }
    })).policy;
    renderClientVersion(); toast("Minimum iOS version updated.");
  } catch (error) {
    $("clientVersionError").textContent = error.message;
  } finally {
    submit.disabled = false;
  }
};

document.addEventListener("visibilitychange", () => { if (!document.hidden && state.token) loadData({ silent: true }).catch(() => {}); });
window.addEventListener("focus", () => { if (state.token) loadData({ silent: true }).catch(() => {}); });
loadDeploymentInfo();
restore();
