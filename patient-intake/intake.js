(() => {
  const formKey = document.body.dataset.formKey;
  const form = document.getElementById("intakeForm");
  const submitButton = document.getElementById("submitButton");
  const errorNode = document.getElementById("formError");
  const photoInput = document.getElementById("photos");
  const photoList = document.getElementById("photoList");

  const resizeParent = () => {
    if (window.parent !== window) {
      window.parent.postMessage({ type: "customer-flow:resize", height: document.documentElement.scrollHeight }, "*");
    }
  };

  const requestJSON = async (url, options = {}) => {
    const response = await fetch(url, options);
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(payload.error?.message || "The application could not be sent.");
    return payload;
  };

  const loadForm = async () => {
    try {
      const { form: configuration } = await requestJSON(`/api/v1/public/forms/${encodeURIComponent(formKey)}`);
      document.getElementById("agencyName").textContent = configuration.agencyName;
      document.getElementById("formTitle").textContent = configuration.label;
      if (configuration.doctorName) {
        document.getElementById("formIntro").textContent = `Share your details and photos securely with ${configuration.doctorName}, the clinic and ${configuration.agencyName}.`;
      }
      resizeParent();
    } catch (error) {
      form.hidden = true;
      errorNode.textContent = error.message;
    }
  };

  const renderPhotos = () => {
    const files = [...photoInput.files];
    photoList.innerHTML = files.map((file) =>
      `<div class="photo-item"><strong></strong><span>${(file.size / 1024 / 1024).toFixed(1)} MB</span></div>`
    ).join("");
    [...photoList.querySelectorAll("strong")].forEach((node, index) => { node.textContent = files[index].name; });
    resizeParent();
  };

  photoInput.addEventListener("change", renderPhotos);
  new ResizeObserver(resizeParent).observe(document.body);

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    errorNode.textContent = "";
    const files = [...photoInput.files];
    const email = document.getElementById("email").value.trim();
    const phone = document.getElementById("phone").value.trim();
    if (!email && !phone) {
      errorNode.textContent = "Enter an email address or phone number.";
      return;
    }
    if (!files.length) {
      errorNode.textContent = "Add at least one photo.";
      return;
    }
    if (files.length > 12 || files.some((file) => file.size > 20 * 1024 * 1024)) {
      errorNode.textContent = "Choose up to 12 photos, no larger than 20 MB each.";
      return;
    }

    submitButton.disabled = true;
    submitButton.textContent = "Sending details…";
    try {
      const payload = await requestJSON(`/api/v1/public/forms/${encodeURIComponent(formKey)}/submissions`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          patientName: document.getElementById("patientName").value,
          email,
          phone,
          note: document.getElementById("note").value,
          consentAccepted: document.getElementById("consent").checked,
        }),
      });
      const submission = payload.submission;
      for (let index = 0; index < files.length; index += 1) {
        submitButton.textContent = `Uploading photo ${index + 1} of ${files.length}…`;
        const response = await fetch(`/api/v1/public/submissions/${submission.caseID}/photos`, {
          method: "POST",
          headers: { "Authorization": `Bearer ${submission.uploadToken}`, "Content-Type": files[index].type || "application/octet-stream" },
          body: files[index],
        });
        if (!response.ok) {
          const detail = await response.json().catch(() => ({}));
          throw new Error(detail.error?.message || `Photo ${index + 1} could not be uploaded.`);
        }
      }
      form.hidden = true;
      document.getElementById("reference").textContent = submission.reference;
      document.getElementById("portalInvitation").hidden = !submission.patientPortalInvitationSent;
      const success = document.getElementById("successView");
      success.hidden = false;
      success.focus();
      resizeParent();
    } catch (error) {
      errorNode.textContent = error.message;
      submitButton.disabled = false;
      submitButton.textContent = "Send application";
      resizeParent();
    }
  });

  loadForm();
})();
