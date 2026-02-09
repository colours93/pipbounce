const API = "http://127.0.0.1:51789";

const els = {
  status: document.getElementById("daemonStatus"),
  toggle: document.getElementById("enableToggle"),
  seg: document.getElementById("cornerZone"),
};

const zoneBtns = els.seg.querySelectorAll("button");

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

async function restartDaemon() {
  try {
    await fetch(`${API}/restart`, { method: "POST" });
  } catch {}
  await new Promise((r) => setTimeout(r, 600));
}

restartDaemon().then(() => {
  triggerPip();
  fetchStatus();
});

document.getElementById("pipBtn").addEventListener("click", triggerPip);

function setActiveZone(value) {
  zoneBtns.forEach((btn) => {
    btn.classList.toggle("active", btn.dataset.value === String(value));
  });
}

function closestZone(px) {
  const zones = [60, 100, 150];
  return zones.reduce((prev, curr) =>
    Math.abs(curr - px) < Math.abs(prev - px) ? curr : prev
  );
}

async function fetchStatus() {
  try {
    const res = await fetch(`${API}/status`);
    const data = await res.json();

    els.status.textContent = data.pipActive ? "PiP active" : "Daemon running";
    els.status.className = "status active";

    els.toggle.checked = data.enabled;
    setActiveZone(closestZone(data.cornerSize));
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

zoneBtns.forEach((btn) => {
  btn.addEventListener("click", () => {
    setActiveZone(btn.dataset.value);
    updateSettings({ cornerSize: Number(btn.dataset.value) });
  });
});

fetchStatus();
setInterval(fetchStatus, 2000);
