const API = "/api/v1";
const state = {
  token: sessionStorage.getItem("cfAdminToken"), user: null, users: [], agencies: [], cases: [], view: "cases",
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
  $("adminName").textContent = state.user.displayName;
}

async function signOut(callServer = true) {
  if (callServer && state.token) await api("/auth/logout", { method: "POST", body: {} }).catch(() => {});
  sessionStorage.removeItem("cfAdminToken");
  state.token = null;
  state.user = null;
  showLogin();
}

async function restore() {
  if (!state.token) return showLogin();
  try {
    const result = await api("/auth/me");
    if (result.user.role !== "admin") throw new Error("This account does not have admin access.");
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
  if (state.view === "cases") renderCases(); else renderUsers();
}

function setDropdownFilterGroup(id, items, selected, filterKey, label) {
  const choices = items.filter(([value]) => value);
  const placeholder = choices.length ? `Select ${label.toLocaleLowerCase()}` : `No ${label.toLocaleLowerCase()} options`;
  const options = choices.map(([value, optionLabel]) =>
    `<option value="${escapeHTML(value)}" ${value === selected ? "selected" : ""}>${escapeHTML(optionLabel)}</option>`
  ).join("");

  $(id).innerHTML = `
    <select class="filter-select ${selected ? "active" : ""}" data-filter-key="${escapeHTML(filterKey)}" aria-label="${escapeHTML(label)} filter" ${choices.length ? "" : "disabled"}>
      <option value="" ${selected ? "" : "selected"}>${escapeHTML(placeholder)}</option>
      ${options}
    </select>`;
}

function updateAllFilterButton(id, keys) {
  const active = !keys.some((key) => state.filters[key]);
  $(id).classList.toggle("active", active);
  $(id).setAttribute("aria-pressed", String(active));
}

function renderFilterChips() {
  const agencies = state.agencies.slice().sort((a, b) => a.name.localeCompare(b.name));
  const doctors = state.users.filter((user) => user.role === "doctor").sort((a, b) => a.displayName.localeCompare(b.displayName));

  setDropdownFilterGroup("caseStatusChips", [["waiting", "Waiting"], ["answered", "Answered"], ["closed", "Closed"]], state.filters.caseStatus, "caseStatus", "Status");
  setDropdownFilterGroup("caseAssignmentChips", [["assigned", "Assigned"], ["unassigned", "Unassigned"]], state.filters.caseAssignment, "caseAssignment", "Assignment");
  setDropdownFilterGroup("caseAgencyChips", agencies.map((agency) => [agency.name, agency.name]), state.filters.caseAgency, "caseAgency", "Agency");
  setDropdownFilterGroup("caseDoctorChips", doctors.map((doctor) => [doctor.id, doctor.displayName]), state.filters.caseDoctor, "caseDoctor", "Doctor");
  setDropdownFilterGroup("userRoleChips", [["agent", "Agents"], ["doctor", "Doctors"], ["admin", "Admins"]], state.filters.userRole, "userRole", "Role");
  setDropdownFilterGroup("userStatusChips", [["active", "Active"], ["inactive", "Inactive"]], state.filters.userStatus, "userStatus", "Access");
  setDropdownFilterGroup("userAgencyChips", agencies.map((agency) => [agency.id, agency.name]), state.filters.userAgency, "userAgency", "Agency");

  document.querySelectorAll(".filter-select[data-filter-key]").forEach((select) => select.addEventListener("change", () => {
    state.filters[select.dataset.filterKey] = select.value;
    renderFilterChips();
    renderCurrentView();
  }));
  updateAllFilterButton("allCaseFilters", ["caseStatus", "caseAssignment", "caseAgency", "caseDoctor"]);
  updateAllFilterButton("allUserFilters", ["userRole", "userStatus", "userAgency"]);
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
      <td><div class="identity"><strong>${escapeHTML(item.patientName)}</strong><small>${escapeHTML(item.patientID)}</small></div></td>
      <td><div class="identity"><strong>${escapeHTML(item.reference)}</strong><small>${item.messageCount} messages</small></div></td>
      <td><span class="status ${escapeHTML(item.status)}">${statusTitle(item.status)}</span></td>
      <td><div class="identity"><strong>${escapeHTML(item.agentName)}</strong><small>${escapeHTML(item.agencyName || "No agency")}</small></div></td>
      <td><select class="doctor-select" data-patient="${escapeHTML(item.patientID)}" data-previous="${escapeHTML(item.doctorID || "")}">${options}</select></td>
      <td>${item.photoCount}</td>
      <td><div class="identity"><strong>${escapeHTML(item.grafts)}</strong><small>${escapeHTML(item.currency)} ${escapeHTML(item.price)}</small></div></td>
      <td>${formatDate(item.uploadedAt)}</td>
    </tr>`;
  }).join("");
  $("casesEmpty").hidden = rows.length !== 0;
  document.querySelectorAll(".doctor-select").forEach((select) => select.addEventListener("change", assignDoctor));
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
    const action = user.id === state.user.id ? "" : `<div class="row-actions">
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
  $("addUserButton").hidden = view !== "users";
  $("searchInput").placeholder = view === "users" ? "Search users" : "Search patients or cases";
  $("searchInput").value = "";
  renderCurrentView();
}

function statusTitle(status) {
  return ({ waiting: "Waiting", answered: "Answered", closed: "Closed" })[status] || status;
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
    if (result.user.role !== "admin") {
      state.token = result.token;
      await api("/auth/logout", { method: "POST", body: {} }).catch(() => {});
      state.token = null;
      throw new Error("This account does not have admin access.");
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
$("allCaseFilters").addEventListener("click", () => {
  Object.assign(state.filters, { caseStatus: "", caseAssignment: "", caseAgency: "", caseDoctor: "" });
  renderFilterChips();
  renderCases();
});
$("allUserFilters").addEventListener("click", () => {
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
