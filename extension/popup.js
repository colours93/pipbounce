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

document.getElementById("pongBtn").addEventListener("click", async () => {
  try {
    const res = await fetch(`${API}/pong`, { method: "POST" });
    const data = await res.json();
    document.getElementById("pongBtn").textContent = data.pong ? "Stop Pong" : "Pong Mode";
  } catch {}
});

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
    if (data.hotkeyCode !== undefined) {
      hotkeyBtn.textContent = formatHotkey(data.hotkeyCode, data.hotkeyFlags);
    }
    document.getElementById("pongBtn").textContent = data.pong ? "Stop Pong" : "Pong Mode";
    if (data.glowColor) setActiveColor(data.glowColor);
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

const colorDots = document.querySelectorAll("#colorPicker .color-dot");

colorDots.forEach((dot) => {
  dot.addEventListener("click", () => {
    colorDots.forEach((d) => d.classList.remove("active"));
    dot.classList.add("active");
    updateSettings({ glowColor: dot.dataset.color });
  });
});

function setActiveColor(color) {
  colorDots.forEach((d) => {
    d.classList.toggle("active", d.dataset.color === color);
  });
}

zoneBtns.forEach((btn) => {
  btn.addEventListener("click", () => {
    setActiveZone(btn.dataset.value);
    updateSettings({ cornerSize: Number(btn.dataset.value) });
  });
});

// Hotkey recorder
const hotkeyBtn = document.getElementById("hotkeyBtn");
let recording = false;

const KEY_NAMES = {
  0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",
  11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",
  20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",26:"7",27:"-",28:"8",
  29:"0",30:"]",31:"O",32:"U",33:"[",34:"I",35:"P",37:"L",38:"J",
  39:"'",40:"K",41:";",42:"\\",43:",",44:"/",45:"N",46:"M",47:".",
  49:"Space",50:"`",53:"Esc",
  122:"F1",120:"F2",99:"F3",118:"F4",96:"F5",97:"F6",98:"F7",
  100:"F8",101:"F9",109:"F10",103:"F11",111:"F12",
};

function flagsToSymbols(f) {
  let s = "";
  if (f & 0x100) s += "\u2318";
  if (f & 0x008) s += "\u2325";
  if (f & 0x004) s += "\u2303";
  if (f & 0x002) s += "\u21E7";
  return s;
}

function formatHotkey(code, flags) {
  return flagsToSymbols(flags) + (KEY_NAMES[code] || `key${code}`);
}

hotkeyBtn.addEventListener("click", () => {
  recording = true;
  hotkeyBtn.textContent = "Press keys...";
  hotkeyBtn.classList.add("recording");
});

document.addEventListener("keydown", (e) => {
  if (!recording) return;
  e.preventDefault();
  if (["Shift","Control","Alt","Meta"].includes(e.key)) return;

  let flags = 0;
  if (e.metaKey) flags |= 0x100;
  if (e.altKey) flags |= 0x008;
  if (e.ctrlKey) flags |= 0x004;
  if (e.shiftKey) flags |= 0x002;

  if (flags === 0) return;

  const code = e.keyCode;
  // Map browser keyCode to macOS virtual keycode
  const MAC_CODES = {
    65:0,66:11,67:8,68:2,69:14,70:3,71:5,72:4,73:34,74:38,75:40,
    76:37,77:46,78:45,79:31,80:35,81:12,82:15,83:1,84:17,85:32,
    86:9,87:13,88:7,89:16,90:6,
    48:29,49:18,50:19,51:20,52:21,53:23,54:22,55:26,56:28,57:25,
    32:49,27:53,192:50,189:27,187:24,219:33,221:30,186:41,222:39,
    188:43,190:47,191:44,220:42,
    112:122,113:120,114:99,115:118,116:96,117:97,118:98,119:100,
    120:101,121:109,122:103,123:111,
  };

  const macCode = MAC_CODES[code];
  if (macCode === undefined) return;

  recording = false;
  hotkeyBtn.classList.remove("recording");
  hotkeyBtn.textContent = formatHotkey(macCode, flags);
  updateSettings({ hotkeyCode: macCode, hotkeyFlags: flags });
});

fetchStatus();
setInterval(fetchStatus, 2000);
