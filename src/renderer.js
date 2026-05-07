const chatForm = document.getElementById('chat-form');
const chatInput = document.getElementById('chat-input');
const chatLog = document.getElementById('chat-log');
const mood = document.getElementById('mood');
const avatar = document.getElementById('avatar');
const closeBtn = document.getElementById('close-btn');
const dragBar = document.getElementById('drag-bar');

const STORAGE_KEY = 'virtual_ena_memory_v1';

const memory = loadMemory();
renderHistory(memory.history || []);
if (!memory.history?.length) {
  appendMessage('bot', '嗨，我是 Harumi Ena 的最小原型桌宠！你可以先告诉我你的名字。');
}

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
  const label = role === 'user' ? '你' : 'Ena';
  item.innerHTML = `<strong>${label}：</strong>${escapeHtml(text)}`;
  chatLog.appendChild(item);
  chatLog.scrollTop = chatLog.scrollHeight;
}

function buildReply(input, mem) {
  const t = input.toLowerCase();

  if (t.includes('我叫') || t.includes('名字')) {
    const name = extractName(input);
    if (name) {
      mem.userName = name;
      mood.textContent = `状态：记住你啦，${name}`;
      avatar.textContent = '✨';
      return `认识你很开心，${name}！我已经记住你的名字了。`;
    }
    return '可以再告诉我一次你的名字吗？比如“我叫小明”。';
  }

  if (t.includes('你记得我吗') || t.includes('还记得我')) {
    avatar.textContent = '🤔';
    return mem.userName
      ? `当然记得，你是${mem.userName}。`
      : '我现在还不知道你的名字，你可以说“我叫xxx”。';
  }

  if (t.includes('你好') || t.includes('hi') || t.includes('hello')) {
    avatar.textContent = '😊';
    return mem.userName
      ? `你好呀，${mem.userName}！今天想聊什么？`
      : '你好呀～先告诉我你的名字吧。';
  }

  if (t.includes('再见') || t.includes('bye')) {
    avatar.textContent = '👋';
    mood.textContent = '状态：待机中';
    return '下次见～我会在这里等你。';
  }

  avatar.textContent = '💬';
  mood.textContent = '状态：聊天中';
  return mem.userName
    ? `${mem.userName}，我听到了：“${input}”。这个MVP目前是规则回复，下一步可以接入真实AI模型。`
    : `我听到了：“${input}”。如果你愿意，先告诉我你的名字，我就能有“记忆”体验。`;
}

function extractName(text) {
  const m = text.match(/我叫\s*([\u4e00-\u9fa5A-Za-z0-9_]{1,20})/);
  return m?.[1] || '';
}

function loadMemory() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : { history: [], userName: '' };
  } catch {
    return { history: [], userName: '' };
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
