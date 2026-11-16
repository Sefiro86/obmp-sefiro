// OblivionMP.Chat 1.1.0 chat page by ReadyM, with the Chat History feature by Sefiro
// (https://github.com/Sefiro86/obmp-sefiro). The original file belongs to ReadyM; the additions are
// marked "Chat History" and released under the MIT license.

const CAPACITY = 100;

// How long the log stays up after the last thing happened, once chat is closed.
const FADE_AFTER_MS = 8000;

const lines = document.getElementById('lines');
const entry = document.getElementById('entry');

let fadeTimer = 0;

// Chat History: Up and Down bring back the lines you sent before, including those from previous
// sessions. The Sefiro.ChatHistory client mod keeps them in a file, because the game's browser does not
// save localStorage to disk. Without the mod the history only lasts for the current session.
const HISTORY_MAX = 200;
let chatHistory = [];    // oldest first
let historyAt = -1;      // -1 = editing a new line, not browsing
let historyDraft = '';   // what was being typed before pressing Up
(async () => {
  try {
    const text = await Promise.race([
      readym.request('SefiroChatHistoryLoad', ''),
      new Promise((_, reject) => setTimeout(() => reject(new Error('timeout')), 3000)),
    ]);
    const saved = String(text || '').split(/\r?\n/).filter(Boolean);
    chatHistory = saved.concat(chatHistory.filter((line) => !saved.includes(line))).slice(-HISTORY_MAX);
  } catch (e) { /* Sefiro.ChatHistory is not installed: session-only history */ }
})();

function remember(text) {
  chatHistory = chatHistory.filter((line) => line !== text);
  chatHistory.push(text);
  if (chatHistory.length > HISTORY_MAX) chatHistory.shift();
  try { readym.postMessage('SefiroChatHistoryAdd', text); } catch (e) { /* mod not installed */ }
}

function browseHistory(step) {
  if (!chatHistory.length) return;
  if (historyAt === -1) {
    if (step > 0) return;
    historyDraft = entry.value;
    historyAt = chatHistory.length;
  }
  historyAt += step;
  if (historyAt < 0) historyAt = 0;
  if (historyAt >= chatHistory.length) {
    historyAt = -1;
    entry.value = historyDraft;
  } else {
    entry.value = chatHistory[historyAt];
  }
  const end = entry.value.length;
  entry.setSelectionRange(end, end);
}

const clock = new Intl.DateTimeFormat(undefined, { hour: '2-digit', minute: '2-digit', hour12: false });

// Shows the log and restarts the countdown to it fading. While chat is open the log stays up, so there is
// nothing to count down to.
function wake() {
  document.body.classList.remove('idle');
  clearTimeout(fadeTimer);

  if (!document.body.classList.contains('open')) {
    fadeTimer = setTimeout(() => document.body.classList.add('idle'), FADE_AFTER_MS);
  }
}

// OPEN MEANS FOCUSED. The game gives the page the keyboard and then says so; the page answers by focusing its
// entry line, which is the only moment it can, because losing focus deliberately clears whatever was focused.
// Nothing here closes chat by itself: while the entry line is up every key belongs to it, including the ones
// the game would otherwise take.
function setOpen(open) {
  document.body.classList.toggle('open', open);

  if (open) {
    wake();
    entry.focus();

    // OPEN MUST MEAN FOCUSED. If the entry did not take the keyboard there is no blur to come later and
    // nothing here could hear a key, so the game would hold input for a page that cannot ask for it back.
    if (document.activeElement !== entry) readym.sendClose();
    return;
  }

  entry.value = '';
  historyAt = -1;   // Chat History
  entry.blur();

  // PUT AWAY AT ONCE when chat is closed, rather than lingering. The countdown above is for a line that
  // arrived while you were playing; a chat you just dismissed should go.
  clearTimeout(fadeTimer);
  document.body.classList.add('idle');
}

function show(batch, replace) {
  if (replace) lines.replaceChildren();

  for (const line of batch) {
    const item = document.createElement('li');
    item.className = line.kind;

    // A local line from another mod can ask for its own color over the one its kind gets.
    if (line.color) item.style.color = line.color;

    const time = document.createElement('span');
    time.className = 'time';
    time.textContent = `[${clock.format(new Date(line.at))}] `;
    item.append(time);

    if (line.kind === 'Player') {
      const who = document.createElement('span');
      who.className = 'nickname';
      who.textContent = line.nickname;
      item.append(who, document.createTextNode(`: ${line.text}`));
    } else {
      item.append(line.text);
    }

    lines.append(item);
  }

  while (lines.children.length > CAPACITY) lines.firstChild.remove();
  lines.scrollTop = lines.scrollHeight;

  wake();
}

readym.on('Line', (json) => show(JSON.parse(json), false));
readym.on('History', (json) => show(JSON.parse(json), true));
readym.on('Open', (open) => setOpen(open));

readym.sendRequestHistory();

// ANYTHING TAKING THE KEYBOARD ENDS CHAT. The game hands input to the UI while chat is up and takes it back
// only when told, and the only thing that can tell it is a page that still has the keyboard. So a page that
// quietly lost focus would leave input with the UI and nothing able to give it back.
//
// ONCE, not per frame: the game answers by closing, which clears the class below before blurring the entry
// itself, so its own blur says nothing.
entry.addEventListener('blur', () => {
  if (document.body.classList.contains('open')) readym.sendClose();
});

entry.addEventListener('keydown', (e) => {
  // ESCAPE IS THE ONLY WAY OUT, and it is caught here rather than bound in the game: the game binds one key,
  // the one that opens chat, and everything while chat is up belongs to the page.
  if (e.key === 'Escape') {
    readym.sendClose();
    return;
  }

  // Chat History: Up and Down browse the lines sent before.
  if (e.key === 'ArrowUp' || e.key === 'ArrowDown') {
    e.preventDefault();
    browseHistory(e.key === 'ArrowUp' ? -1 : 1);
    return;
  }

  if (e.key !== 'Enter') return;

  // SENDS WITHOUT CLOSING. Chat that closed itself on every line would hand the keyboard back mid-conversation,
  // and the next key you typed would reach the game instead.
  const text = entry.value.trim();
  entry.value = '';

  historyAt = -1;   // Chat History
  if (text) {
    remember(text);   // Chat History
    readym.sendSubmit(text);
  }
});

wake();
