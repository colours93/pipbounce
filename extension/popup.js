const API = "http://127.0.0.1:51789";

const els = {
  status: document.getElementById("daemonStatus"),
  toggle: document.getElementById("enableToggle"),
  distance: document.getElementById("dodgeDistance"),
  distanceVal: document.getElementById("distanceValue"),
  cooldown: document.getElementById("cooldown"),
  cooldownVal: document.getElementById("cooldownValue"),
  margin: document.getElementById("margin"),
  marginVal: document.getElementById("marginValue"),
  cornerSize: document.getElementById("cornerSize"),
  cornerSizeVal: document.getElementById("cornerSizeValue"),
  pip: document.getElementById("pipStatus"),
};

// Trigger PiP directly from popup
async function triggerPip() {
  try {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (tab) {
      await chrome.scripting.executeScript({
        target: { tabId: tab.id, allFrames: true },
        files: ["content.js"],
      });
    }
  } catch (e) {
    console.error("PiP trigger failed:", e);
  }
}

// Auto-trigger PiP when popup opens
triggerPip();

// Button as manual toggle too
document.getElementById("pipBtn").addEventListener("click", triggerPip);

async function fetchStatus() {
  try {
    const res = await fetch(`${API}/status`);
    const data = await res.json();

    els.status.textContent = "Daemon running";
    els.status.className = "status active";

    els.toggle.checked = data.enabled;
    els.distance.value = data.dodgeDistance;
    els.distanceVal.textContent = data.dodgeDistance + "px";
    els.cooldown.value = data.cooldown;
    els.cooldownVal.textContent = data.cooldown + "s";
    els.margin.value = data.margin;
    els.marginVal.textContent = data.margin + "px";
    els.cornerSize.value = data.cornerSize;
    els.cornerSizeVal.textContent = data.cornerSize + "px";

    if (data.pipActive) {
      els.pip.textContent = "PiP window detected";
      els.pip.className = "pip-status has-pip";
    } else {
      els.pip.textContent = "No PiP window detected";
      els.pip.className = "pip-status";
    }
  } catch {
    els.status.textContent = "Daemon not running — start ~/.pipdodge/pipdodge";
    els.status.className = "status error";
  }
}

async function updateSettings(changes) {
  try {
    await fetch(`${API}/settings`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(changes),
    });
  } catch {}
}

els.toggle.addEventListener("change", () => {
  updateSettings({ enabled: els.toggle.checked });
});

els.distance.addEventListener("input", () => {
  els.distanceVal.textContent = els.distance.value + "px";
  updateSettings({ dodgeDistance: Number(els.distance.value) });
});

els.cooldown.addEventListener("input", () => {
  els.cooldownVal.textContent = els.cooldown.value + "s";
  updateSettings({ cooldown: Number(els.cooldown.value) });
});

els.margin.addEventListener("input", () => {
  els.marginVal.textContent = els.margin.value + "px";
  updateSettings({ margin: Number(els.margin.value) });
});

els.cornerSize.addEventListener("input", () => {
  els.cornerSizeVal.textContent = els.cornerSize.value + "px";
  updateSettings({ cornerSize: Number(els.cornerSize.value) });
});

fetchStatus();
setInterval(fetchStatus, 2000);
