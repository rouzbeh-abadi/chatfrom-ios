// A stand-in for ChatFrom's chat page, for the UI tests: it speaks the page's side
// of the bridge (libs/app-bridge.ts in the app) and writes what it hears on the
// page, where a test can read it. It tests the SDK, not the page.
//
//   node Example/TestServer/server.mjs [port]
//
// The chatbot's id picks what it does: live-bot, closed-bot, left-bot (a pill on
// the left), second-bot (another chatbot), flaky-bot (small, for /fail), broken-bot
// (always a 500), mute-bot (never says it is ready), failing-bot (loads, then says
// chatfrom:failed), slow-ready-bot (takes 5 seconds to say it is ready, and from the
// second load on takes 8 to arrive), link-bot (clicks a link by itself, with no tap).
//
// A test can also ask, by id: /reset (forget this chatbot's loads and reports),
// /fail?on=1 (answer 500 until told otherwise), /loads and /reports (how many times
// it loaded, and all it said, across documents).

import { execSync } from "node:child_process";
import { createServer } from "node:http";

const port = Number(process.argv[2] ?? 4599);
const loads = new Map();
const failing = new Set();
const reports = new Map();

const looks = {
  "live-bot": { accent: "#570DF8", position: "right", icon: "chat", label: "", bubble_size: "medium", display_name: "Lumen Ceramics" },
  "left-bot": { accent: "#FACC15", position: "left", icon: "mail", label: "Ask us", bubble_size: "large", display_name: "Bright Help" },
  "second-bot": { accent: "#0F766E", position: "right", icon: "help", label: "", bubble_size: "medium", display_name: "Second Chatbot" },
  "flaky-bot": { accent: "#2563EB", position: "right", icon: "help", label: "", bubble_size: "small", display_name: "Second Try" },
  "mute-bot": { accent: "#0F766E", position: "right", icon: "chat", label: "", bubble_size: "medium", display_name: "Never Ready" },
  "failing-bot": { accent: "#B91C1C", position: "right", icon: "chat", label: "", bubble_size: "medium", display_name: "Says It Failed" },
  "slow-ready-bot": { accent: "#7C3AED", position: "right", icon: "chat", label: "", bubble_size: "medium", display_name: "Slow To Say" },
  "link-bot": { accent: "#BE185D", position: "right", icon: "chat", label: "", bubble_size: "medium", display_name: "Clicks By Itself" },
};

const page = (id, count) => {
  const look = looks[id];
  const config = look ? { id, live: true, remember: true, ...look } : { id, live: false };
  const ready = id === "mute-bot" ? "" : id === "failing-bot" ? 'tell({ type: "chatfrom:failed" });' : id === "slow-ready-bot" && count === 1 ? 'setTimeout(() => { say("said ready"); tell({ type: "chatfrom:ready" }); }, 5000);' : 'tell({ type: "chatfrom:ready" });';
  return `<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  html, body { margin: 0; height: 100%; font: 16px -apple-system, sans-serif; color: #0F172A; background: #fff; }
  main { position: fixed; inset: 0; display: flex; flex-direction: column; }
  #log { flex: 1; overflow-y: auto; padding: 12px 16px; }
  #log p { margin: 0 0 6px; font-size: 13px; }
  nav { display: flex; flex-wrap: wrap; gap: 8px; padding: 8px 12px; }
  button, a { font-size: 14px; }
  form { display: flex; gap: 8px; padding: 8px 12px 12px; border-top: 1px solid #E2E8F0; }
  input[type=text] { flex: 1; font-size: 16px; padding: 8px 10px; border: 1px solid #CBD5E1; border-radius: 8px; }
</style></head>
<body><main>
  <div id="log" aria-label="log"></div>
  <nav>
    <button id="talk" type="button">Talk</button>
    <button id="mark" type="button">Show the mark</button>
    <button id="bought" type="button">Show the purchases</button>
    <a id="outside" href="https://example.com/" target="_blank" rel="noreferrer">Outside</a>
    <a id="home" href="/">Home</a>
    <input id="file" type="file" aria-label="Attach">
  </nav>
  <form onsubmit="return false"><input id="box" type="text" placeholder="Ask a question" aria-label="Message"></form>
</main>
<script>
  const say = (text) => {
    const p = document.createElement("p");
    p.textContent = text;
    document.getElementById("log").append(p);
    navigator.sendBeacon("/report?id=${id}", "load ${count}: " + text);
  };
  const tell = (message) => window.webkit?.messageHandlers?.chatfrom?.postMessage({ ...message, bridge: 1 });
  const who = () => { const a = window.ChatFromApp; return "key=" + (a?.userKey ? a.userKey.slice(0, 6) : "none") + " token=" + (a?.userToken ?? "none"); };
  const bought = () => { const a = window.ChatFromApp; return "rc=" + (a?.revenueCatId ?? "none") + " store=" + (Array.isArray(a?.appStore) ? a.appStore.length : 0); };
  const stored = () => localStorage.getItem("mark") ?? "empty";
  say("loaded " + who() + " mark=" + stored());
  say("purchases " + bought());
  say("path " + location.pathname);
  say("load number ${count}");
  localStorage.setItem("mark", "kept-" + Date.now());
  addEventListener("chatfrom:new-chat", () => { say("heard new-chat"); tell({ type: "chatfrom:talking", on: false }); });
  addEventListener("chatfrom:token", () => { say("heard token " + who()); say("purchases " + bought()); });
  addEventListener("chatfrom:sign-out", () => { say("heard sign-out mark=" + stored()); window.ChatFromApp = {}; localStorage.setItem("mark", "new-visitor"); tell({ type: "chatfrom:talking", on: false }); });
  document.getElementById("talk").onclick = () => { say("talking"); tell({ type: "chatfrom:talking", on: true }); };
  document.getElementById("mark").onclick = () => say("mark now " + stored());
  document.getElementById("bought").onclick = () => say("purchases now " + bought());
  // Written every 5 seconds with the time, so a test can tell the page kept running while the chat was closed.
  let ticks = 0;
  setInterval(() => { ticks++; if (ticks % 5 === 0 && ticks <= 60) say("tick " + ticks + " at " + Date.now()); }, 1000);
  ${id === "link-bot" ? 'setTimeout(() => { say("clicking the link"); document.getElementById("home").click(); }, 3000);' : ""}
  tell({ type: "chatfrom:config", config: ${JSON.stringify(config)} });
  ${ready}
</script>
</body></html>`;
};

