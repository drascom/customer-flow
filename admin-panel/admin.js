const API = "/api/v1";
const directAdmin = document.body.dataset.directAdmin === "true";
const state = {
  token: directAdmin ? null : sessionStorage.getItem("cfAdminToken"), user: null, users: [], agencies: [], cases: [], view: "cases",
  filters: {
    caseStatus: "", caseAssignment: "", caseAgency: "", caseDoctor: "",
    userRole: "", userStatus: "", userAgency: ""
  }
};

const $ = (id) => document.getElementById(id);
const escapeHTML = (value) => String(value ?? "").replace(/[&<>'"]/g, (char) => ({"&":"&amp;","<":"&lt;",">":"&gt;","'":"&#39;",'"':"&quot;"}[char]));

async function api(path, options = {}) {
  const headers = { Accept: "application/json", ...(options.headers || {}) };
  if (state.token) headers.Authorization = `Bearer ${state.token}`;
  if (options.body && typeof options.body !== "string") {
    headers["Content-Type"] = "application/json";
    options.body = JSON.stringify(options.body);
  }
  const response = await fetch(`${API}${path}`, { ...options, headers });
  const payload = await response.json().catch(() => ({}));
  if (response.status === 401) {
    if (directAdmin) throw new Error("The dashboard could not establish its admin session.");
    signOut(false);
    throw new Error("Your session expired. Sign in again.");
  }
  if (!response.ok) throw new Error(payload.error?.message || `Request failed (${response.status}).`);
  return payload;
}

function showLogin(message = "") {
  $("loginView").hidden = false;
  $("appView").hidden = true;
  $("loginError").textContent = message;
}

function showApp() {
  $("loginView").hidden = true;
  $("appView").hidden = false;
  $("adminName").textContent = state.user.role === "manager"
    ? `${state.user.displayName} · Read only`
    : state.user.displayName;
  $("logoutButton").hidden = directAdmin;
}

async function signOut(callServer = true) {
  if (directAdmin) return;
  if (callServer && state.token) await api("/auth/logout", { method: "POST", body: {} }).catch(() => {});
  sessionStorage.removeItem("cfAdminToken");
  state.token = null;
  state.user = null;
  showLogin();
}

async function restore() {
  if (directAdmin) {
    state.user = { id: "direct-admin", role: "admin", displayName: "Admin" };
    showApp();
    try {
      await loadData();
    } catch (error) {
      toast(error.message);
    }
    return;
  }
  if (!state.token) return showLogin();
  try {
    const result = await api("/auth/me");
    if (!["admin", "manager"].includes(result.user.role)) throw new Error("This account does not have management access.");
    state.user = result.user;
    showApp();
    await loadData();
  } catch (error) {
    sessionStorage.removeItem("cfAdminToken");
    state.token = null;
    showLogin(error.message);
  }
}

async function loadData() {
  const [userResult, agencyResult, caseResult] = await Promise.all([
    api("/admin/users"), api("/admin/agencies"), api("/admin/cases")
  ]);
  state.users = userResult.users;
  state.agencies = agencyResult.agencies;
  state.cases = caseResult.cases;
  renderAgencyOptions();
  renderFilterChips();
  updateOverview();
  renderCurrentView();
}

function updateOverview() {
  $("activeUsers").textContent = state.users.filter((user) => user.active).length;
  $("patientCount").textContent = new Set(state.cases.map((item) => item.patientID)).size;
  $("waitingCount").textContent = state.cases.filter((item) => item.status === "waiting").length;
  $("answeredCount").textContent = state.cases.filter((item) => item.status === "answered").length;
}

function renderCurrentView() {
  if (state.view === "cases") renderCases();
  else if (state.view === "users") renderUsers();
  else renderAgencies();
}

function setChipGroup(id, items, selected, filterKey) {
  $(id).innerHTML = items.map(([value, label]) =>
    `<button type="button" class="filter-chip ${value === selected ? "active" : ""}" data-filter-key="${escapeHTML(filterKey)}" data-filter-value="${escapeHTML(value)}" aria-pressed="${value === selected}">${escapeHTML(label)}</button>`
  ).join("");
}

function renderFilterChips() {
  const agencies = state.agencies.slice().sort((a, b) => a.name.localeCompare(b.name));
  const doctors = state.users.filter((user) => user.role === "doctor").sort((a, b) => a.displayName.localeCompare(b.displayName));

  setChipGroup("caseStatusChips", [["", "All"], ["waiting", "Waiting"], ["answered", "Answered"], ["closed", "Closed"]], state.filters.caseStatus, "caseStatus");
  setChipGroup("caseAssignmentChips", [["", "All"], ["assigned", "Assigned"], ["unassigned", "Unassigned"]], state.filters.caseAssignment, "caseAssignment");
  setChipGroup("caseAgencyChips", [["", "All"], ...agencies.map((agency) => [agency.name, agency.name])], state.filters.caseAgency, "caseAgency");
  setChipGroup("caseDoctorChips", [["", "All"], ...doctors.map((doctor) => [doctor.id, doctor.displayName])], state.filters.caseDoctor, "caseDoctor");
  setChipGroup("userRoleChips", [["", "All"], ["agent", "Agents"], ["doctor", "Doctors"], ["manager", "Managers"], ["admin", "Admins"]], state.filters.userRole, "userRole");
  setChipGroup("userStatusChips", [["", "All"], ["active", "Active"], ["inactive", "Inactive"]], state.filters.userStatus, "userStatus");
  setChipGroup("userAgencyChips", [["", "All"], ...agencies.map((agency) => [agency.id, agency.name])], state.filters.userAgency, "userAgency");

  document.querySelectorAll("[data-filter-key]").forEach((button) => button.addEventListener("click", () => {
    state.filters[button.dataset.filterKey] = button.dataset.filterValue;
    renderFilterChips();
    renderCurrentView();
  }));
  $("clearCaseFilters").hidden = !["caseStatus", "caseAssignment", "caseAgency", "caseDoctor"].some((key) => state.filters[key]);
  $("clearUserFilters").hidden = !["userRole", "userStatus", "userAgency"].some((key) => state.filters[key]);
}

function renderCases() {
  const query = $("searchInput").value.trim().toLocaleLowerCase();
  const doctors = state.users.filter((user) => user.role === "doctor" && user.active);
  const rows = state.cases.filter((item) => {
    const haystack = `${item.patientName} ${item.patientID} ${item.reference} ${item.agentName} ${item.agencyName || ""} ${item.doctorName || ""}`.toLocaleLowerCase();
    const assignmentMatches = !state.filters.caseAssignment || (state.filters.caseAssignment === "assigned" ? Boolean(item.doctorID) : !item.doctorID);
    return (!query || haystack.includes(query))
      && (!state.filters.caseStatus || item.status === state.filters.caseStatus)
      && assignmentMatches
      && (!state.filters.caseAgency || item.agencyName === state.filters.caseAgency)
      && (!state.filters.caseDoctor || item.doctorID === state.filters.caseDoctor);
  });

  $("casesBody").innerHTML = rows.map((item) => {
    const options = [`<option value="">Unassigned</option>`, ...doctors.map((doctor) =>
      `<option value="${escapeHTML(doctor.id)}" ${doctor.id === item.doctorID ? "selected" : ""}>${escapeHTML(doctor.displayName)}</option>`
    )].join("");
    return `<tr>
      <td><div class="identity"><strong>${escapeHTML(item.patientName)}</strong><small>${escapeHTML(item.reference)}</small></div></td>
      <td>${item.messageCount}</td>
      <td><span class="status ${escapeHTML(item.status)}">${statusTitle(item.status)}</span></td>
      <td><div class="identity"><strong>${escapeHTML(item.agentName)}</strong><small>${escapeHTML(item.agencyName || "No agency")}</small></div></td>
      <td>${state.user.role === "manager"
        ? escapeHTML(item.doctorName || "Unassigned")
        : `<select class="doctor-select" data-patient="${escapeHTML(item.patientID)}" data-previous="${escapeHTML(item.doctorID || "")}">${options}</select>`}</td>
      <td>${item.photoCount}</td>
      <td><div class="identity"><strong>${escapeHTML(item.grafts)}</strong><small>£${escapeHTML(item.price)}</small></div></td>
      <td>${formatDate(item.uploadedAt)}</td>
      <td>${state.user.role === "admin"
        ? `<button class="row-action danger" data-delete-case="${escapeHTML(item.id)}" data-case-reference="${escapeHTML(item.reference)}">Delete</button>`
        : ""}</td>
    </tr>`;
  }).join("");
  $("casesEmpty").hidden = rows.length !== 0;
  document.querySelectorAll(".doctor-select").forEach((select) => select.addEventListener("change", assignDoctor));
  document.querySelectorAll("[data-delete-case]").forEach((button) => button.addEventListener("click", deleteCase));
}

async function deleteCase(event) {
  const button = event.currentTarget;
  const reference = button.dataset.caseReference;
  const confirmation = window.prompt(
    `This permanently deletes the consultation, all messages and every photo. Type ${reference} to continue:`
  ) || "";
  if (confirmation !== reference) return;
  button.disabled = true;
  try {
    await api(`/admin/cases/${encodeURIComponent(button.dataset.deleteCase)}`, { method: "DELETE" });
    state.cases = state.cases.filter((item) => item.id !== button.dataset.deleteCase);
    renderFilterChips();
    updateOverview();
    renderCases();
    toast("Consultation and all related media permanently deleted.");
  } catch (error) {
    button.disabled = false;
    toast(error.message);
  }
}

function renderUsers() {
  const query = $("searchInput").value.trim().toLocaleLowerCase();
  const rows = state.users.filter((user) => {
    const haystack = `${user.displayName} ${user.username} ${user.role} ${user.agencyName || ""}`.toLocaleLowerCase();
    const statusMatches = !state.filters.userStatus || (state.filters.userStatus === "active" ? user.active : !user.active);
    return haystack.includes(query)
      && (!state.filters.userRole || user.role === state.filters.userRole)
      && statusMatches
      && (!state.filters.userAgency || user.agencyID === state.filters.userAgency);
  });
  $("usersBody").innerHTML = rows.map((user) => {
    const activity = user.role === "doctor" ? `${user.patientCount} patients` : user.role === "agent" ? `${user.caseCount} cases` : "System access";
    const action = state.user.role === "manager" || user.id === state.user.id ? "" : `<div class="row-actions">
      <button class="row-action ${user.active ? "danger" : ""}" data-user="${escapeHTML(user.id)}" data-active="${user.active}">${user.active ? "Deactivate" : "Reactivate"}</button>
      ${user.active ? "" : `<button class="row-action danger" data-delete-user="${escapeHTML(user.id)}" data-username="${escapeHTML(user.username)}">Delete</button>`}
    </div>`;
    return `<tr>
      <td><div class="identity"><strong>${escapeHTML(user.displayName)}</strong><small>${escapeHTML(user.id)}</small></div></td>
      <td>${escapeHTML(user.username)}</td>
      <td><span class="role">${escapeHTML(user.role)}</span></td>
      <td>${escapeHTML(user.agencyName || "—")}</td>
      <td>${activity}</td>
      <td><span class="${user.active ? "active-dot" : "inactive-dot"}">${user.active ? "Active" : "Inactive"}</span></td>
      <td>${action}</td>
    </tr>`;
  }).join("");
  $("usersEmpty").hidden = rows.length !== 0;
  document.querySelectorAll("[data-user]").forEach((button) => button.addEventListener("click", toggleUser));
  document.querySelectorAll("[data-delete-user]").forEach((button) => button.addEventListener("click", deleteUser));
}

function renderAgencies() {
  const query = $("searchInput").value.trim().toLocaleLowerCase();
  const rows = state.agencies.filter((agency) => agency.name.toLocaleLowerCase().includes(query));
  $("agenciesBody").innerHTML = rows.map((agency) => `<tr>
    <td><div class="identity"><strong>${escapeHTML(agency.name)}</strong><small>${agency.active ? "Active" : "Inactive"}</small></div></td>
    <td>${agency.userCount}</td>
    <td><span class="${agency.mcpConfigured ? "active-dot" : "inactive-dot"}">${agency.mcpConfigured ? "Connected" : "Not configured"}</span></td>
    <td>${agency.mcpRotatedAt ? formatDate(agency.mcpRotatedAt) : "—"}</td>
    <td>${state.user.role === "admin" ? `<button class="row-action" data-agency-settings="${escapeHTML(agency.id)}">Manage</button>` : ""}</td>
  </tr>`).join("");
  $("agenciesEmpty").hidden = rows.length !== 0;
  document.querySelectorAll("[data-agency-settings]").forEach((button) => button.addEventListener("click", openAgencySettings));
}

async function openAgencySettings(event) {
  const agency = state.agencies.find((item) => item.id === event.currentTarget.dataset.agencySettings);
  if (!agency) return;
  $("agencyDialog").dataset.agencyID = agency.id;
  $("editAgencyName").value = agency.name;
  $("mcpStatus").textContent = "Loading…";
  $("mcpEndpoint").value = "";
  $("mcpTokenBox").hidden = true;
  $("agencyFormError").textContent = "";
  $("agencyDialog").showModal();
  try {
    const result = await api(`/admin/agencies/${encodeURIComponent(agency.id)}/mcp`);
    updateMCPDialog(result.connection);
  } catch (error) {
    $("agencyFormError").textContent = error.message;
  }
}

function updateMCPDialog(connection) {
  $("mcpStatus").textContent = connection.configured
    ? `Active${connection.rotatedAt ? ` · rotated ${formatDate(connection.rotatedAt)}` : ""}`
    : "Not configured";
  $("mcpEndpoint").value = connection.endpointURL || "";
  $("rotateMCPToken").textContent = connection.configured ? "Rotate access token" : "Generate access token";
}

async function assignDoctor(event) {
  const select = event.currentTarget;
  const previous = select.dataset.previous;
  const doctorID = select.value || null;
  let reason = "";
  if (previous && previous !== (doctorID || "")) {
    reason = window.prompt("Reason for changing the assigned doctor:", "Administrative reassignment") || "";
    if (!reason.trim()) {
      select.value = previous;
      return;
    }
  }
  select.disabled = true;
  try {
    await api(`/admin/patients/${encodeURIComponent(select.dataset.patient)}`, {
      method: "PATCH", body: { doctorID, reason }
    });
    state.cases.filter((item) => item.patientID === select.dataset.patient).forEach((item) => {
      item.doctorID = doctorID;
      item.doctorName = state.users.find((user) => user.id === doctorID)?.displayName || null;
    });
    toast("Doctor assignment updated.");
    renderCases();
  } catch (error) {
    select.value = previous;
    toast(error.message);
  } finally {
    select.disabled = false;
  }
}

async function toggleUser(event) {
  const button = event.currentTarget;
  const currentlyActive = button.dataset.active === "true";
  if (currentlyActive && !window.confirm("Deactivate this user? Their active sessions will be ended.")) return;
  button.disabled = true;
  try {
    await api(`/admin/users/${encodeURIComponent(button.dataset.user)}`, {
      method: "PATCH", body: { active: !currentlyActive }
    });
    const user = state.users.find((item) => item.id === button.dataset.user);
    if (user) user.active = !currentlyActive;
    renderFilterChips();
    updateOverview();
    renderUsers();
    toast(currentlyActive ? "User deactivated." : "User reactivated.");
  } catch (error) {
    button.disabled = false;
    toast(error.message);
  }
}

async function deleteUser(event) {
  const button = event.currentTarget;
  const username = button.dataset.username;
  const confirmation = window.prompt(`Type ${username} to permanently delete this unused account:`) || "";
  if (confirmation !== username) return;
  button.disabled = true;
  try {
    await api(`/admin/users/${encodeURIComponent(button.dataset.deleteUser)}`, { method: "DELETE" });
    state.users = state.users.filter((user) => user.id !== button.dataset.deleteUser);
    renderFilterChips();
    updateOverview();
    renderUsers();
    toast("User permanently deleted.");
  } catch (error) {
    button.disabled = false;
    toast(error.message);
  }
}

function renderAgencyOptions(selectedID = "") {
  const active = state.agencies.filter((agency) => agency.active);
  $("newAgency").innerHTML = [
    `<option value="">Select agency</option>`,
    ...active.map((agency) => `<option value="${escapeHTML(agency.id)}" ${agency.id === selectedID ? "selected" : ""}>${escapeHTML(agency.name)}</option>`),
    `<option value="__new__">+ Add new agency…</option>`
  ].join("");
  updateAgencyFields();
}

function updateAgencyFields() {
  const isAgent = $("newRole").value === "agent";
  $("agencyField").hidden = !isAgent;
  $("newAgency").required = isAgent;
  const addingAgency = isAgent && $("newAgency").value === "__new__";
  $("newAgencyField").hidden = !addingAgency;
  $("newAgencyName").required = addingAgency;
  if (!addingAgency) $("newAgencyName").value = "";
}

function switchView(view) {
  state.view = view;
  document.querySelectorAll(".tab").forEach((button) => button.classList.toggle("active", button.dataset.view === view));
  $("casesView").hidden = view !== "cases";
  $("usersView").hidden = view !== "users";
  $("agenciesView").hidden = view !== "agencies";
  $("addUserButton").hidden = view !== "users" || state.user.role === "manager";
  $("searchInput").placeholder = view === "users" ? "Search users" : view === "agencies" ? "Search agencies" : "Search patients or cases";
  $("searchInput").value = "";
  renderCurrentView();
}

function statusTitle(status) {
  return ({ waiting: "Waiting", answered: "Answered", closed: "Confirmed" })[status] || status;
}

function formatDate(value) {
  return new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" }).format(new Date(value));
}

let toastTimer;
function toast(message) {
  clearTimeout(toastTimer);
  $("toast").textContent = message;
  $("toast").hidden = false;
  toastTimer = setTimeout(() => { $("toast").hidden = true; }, 3200);
}

$("loginForm").addEventListener("submit", async (event) => {
  event.preventDefault();
  $("loginError").textContent = "";
  const submit = event.currentTarget.querySelector("button[type=submit]");
  submit.disabled = true;
  try {
    const result = await api("/auth/login", { method: "POST", body: {
      username: $("loginUsername").value.trim(), password: $("loginPassword").value
    }});
    if (!["admin", "manager"].includes(result.user.role)) {
      state.token = result.token;
      await api("/auth/logout", { method: "POST", body: {} }).catch(() => {});
      state.token = null;
      throw new Error("This account does not have management access.");
    }
    state.token = result.token;
    state.user = result.user;
    sessionStorage.setItem("cfAdminToken", state.token);
    $("loginPassword").value = "";
    showApp();
    await loadData();
  } catch (error) {
    $("loginError").textContent = error.message;
  } finally {
    submit.disabled = false;
  }
});

$("logoutButton").addEventListener("click", () => signOut(true));
document.querySelectorAll(".tab").forEach((button) => button.addEventListener("click", () => switchView(button.dataset.view)));
$("searchInput").addEventListener("input", renderCurrentView);
$("clearCaseFilters").addEventListener("click", () => {
  Object.assign(state.filters, { caseStatus: "", caseAssignment: "", caseAgency: "", caseDoctor: "" });
  renderFilterChips();
  renderCases();
});
$("clearUserFilters").addEventListener("click", () => {
  Object.assign(state.filters, { userRole: "", userStatus: "", userAgency: "" });
  renderFilterChips();
  renderUsers();
});
$("addUserButton").addEventListener("click", () => {
  renderAgencyOptions();
  $("userDialog").showModal();
});
$("closeDialog").addEventListener("click", () => $("userDialog").close());
$("cancelUser").addEventListener("click", () => $("userDialog").close());
$("newRole").addEventListener("change", updateAgencyFields);
$("newAgency").addEventListener("change", updateAgencyFields);
$("closeAgencyDialog").addEventListener("click", () => $("agencyDialog").close());
$("cancelAgency").addEventListener("click", () => $("agencyDialog").close());
$("copyMCPToken").addEventListener("click", async () => {
  await navigator.clipboard.writeText($("mcpToken").textContent);
  toast("MCP token copied.");
});
$("rotateMCPToken").addEventListener("click", async () => {
  const agencyID = $("agencyDialog").dataset.agencyID;
  const agency = state.agencies.find((item) => item.id === agencyID);
  if (!agency) return;
  const warning = agency.mcpConfigured
    ? "Rotate this token? The current token will stop working immediately."
    : "Generate an MCP token for this agency?";
  if (!window.confirm(warning)) return;
  $("rotateMCPToken").disabled = true;
  try {
    const result = await api(`/admin/agencies/${encodeURIComponent(agencyID)}/mcp/rotate`, { method: "POST", body: {} });
    updateMCPDialog(result.connection);
    $("mcpToken").textContent = result.connection.accessToken;
    $("mcpTokenBox").hidden = false;
    agency.mcpConfigured = true;
    agency.mcpRotatedAt = result.connection.rotatedAt;
    renderAgencies();
  } catch (error) {
    $("agencyFormError").textContent = error.message;
  } finally {
    $("rotateMCPToken").disabled = false;
  }
});
$("agencyForm").addEventListener("submit", async (event) => {
  event.preventDefault();
  const agencyID = $("agencyDialog").dataset.agencyID;
  const agency = state.agencies.find((item) => item.id === agencyID);
  if (!agency) return;
  try {
    const result = await api(`/admin/agencies/${encodeURIComponent(agencyID)}`, {
      method: "PATCH", body: { name: $("editAgencyName").value.trim() }
    });
    Object.assign(agency, result.agency);
    renderAgencyOptions();
    renderFilterChips();
    renderAgencies();
    toast("Agency updated.");
  } catch (error) {
    $("agencyFormError").textContent = error.message;
  }
});
$("userForm").addEventListener("submit", async (event) => {
  event.preventDefault();
  $("userFormError").textContent = "";
  const submit = event.currentTarget.querySelector("button[type=submit]");
  submit.disabled = true;
  try {
    const role = $("newRole").value;
    let agencyID = role === "agent" ? $("newAgency").value : null;
    if (agencyID === "__new__") {
      const agencyResult = await api("/admin/agencies", {
        method: "POST", body: { name: $("newAgencyName").value.trim() }
      });
      state.agencies.push(agencyResult.agency);
      agencyID = agencyResult.agency.id;
    }
    const result = await api("/admin/users", { method: "POST", body: {
      displayName: $("newDisplayName").value.trim(), username: $("newUsername").value.trim(),
      role, agencyID, password: $("newPassword").value
    }});
    state.users.push(result.user);
    renderFilterChips();
    event.currentTarget.reset();
    renderAgencyOptions();
    $("userDialog").close();
    updateOverview();
    renderUsers();
    toast("User created.");
  } catch (error) {
    $("userFormError").textContent = error.message;
  } finally {
    submit.disabled = false;
  }
});

restore();
