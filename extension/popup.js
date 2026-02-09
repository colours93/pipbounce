const API = "http://127.0.0.1:51789";

const els = {
  status: document.getElementById("daemonStatus"),
  toggle: document.getElementById("enableToggle"),
  cornerSize: document.getElementById("cornerSize"),
  cornerSizeVal: document.getElementById("cornerSizeValue"),
};

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

triggerPip();
document.getElementById("pipBtn").addEventListener("click", triggerPip);

async function fetchStatus() {
  try {
    const res = await fetch(`${API}/status`);
    const data = await res.json();

    els.status.textContent = data.pipActive ? "PiP active" : "Daemon running";
    els.status.className = "status active";

    els.toggle.checked = data.enabled;
    els.cornerSize.value = data.cornerSize;
    els.cornerSizeVal.textContent = data.cornerSize + "px";
  } catch {
    els.status.textContent = "Daemon not running — start ~/.xpip/xpip";
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

els.cornerSize.addEventListener("input", () => {
  els.cornerSizeVal.textContent = els.cornerSize.value + "px";
  updateSettings({ cornerSize: Number(els.cornerSize.value) });
});

fetchStatus();
setInterval(fetchStatus, 2000);
