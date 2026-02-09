const API = "http://127.0.0.1:51789";

const els = {
  status: document.getElementById("daemonStatus"),
  statusLabel: document.querySelector("#daemonStatus .label"),
  toggle: document.getElementById("enableToggle"),
  glow: document.getElementById("glowToggle"),
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

els.status.addEventListener("click", async () => {
  if (els.status.classList.contains("offline")) {
    els.statusLabel.textContent = "Restarting...";
    await restartDaemon();
    fetchStatus();
  }
});

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

    els.statusLabel.textContent = data.pipActive ? "PiP active" : "Online";
    els.status.className = "status online";

    els.toggle.checked = data.enabled;
    els.glow.checked = data.glow;
    setActiveZone(closestZone(data.cornerSize));
  } catch {
    els.statusLabel.textContent = "Offline — click to restart";
    els.status.className = "status offline";
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

els.glow.addEventListener("change", () => {
  updateSettings({ glow: els.glow.checked });
});

zoneBtns.forEach((btn) => {
  btn.addEventListener("click", () => {
    setActiveZone(btn.dataset.value);
    updateSettings({ cornerSize: Number(btn.dataset.value) });
  });
});

fetchStatus();
setInterval(fetchStatus, 2000);