// Ends the web view's process in one simulator, as iOS does to a page in the background, and nothing on this Mac or in another simulator.
function endPageProcess(udid) {
  if (!/^[0-9A-F-]{36}$/.test(udid)) return 0;
  const lines = execSync("ps -axo pid=,command=", { encoding: "utf8", maxBuffer: 1 << 24 }).split("\n");
  let ended = 0;
  for (const line of lines) {
    if (!line.includes("com.apple.WebKit.WebContent") || !line.includes(".simruntime")) continue;
    const pid = Number(line.trim().split(/\s+/)[0]);
    const env = execSync(`ps eww -o command= -p ${pid} || true`, { encoding: "utf8", maxBuffer: 1 << 24, stdio: ["ignore", "pipe", "ignore"] });
    if (!env.includes(`SIMULATOR_UDID=${udid}`)) continue;
    process.kill(pid, "SIGKILL");
    ended++;
  }
  return ended;
}

createServer((req, res) => {
  const url = new URL(req.url, "http://localhost");
  const asked = url.searchParams.get("id") ?? "";
  if (url.pathname === "/health") return res.end("ok");
  if (url.pathname === "/end-page-process") return res.end(String(endPageProcess(url.searchParams.get("udid") ?? "")));
  if (url.pathname === "/reset") {
    loads.delete(asked);
    reports.delete(asked);
    failing.delete(asked);
    return res.end("ok");
  }
  if (url.pathname === "/fail") {
    if (url.searchParams.get("on") === "1") failing.add(asked);
    else failing.delete(asked);
    return res.end("ok");
  }
  if (url.pathname === "/loads") return res.end(String(loads.get(asked) ?? 0));
  if (url.pathname === "/reports") {
    res.writeHead(200, { "content-type": "application/json" });
    return res.end(JSON.stringify(reports.get(asked) ?? []));
  }
  if (url.pathname === "/report") {
    let body = "";
    req.on("data", (chunk) => (body += chunk));
    req.on("end", () => {
      reports.set(asked, [...(reports.get(asked) ?? []), body]);
      res.end("ok");
    });
    return;
  }
  const match = /^\/mobile\/([^/]+)$/.exec(url.pathname);
  if (!match) {
    res.writeHead(200, { "content-type": "text/html" });
    return res.end("<!doctype html><title>Not the chat</title><p>This is not the chat page.</p>");
  }
  const id = match[1];
  const count = (loads.get(id) ?? 0) + 1;
  loads.set(id, count);
  if (id === "broken-bot" || failing.has(id)) {
    res.writeHead(500, { "content-type": "text/plain" });
    return res.end("Server error");
  }
  const send = () => {
    res.writeHead(200, { "content-type": "text/html", "cache-control": "no-store" });
    res.end(page(id, count));
  };
  if (id === "slow-ready-bot" && count > 1) return void setTimeout(send, 8000);
  send();
}).listen(port, "127.0.0.1", () => console.log(`Test page on http://localhost:${port}`));
