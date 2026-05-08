const chatForm = document.getElementById('chat-form');
const chatInput = document.getElementById('chat-input');
const chatLog = document.getElementById('chat-log');
const mood = document.getElementById('mood');
const avatar = document.getElementById('avatar');
const closeBtn = document.getElementById('close-btn');
const dragBar = document.getElementById('drag-bar');

const STORAGE_KEY = 'virtual_ena_memory_v1';
const PLAYER_NAME = '雪鹰';

const memory = loadMemory();
memory.userName = PLAYER_NAME;
renderHistory(memory.history || []);

chatForm.addEventListener('submit', (event) => {
  event.preventDefault();
  const text = chatInput.value.trim();
  if (!text) return;

  appendMessage('user', text);
  memory.history.push({ role: 'user', text, ts: Date.now() });

  const reply = buildReply(text, memory);
  appendMessage('bot', reply);
  memory.history.push({ role: 'bot', text: reply, ts: Date.now() });

  saveMemory(memory);
  chatInput.value = '';
  chatInput.focus();
});

closeBtn.addEventListener('click', () => {
  window.desktopPet.quit();
});

let dragging = false;
let lastX = 0;
let lastY = 0;

dragBar.addEventListener('mousedown', (event) => {
  dragging = true;
  lastX = event.screenX;
  lastY = event.screenY;
});

window.addEventListener('mouseup', () => {
  dragging = false;
});

window.addEventListener('mousemove', (event) => {
  if (!dragging) return;
  const dx = event.screenX - lastX;
  const dy = event.screenY - lastY;
  lastX = event.screenX;
  lastY = event.screenY;
  window.desktopPet.dragWindow(dx, dy);
});

function appendMessage(role, text) {
  const item = document.createElement('div');
  item.className = `msg ${role}`;
  const label = role === 'user' ? PLAYER_NAME : 'Ena';
  item.innerHTML = `<strong>${label}：</strong>${escapeHtml(text)}`;
  chatLog.appendChild(item);
  chatLog.scrollTop = chatLog.scrollHeight;
}

function buildReply(input, mem) {
  const t = input.toLowerCase();
  mem.userName = PLAYER_NAME;

  if (t.includes('我叫') || t.includes('名字')) {
    avatar.textContent = 'Ena';
    mood.textContent = '状态：聊天中';
    return '我知道啦，雪鹰君。突然又确认名字什么的……有点太正式了吧。';
  }

  if (t.includes('你记得我吗') || t.includes('还记得我')) {
    avatar.textContent = 'Ena';
    return '当然记得。你是雪鹰君，这种事我还不至于忘掉。';
  }

  if (t.includes('你好') || t.includes('hi') || t.includes('hello')) {
    avatar.textContent = 'Ena';
    return '你好，雪鹰君。嗯……今天想聊什么？';
  }

  if (t.includes('再见') || t.includes('bye')) {
    avatar.textContent = 'Ena';
    mood.textContent = '状态：待机中';
    return '下次见，雪鹰君。我会在这里等你的。';
  }

  avatar.textContent = 'Ena';
  mood.textContent = '状态：聊天中';
  return `${PLAYER_NAME}，我听到了：“${input}”。这个 MVP 目前还是规则回复，之后接入真正的 AI 模型时会更自然一点。`;
}

function loadMemory() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : { history: [], userName: PLAYER_NAME };
  } catch {
    return { history: [], userName: PLAYER_NAME };
  }
}

function saveMemory(data) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(data));
}

function renderHistory(history) {
  history.slice(-30).forEach((h) => appendMessage(h.role, h.text));
}

function escapeHtml(str) {
  return str
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}
