chrome.commands.onCommand.addListener(async (command) => {
  if (command !== "toggle-pip") return;
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab) return;
  await chrome.scripting.executeScript({
    target: { tabId: tab.id, allFrames: true },
    files: ["content.js"],
  });
});
