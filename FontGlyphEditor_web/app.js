(() => {
  const DEFAULT_MASTER = window.location.protocol.startsWith('http') ? window.location.origin : 'http://127.0.0.1:9000';
  const state = {
    masterBaseURL: localStorage.getItem('fge_master_url') || DEFAULT_MASTER,
    token: localStorage.getItem('fge_token') || '',
    user: null,
    lines: [],
    selectedLineID: localStorage.getItem('fge_line_id') || '',
    loginMode: 'login',
    activeTab: 'editor',
    editorTab: 'adjust',
    isLoading: false,
    fontFile: null,
    fontObjectURL: '',
    exportedFontURL: '',
    exportedBlobURL: '',
    exportedName: '',
    outputFamilyName: '修符字体',
    previewText: '字体预览\n1234567890\nABCDEFGHIJK',
    adjustment: {
      scope: 'all',
      selected_chars: '',
      scale: 1,
      weight: 0,
      tracking: 0,
      baseline_shift: 0,
      line_height: 1
    },
    color: {
      scope: 'all',
      selected_chars: '',
      mode: 'none',
      solid_hex: '#E8836B',
      palette_text: '#E8836B,#F2B705,#3DA5D9,#73B66B',
      random_seed: 42
    },
    patches: [],
    generatedCards: [],
    allCards: [],
    users: []
  };

  const $app = document.getElementById('app');
  let toastTimer = null;
  let importedFontFace = null;
  let exportedFontFace = null;

  function escapeHtml(value) {
    return String(value ?? '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#039;');
  }

  function normalizeBaseURL(value) {
    const text = String(value || '').trim().replace(/\/+$/, '');
    return text || DEFAULT_MASTER;
  }

  function apiURL(base, path) {
    return `${normalizeBaseURL(base)}/${String(path).replace(/^\/+/, '')}`;
  }

  function selectedLine() {
    return state.lines.find(line => line.id === state.selectedLineID) || state.lines[0] || null;
  }

  function engineBaseURL() {
    const line = selectedLine();
    return line ? normalizeBaseURL(line.url) : '';
  }

  function makeID() {
    if (window.crypto && typeof window.crypto.randomUUID === 'function') return window.makeID();
    return `fge_${Date.now()}_${Math.random().toString(16).slice(2)}`;
  }

  function showToast(message, type = 'info') {
    let el = document.querySelector('.toast');
    if (!el) {
      el = document.createElement('div');
      el.className = 'toast';
      document.body.appendChild(el);
    }
    el.textContent = message;
    el.className = `toast show ${type === 'error' ? 'error' : ''}`;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => el.classList.remove('show'), 4200);
  }

  async function requestJSON(base, path, options = {}) {
    const headers = { ...(options.headers || {}) };
    if (options.body && !(options.body instanceof FormData)) headers['Content-Type'] = 'application/json';
    if (state.token && options.auth !== false) headers.Authorization = `Bearer ${state.token}`;
    const res = await fetch(apiURL(base, path), { ...options, headers });
    const contentType = res.headers.get('content-type') || '';
    let payload = null;
    if (contentType.includes('application/json')) payload = await res.json();
    else payload = await res.text();
    if (!res.ok) {
      let detail = typeof payload === 'string' ? payload : (payload.detail || payload.message || JSON.stringify(payload));
      if (Array.isArray(payload.detail)) detail = payload.detail.map(item => item.msg || JSON.stringify(item)).join('；');
      throw new Error(detail || `HTTP ${res.status}`);
    }
    return payload;
  }

  async function requestBlob(base, path, options = {}) {
    const headers = { ...(options.headers || {}) };
    if (state.token && options.auth !== false) headers.Authorization = `Bearer ${state.token}`;
    const res = await fetch(apiURL(base, path), { ...options, headers });
    if (!res.ok) {
      const text = await res.text();
      throw new Error(text || `HTTP ${res.status}`);
    }
    return { blob: await res.blob(), headers: res.headers };
  }

  function setLoading(flag) {
    state.isLoading = flag;
    render();
  }

  async function bootstrap() {
    if (!state.token) {
      render();
      return;
    }
    try {
      state.user = await requestJSON(state.masterBaseURL, '/auth/me');
      await refreshLines(false);
      state.activeTab = 'editor';
    } catch (err) {
      logout(false);
      showToast(`登录已失效：${err.message}`, 'error');
    }
    render();
  }

  function saveAuth(token, user) {
    state.token = token;
    state.user = user;
    localStorage.setItem('fge_token', token);
    localStorage.setItem('fge_master_url', state.masterBaseURL);
  }

  function logout(shouldRender = true) {
    state.token = '';
    state.user = null;
    state.lines = [];
    state.selectedLineID = '';
    localStorage.removeItem('fge_token');
    localStorage.removeItem('fge_line_id');
    if (shouldRender) render();
  }

  async function loginOrRegister() {
    const master = normalizeBaseURL(document.getElementById('login-master-url').value);
    const qq = document.getElementById('login-qq').value.trim();
    const password = document.getElementById('login-password').value;
    const confirm = document.getElementById('login-confirm')?.value || '';
    const cardKey = document.getElementById('login-card-key')?.value.trim() || '';
    state.masterBaseURL = master;
    localStorage.setItem('fge_master_url', master);
    try {
      setLoading(true);
      const payload = state.loginMode === 'login'
        ? { username: qq, password }
        : { qq, password, password_confirm: confirm, card_key: cardKey };
      const path = state.loginMode === 'login' ? '/auth/login' : '/auth/register';
      const auth = await requestJSON(master, path, { method: 'POST', auth: false, body: JSON.stringify(payload) });
      saveAuth(auth.token, auth.user);
      await refreshLines(false);
      state.activeTab = 'editor';
      showToast(state.loginMode === 'login' ? '登录成功' : '注册成功');
    } catch (err) {
      showToast(err.message, 'error');
    } finally {
      setLoading(false);
    }
  }

  async function refreshLines(shouldRender = true) {
    const lines = await requestJSON(state.masterBaseURL, '/config/lines');
    state.lines = Array.isArray(lines) ? lines : [];
    if (!state.lines.some(line => line.id === state.selectedLineID)) {
      state.selectedLineID = state.lines[0]?.id || '';
    }
    if (state.selectedLineID) localStorage.setItem('fge_line_id', state.selectedLineID);
    if (shouldRender) render();
  }

  function inferCharacterFromFilename(filename) {
    const base = filename.replace(/\.[^.]+$/, '').trim();
    const cleaned = base.replace(/^char[_-]?/i, '').replace(/^glyph[_-]?/i, '');
    if ([...cleaned].length === 1) return cleaned;
    const match = cleaned.match(/(?:^|[_\-\s])u\+?([0-9a-f]{4,6})(?:$|[_\-\s])/i) || cleaned.match(/^([0-9a-f]{4,6})$/i);
    if (match) {
      const cp = parseInt(match[1], 16);
      if (Number.isFinite(cp)) return String.fromCodePoint(cp);
    }
    return '';
  }

  async function loadFontFile(file) {
    if (!file) return;
    state.fontFile = file;
    if (state.fontObjectURL) URL.revokeObjectURL(state.fontObjectURL);
    state.fontObjectURL = URL.createObjectURL(file);
    const baseName = file.name.replace(/\.[^.]+$/, '');
    state.outputFamilyName = state.outputFamilyName === '修符字体' ? baseName : state.outputFamilyName;
    state.previewText = `${baseName}字体预览\n1234567890\nABCDEFGHIJK`;
    await installFontFace('ImportedFGEFont', state.fontObjectURL, 'imported');
    render();
    showToast(`已导入字体：${file.name}`);
  }

  async function installFontFace(family, url, kind) {
    try {
      const oldFace = kind === 'imported' ? importedFontFace : exportedFontFace;
      if (oldFace) document.fonts.delete(oldFace);
      const face = new FontFace(family, `url(${url})`);
      await face.load();
      document.fonts.add(face);
      if (kind === 'imported') importedFontFace = face;
      else exportedFontFace = face;
    } catch (err) {
      console.warn('FontFace load failed', err);
    }
  }

  async function addPatchFiles(files) {
    const list = Array.from(files || []);
    if (!list.length) return;
    for (const file of list) {
      const ext = file.name.split('.').pop().toLowerCase();
      if (ext === 'zip') {
        await inferZipPatches(file);
      } else {
        const previewURL = URL.createObjectURL(file);
        state.patches.push({
          id: makeID(),
          character: inferCharacterFromFilename(file.name),
          image_filename: file.name,
          sourceFile: file,
          sourceFileName: file.name,
          previewURL,
          scale: 1,
          tracking: 0,
          offset_x: 0,
          offset_y: 0,
          weight: 0,
          png_ppem: 160
        });
      }
    }
    state.editorTab = 'patch';
    render();
  }

  async function inferZipPatches(file) {
    const engine = engineBaseURL();
    if (!engine) {
      showToast('请先在账号页配置或选择线路，再导入 ZIP。', 'error');
      return;
    }
    try {
      const form = new FormData();
      form.append('files', file, file.name);
      const data = await requestJSON(engine, '/infer-images', { method: 'POST', body: form });
      const items = Array.isArray(data.items) ? data.items : [];
      if (!items.length) {
        state.patches.push(newPatchFromZip(file, file.name, ''));
        showToast('ZIP 已添加，但线路没有识别到图片，请手动填写替换字符。');
      } else {
        for (const item of items) state.patches.push(newPatchFromZip(file, item.filename, item.character || ''));
        showToast(`ZIP 已识别 ${items.length} 个修符项`);
      }
    } catch (err) {
      state.patches.push(newPatchFromZip(file, file.name, ''));
      showToast(`ZIP 自动识别失败：${err.message}`, 'error');
    }
  }

  function newPatchFromZip(file, imageFilename, character) {
    return {
      id: makeID(),
      character,
      image_filename: imageFilename,
      sourceFile: file,
      sourceFileName: file.name,
      previewURL: '',
      scale: 1,
      tracking: 0,
      offset_x: 0,
      offset_y: 0,
      weight: 0,
      png_ppem: 160
    };
  }

  function updatePatch(id, field, value) {
    const patch = state.patches.find(item => item.id === id);
    if (!patch) return;
    patch[field] = value;
    render();
  }

  function deletePatch(id) {
    const patch = state.patches.find(item => item.id === id);
    if (patch?.previewURL) URL.revokeObjectURL(patch.previewURL);
    state.patches = state.patches.filter(item => item.id !== id);
    render();
  }

  function duplicatePatch(id) {
    const patch = state.patches.find(item => item.id === id);
    if (!patch) return;
    state.patches.push({ ...patch, id: makeID(), character: '', previewURL: patch.previewURL });
    render();
  }

  function validPatches() {
    return state.patches.filter(p => String(p.character || '').trim() && String(p.image_filename || '').trim());
  }

  async function testEngine() {
    const engine = engineBaseURL();
    if (!engine) return showToast('暂无可用线路，请先配置总后端 config/lines.json。', 'error');
    try {
      setLoading(true);
      const res = await requestJSON(engine, '/health');
      showToast(res.ok ? '字体引擎连接成功' : '字体引擎无响应');
    } catch (err) {
      showToast(`字体引擎连接失败：${err.message}`, 'error');
    } finally {
      setLoading(false);
    }
  }

  function makeExportRequest() {
    return {
      output_family_name: state.outputFamilyName.trim() || '修符字体',
      preview_text: state.previewText,
      adjustment: {
        scope: state.adjustment.scope,
        selected_chars: state.adjustment.selected_chars,
        scale: Number(state.adjustment.scale),
        weight: Number(state.adjustment.weight),
        tracking: Math.round(Number(state.adjustment.tracking)),
        baseline_shift: Math.round(Number(state.adjustment.baseline_shift)),
        line_height: Number(state.adjustment.line_height)
      },
      color: {
        scope: state.color.scope,
        selected_chars: state.color.selected_chars,
        mode: state.color.mode,
        solid_hex: state.color.solid_hex,
        palette_hex: state.color.palette_text.split(',').map(s => s.trim()).filter(Boolean),
        random_seed: Math.round(Number(state.color.random_seed))
      },
      patches: validPatches().map(p => ({
        character: String(p.character).trim(),
        image_filename: p.image_filename,
        scale: Number(p.scale),
        tracking: Math.round(Number(p.tracking)),
        offset_x: Math.round(Number(p.offset_x)),
        offset_y: Math.round(Number(p.offset_y)),
        weight: Number(p.weight),
        png_ppem: Math.round(Number(p.png_ppem || 160))
      }))
    };
  }

  async function exportFont() {
    if (!state.fontFile) return showToast('请先导入 .ttf / .otf / .ttc 字体文件。', 'error');
    const engine = engineBaseURL();
    if (!engine) return showToast('暂无可用线路，请先配置并选择线路。', 'error');
    try {
      setLoading(true);
      const form = new FormData();
      form.append('font', state.fontFile, state.fontFile.name);
      form.append('request_json', JSON.stringify(makeExportRequest()));
      const added = new Set();
      for (const patch of validPatches()) {
        const key = `${patch.sourceFileName}::${patch.sourceFile.size}::${patch.sourceFile.lastModified}`;
        if (added.has(key)) continue;
        added.add(key);
        form.append('images', patch.sourceFile, patch.sourceFileName);
      }
      const { blob } = await requestBlob(engine, '/export', { method: 'POST', body: form });
      if (state.exportedBlobURL) URL.revokeObjectURL(state.exportedBlobURL);
      state.exportedBlobURL = URL.createObjectURL(blob);
      state.exportedName = `${(state.outputFamilyName.trim() || '修符字体').replace(/\.ttf$/i, '')}.ttf`;
      await installFontFace('ExportedFGEFont', state.exportedBlobURL, 'exported');
      downloadBlobURL(state.exportedBlobURL, state.exportedName);
      showToast(`字体文件已生成：${state.exportedName}`);
    } catch (err) {
      showToast(`导出失败：${err.message}`, 'error');
    } finally {
      setLoading(false);
    }
  }

  function downloadBlobURL(url, filename) {
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    a.remove();
  }

  async function loadUsers() {
    try {
      state.users = await requestJSON(state.masterBaseURL, '/admin/users');
      render();
    } catch (err) {
      showToast(`用户列表加载失败：${err.message}`, 'error');
    }
  }

  async function createUser() {
    const qq = document.getElementById('new-user-qq').value.trim();
    const password = document.getElementById('new-user-password').value;
    const role = document.getElementById('new-user-role').value;
    const days = Number(document.getElementById('new-user-days').value || 30);
    const expiresAt = Number.isFinite(days) && days > 0 ? new Date(Date.now() + days * 86400000).toISOString() : null;
    try {
      setLoading(true);
      await requestJSON(state.masterBaseURL, '/admin/users', { method: 'POST', body: JSON.stringify({ qq, password, role, expires_at: expiresAt, is_active: true }) });
      showToast('用户已创建');
      await loadUsers();
    } catch (err) {
      showToast(`创建用户失败：${err.message}`, 'error');
    } finally {
      setLoading(false);
    }
  }

  async function updateUser(userID) {
    const password = document.getElementById(`user-password-${userID}`).value;
    const role = document.getElementById(`user-role-${userID}`).value;
    const active = document.getElementById(`user-active-${userID}`).checked;
    const expiresAt = document.getElementById(`user-expire-${userID}`).value.trim();
    const body = { role, is_active: active };
    if (password) body.password = password;
    body.expires_at = expiresAt || null;
    try {
      await requestJSON(state.masterBaseURL, `/admin/users/${userID}`, { method: 'PATCH', body: JSON.stringify(body) });
      showToast('用户已更新');
      await loadUsers();
    } catch (err) {
      showToast(`更新用户失败：${err.message}`, 'error');
    }
  }

  async function generateCards() {
    const count = Number(document.getElementById('card-count').value || 1);
    const durationDays = Number(document.getElementById('card-days').value || 30);
    const note = document.getElementById('card-note').value.trim();
    try {
      setLoading(true);
      state.generatedCards = await requestJSON(state.masterBaseURL, '/admin/cards/generate', { method: 'POST', body: JSON.stringify({ count, duration_days: durationDays, note }) });
      showToast(`已生成 ${state.generatedCards.length} 个卡密`);
      await loadCards(false);
    } catch (err) {
      showToast(`生成卡密失败：${err.message}`, 'error');
    } finally {
      setLoading(false);
    }
  }

  async function loadCards(shouldRender = true) {
    try {
      state.allCards = await requestJSON(state.masterBaseURL, '/admin/cards');
      if (shouldRender) render();
    } catch (err) {
      showToast(`卡密列表加载失败：${err.message}`, 'error');
    }
  }

  function exportCardsCSV() {
    const url = apiURL(state.masterBaseURL, '/admin/cards/export.csv');
    fetch(url, { headers: { Authorization: `Bearer ${state.token}` } })
      .then(async res => {
        if (!res.ok) throw new Error(await res.text());
        return res.blob();
      })
      .then(blob => {
        const url = URL.createObjectURL(blob);
        downloadBlobURL(url, 'cards.csv');
        setTimeout(() => URL.revokeObjectURL(url), 2000);
      })
      .catch(err => showToast(`导出 CSV 失败：${err.message}`, 'error'));
  }

  function randomColorForChar(ch) {
    let hash = 0;
    const text = `${ch}${state.color.random_seed}`;
    for (let i = 0; i < text.length; i++) hash = ((hash << 5) - hash + text.charCodeAt(i)) | 0;
    const hue = Math.abs(hash) % 360;
    return `hsl(${hue}, 75%, 44%)`;
  }

  function colorForChar(ch) {
    if (state.color.mode === 'none') return '';
    if (state.color.scope === 'selected' && !state.color.selected_chars.includes(ch)) return '';
    if (state.color.mode === 'solid') return state.color.solid_hex || '';
    if (state.color.mode === 'random') return randomColorForChar(ch);
    const palette = state.color.palette_text.split(',').map(s => s.trim()).filter(Boolean);
    if (!palette.length) return '';
    let hash = 0;
    const text = `${ch}${state.color.random_seed}`;
    for (let i = 0; i < text.length; i++) hash = ((hash << 5) - hash + text.charCodeAt(i)) | 0;
    return palette[Math.abs(hash) % palette.length];
  }

  function patchMap() {
    const map = new Map();
    for (const patch of validPatches()) map.set([...patch.character.trim()][0], patch);
    return map;
  }

  function renderModifiedPreview() {
    const map = patchMap();
    const lines = state.previewText.split('\n');
    return lines.map(line => {
      const chars = [...line].map(ch => {
        const patch = map.get(ch);
        if (patch) {
          const size = Math.max(8, 32 * Number(state.adjustment.scale) * Number(patch.scale));
          const tx = Number(patch.offset_x) / 80;
          const ty = -Number(patch.offset_y) / 80 - Number(state.adjustment.baseline_shift) / 80;
          const margin = Math.max(0, Number(patch.tracking) / 160);
          if (patch.previewURL) {
            return `<span class="preview-patch" style="width:${size}px;height:${size}px;transform:translate(${tx}px,${ty}px);margin-right:${margin}px"><img src="${patch.previewURL}" alt="${escapeHtml(patch.character)}" style="width:${size}px;height:${size}px"></span>`;
          }
          return `<span class="preview-patch" style="width:${size}px;height:${size}px;transform:translate(${tx}px,${ty}px);margin-right:${margin}px"><span class="preview-patch-placeholder">ZIP</span></span>`;
        }
        const color = colorForChar(ch);
        const size = Math.max(8, 32 * Number(state.adjustment.scale));
        const spacing = Number(state.adjustment.tracking) / 80;
        const baseline = -Number(state.adjustment.baseline_shift) / 20;
        const colorStyle = color ? `color:${escapeHtml(color)};` : '';
        return `<span class="preview-char" style="font-family:ImportedFGEFont, system-ui, sans-serif;font-size:${size}px;margin-right:${spacing}px;transform:translateY(${baseline}px);${colorStyle}">${escapeHtml(ch)}</span>`;
      }).join('');
      return `<div class="preview-line" style="margin-bottom:${Math.max(4, 8 * Number(state.adjustment.line_height))}px">${chars || '&nbsp;'}</div>`;
    }).join('');
  }

  function loginView() {
    const isRegister = state.loginMode === 'register';
    return `
      <div class="login-wrap">
        <div class="card login-card">
          <div class="brand">
            <div class="logo">XF</div>
            <div>
              <h1>XFonts Web</h1>
              <p>FontGlyphEditor Web 端 · 登录后使用字体修符和后台管理</p>
            </div>
          </div>
          <div class="login-tabs">
            <button class="${state.loginMode === 'login' ? 'active' : ''}" data-action="login-mode" data-mode="login">登录</button>
            <button class="${state.loginMode === 'register' ? 'active' : ''}" data-action="login-mode" data-mode="register">注册</button>
          </div>
          <div class="grid">
            <label>总后端 Master 地址
              <input id="login-master-url" value="${escapeHtml(state.masterBaseURL)}" placeholder="https://font-master.example.com" />
            </label>
            <label>账号 / QQ
              <input id="login-qq" autocomplete="username" placeholder="admin" />
            </label>
            <label>密码
              <input id="login-password" type="password" autocomplete="current-password" />
            </label>
            ${isRegister ? `
              <label>确认密码
                <input id="login-confirm" type="password" autocomplete="new-password" />
              </label>
              <label>卡密
                <input id="login-card-key" placeholder="FGE-..." />
              </label>` : ''}
            <button class="btn primary full" data-action="submit-login" ${state.isLoading ? 'disabled' : ''}>${state.isLoading ? '处理中...' : (isRegister ? '注册并登录' : '登录')}</button>
            <p class="muted small">默认超级管理员由 Master 后端环境变量 <span class="mono">SUPER_ADMIN_QQ</span> / <span class="mono">SUPER_ADMIN_PASSWORD</span> 创建。Web 端和 iOS 端共用同一套账号、卡密与线路配置。</p>
          </div>
        </div>
      </div>`;
  }

  function topbar() {
    return `
      <div class="topbar">
        <div class="brand">
          <div class="logo">XF</div>
          <div>
            <h1>XFonts Web</h1>
            <p>FontGlyphEditor Web 端</p>
          </div>
        </div>
        <div class="user-pill">
          <span>${escapeHtml(state.user?.qq || '')}</span>
          <span class="badge ${state.user?.role === 'super_admin' ? 'good' : ''}">${state.user?.role === 'super_admin' ? '超级管理员' : '管理员'}</span>
          <button class="btn danger" data-action="logout">退出</button>
        </div>
      </div>`;
  }

  function navTabs() {
    const tabs = [
      ['editor', '字体修符'],
      ...(state.user?.role === 'super_admin' ? [['admin', '用户管理']] : []),
      ['account', '账号 / 线路']
    ];
    return `<div class="tabs">${tabs.map(([id, title]) => `<button class="${state.activeTab === id ? 'active' : ''}" data-action="tab" data-tab="${id}">${title}</button>`).join('')}</div>`;
  }

  function editorView() {
    const line = selectedLine();
    return `
      <div class="main-grid">
        <div class="grid">
          <div class="card card-pad">
            <div class="section-title"><h2>当前字体</h2><span class="badge">${state.fontFile ? escapeHtml(state.fontFile.name) : '未导入'}</span></div>
            <div class="grid grid-2">
              <label>导出字体名称
                <input data-bind="outputFamilyName" value="${escapeHtml(state.outputFamilyName)}" />
              </label>
              <label>导入字体文件
                <input type="file" accept=".ttf,.otf,.ttc" data-action="font-file" />
              </label>
            </div>
            <div style="height:12px"></div>
            <label>预览文本
              <textarea data-bind="previewText">${escapeHtml(state.previewText)}</textarea>
            </label>
          </div>

          <div class="card card-pad">
            <div class="section-title"><h3>预览</h3><span class="muted small">修改后为 Web 本地预览；最终效果以导出字体为准</span></div>
            <div class="grid grid-2">
              <div>
                <div class="muted small" style="margin-bottom:8px">原始</div>
                <div class="preview-box" style="font-family:ImportedFGEFont, system-ui, sans-serif;font-size:32px">${escapeHtml(state.previewText)}</div>
              </div>
              <div>
                <div class="muted small" style="margin-bottom:8px">修改后</div>
                <div class="preview-box modified-preview">${renderModifiedPreview()}</div>
              </div>
            </div>
            ${state.exportedBlobURL ? `<div class="hr"></div><div class="btn-row"><span class="badge good">最近已生成：${escapeHtml(state.exportedName)}</span><button class="btn" data-action="download-exported">重新下载</button><span class="muted small" style="font-family:ExportedFGEFont, system-ui, sans-serif;font-size:20px">${escapeHtml(state.previewText.split('\n')[0] || '字体预览')}</span></div>` : ''}
          </div>
        </div>

        <div class="grid">
          <div class="card card-pad">
            <div class="section-title"><h3>字体引擎线路</h3><button class="btn" data-action="refresh-lines">刷新</button></div>
            ${state.lines.length ? `
              <label>选择线路
                <select data-action="select-line">
                  ${state.lines.map(item => `<option value="${escapeHtml(item.id)}" ${item.id === state.selectedLineID ? 'selected' : ''}>${escapeHtml(item.name)}</option>`).join('')}
                </select>
              </label>
              <p class="muted small">当前：${escapeHtml(line?.url || '')}</p>` : `<p class="muted small">暂无可用线路。请检查 Master 后端 <span class="mono">config/lines.json</span>。</p>`}
            <div class="btn-row"><button class="btn" data-action="test-engine">测试线路</button></div>
          </div>

          <div class="card card-pad">
            ${editorPanels()}
          </div>

          <div class="card card-pad">
            <div class="section-title"><h3>导出</h3></div>
            <button class="btn primary full" data-action="export-font" ${state.isLoading || !state.fontFile ? 'disabled' : ''}>${state.isLoading ? '正在生成...' : '生成并下载字体文件'}</button>
            <p class="muted small">会调用当前线路后端的 <span class="mono">/export</span>，并自动附带登录 Token。</p>
          </div>
        </div>
      </div>`;
  }

  function editorPanels() {
    const tabs = [['adjust', '调整'], ['color', '颜色'], ['patch', '修符']];
    return `
      <div class="subtabs">${tabs.map(([id, title]) => `<button class="${state.editorTab === id ? 'active' : ''}" data-action="editor-tab" data-tab="${id}">${title}</button>`).join('')}</div>
      ${state.editorTab === 'adjust' ? adjustPanel() : state.editorTab === 'color' ? colorPanel() : patchPanel()}`;
  }

  function scopeButtons(prefix, value) {
    return `<div class="scope">
      <button class="${value === 'all' ? 'active' : ''}" data-action="scope" data-prefix="${prefix}" data-value="all">全部字符</button>
      <button class="${value === 'selected' ? 'active' : ''}" data-action="scope" data-prefix="${prefix}" data-value="selected">指定字符</button>
    </div>`;
  }

  function rangeRow(label, path, min, max, step, value) {
    return `<div class="range-row"><span>${label}</span><input type="range" min="${min}" max="${max}" step="${step}" value="${value}" data-path="${path}"><span class="mono muted">${value}</span></div>`;
  }

  function adjustPanel() {
    return `<div class="panel">
      <h3 style="margin:0">调整</h3>
      ${scopeButtons('adjustment', state.adjustment.scope)}
      ${state.adjustment.scope === 'selected' ? `<label>指定字符<input data-path="adjustment.selected_chars" value="${escapeHtml(state.adjustment.selected_chars)}" placeholder="例如：测试ABC" /></label>` : ''}
      ${rangeRow('大小', 'adjustment.scale', 0.5, 2, 0.01, state.adjustment.scale)}
      ${rangeRow('粗细', 'adjustment.weight', -8, 8, 1, state.adjustment.weight)}
      ${rangeRow('字间距', 'adjustment.tracking', -300, 800, 1, state.adjustment.tracking)}
      ${rangeRow('上浮下沉', 'adjustment.baseline_shift', -800, 800, 1, state.adjustment.baseline_shift)}
      ${rangeRow('行距', 'adjustment.line_height', 0.7, 2.2, 0.01, state.adjustment.line_height)}
    </div>`;
  }

  function colorPanel() {
    return `<div class="panel">
      <h3 style="margin:0">颜色</h3>
      ${scopeButtons('color', state.color.scope)}
      ${state.color.scope === 'selected' ? `<label>指定字符<input data-path="color.selected_chars" value="${escapeHtml(state.color.selected_chars)}" placeholder="例如：测试ABC" /></label>` : ''}
      <label>颜色模式
        <select data-path="color.mode">
          <option value="none" ${state.color.mode === 'none' ? 'selected' : ''}>不改颜色</option>
          <option value="solid" ${state.color.mode === 'solid' ? 'selected' : ''}>统一颜色</option>
          <option value="random" ${state.color.mode === 'random' ? 'selected' : ''}>完全随机</option>
          <option value="palette_random" ${state.color.mode === 'palette_random' ? 'selected' : ''}>指定色随机</option>
        </select>
      </label>
      ${state.color.mode === 'solid' ? `<label>统一颜色<input data-path="color.solid_hex" value="${escapeHtml(state.color.solid_hex)}" placeholder="#E8836B" /></label>` : ''}
      ${state.color.mode === 'palette_random' ? `<label>调色盘<input data-path="color.palette_text" value="${escapeHtml(state.color.palette_text)}" placeholder="#E8836B,#F2B705" /></label>` : ''}
      ${state.color.mode === 'random' || state.color.mode === 'palette_random' ? rangeRow('随机种子', 'color.random_seed', 1, 999, 1, state.color.random_seed) : ''}
      <p class="muted small">颜色会写入 SVG / sbix 彩色字形表。不同浏览器和 App 对彩色字体表支持不同。</p>
    </div>`;
  }

  function patchPanel() {
    return `<div class="panel">
      <div class="section-title"><h3>修符</h3></div>
      <label class="file-drop">
        <strong>添加 PNG / JPEG / WEBP / ZIP</strong>
        <span class="muted small">ZIP 会发送到当前线路自动识别文件名对应字符。</span>
        <input type="file" multiple accept=".png,.jpg,.jpeg,.webp,.zip" data-action="patch-files" />
        <span class="btn">选择文件</span>
      </label>
      <div class="patch-list">
        ${state.patches.length ? state.patches.map(patchRow).join('') : `<div class="muted small">还没有修符图片。导入图片后填写要替换的字符。</div>`}
      </div>
    </div>`;
  }

  function patchRow(p) {
    return `<div class="patch-row">
      <div class="patch-thumb">${p.previewURL ? `<img src="${p.previewURL}" alt="">` : '<span>ZIP</span>'}</div>
      <div>
        <div class="patch-head">
          <div><strong>${escapeHtml(p.image_filename)}</strong><div class="muted small">来源：${escapeHtml(p.sourceFileName)}</div></div>
          <div class="btn-row"><button class="btn" data-action="duplicate-patch" data-id="${p.id}">复制</button><button class="btn danger" data-action="delete-patch" data-id="${p.id}">删除</button></div>
        </div>
        <div class="patch-controls">
          <label>替换字符<input data-patch="${p.id}" data-field="character" value="${escapeHtml(p.character)}" placeholder="如 字" /></label>
          ${rangePatchRow('大小', p, 'scale', 0.3, 3, 0.01)}
          ${rangePatchRow('字距', p, 'tracking', -300, 800, 1)}
          ${rangePatchRow('左右', p, 'offset_x', -800, 800, 1)}
          ${rangePatchRow('上下', p, 'offset_y', -800, 800, 1)}
          ${rangePatchRow('粗细', p, 'weight', -8, 8, 1)}
          ${rangePatchRow('PNG ppem', p, 'png_ppem', 16, 1024, 1)}
        </div>
      </div>
    </div>`;
  }

  function rangePatchRow(label, p, field, min, max, step) {
    return `<div class="range-row"><span>${label}</span><input type="range" min="${min}" max="${max}" step="${step}" value="${p[field]}" data-patch="${p.id}" data-field="${field}"><span class="mono muted">${p[field]}</span></div>`;
  }

  function accountView() {
    const line = selectedLine();
    return `<div class="grid grid-2">
      <div class="card card-pad">
        <div class="section-title"><h2>账号</h2></div>
        <div class="grid">
          <p><strong>账号：</strong>${escapeHtml(state.user?.qq || '')}</p>
          <p><strong>身份：</strong>${state.user?.role === 'super_admin' ? '超级管理员' : '管理员'}</p>
          <p><strong>到期：</strong>${escapeHtml(state.user?.expires_at || '永久')}</p>
          <p><strong>Master：</strong><span class="mono">${escapeHtml(state.masterBaseURL)}</span></p>
        </div>
      </div>
      <div class="card card-pad">
        <div class="section-title"><h2>线路</h2><button class="btn" data-action="refresh-lines">刷新线路</button></div>
        ${state.lines.length ? `<div class="grid">
          <label>当前线路
            <select data-action="select-line">
              ${state.lines.map(item => `<option value="${escapeHtml(item.id)}" ${item.id === state.selectedLineID ? 'selected' : ''}>${escapeHtml(item.name)}</option>`).join('')}
            </select>
          </label>
          <p class="muted small">当前 URL：${escapeHtml(line?.url || '')}</p>
          <button class="btn" data-action="test-engine">测试当前线路</button>
        </div>` : `<p class="muted">暂无线路，请配置 Master 的 config/lines.json。</p>`}
      </div>
    </div>`;
  }

  function adminView() {
    return `<div class="grid">
      <div class="grid grid-2">
        <div class="card card-pad">
          <div class="section-title"><h2>添加用户</h2></div>
          <div class="grid">
            <label>账号 / QQ<input id="new-user-qq" placeholder="user001" /></label>
            <label>初始密码<input id="new-user-password" type="password" /></label>
            <label>角色<select id="new-user-role"><option value="admin">管理员</option><option value="super_admin">超级管理员</option></select></label>
            <label>有效天数<input id="new-user-days" type="number" value="30" /></label>
            <button class="btn primary" data-action="create-user">添加用户</button>
          </div>
        </div>
        <div class="card card-pad">
          <div class="section-title"><h2>生成卡密</h2><button class="btn" data-action="load-cards">刷新卡密</button></div>
          <div class="grid">
            <label>数量<input id="card-count" type="number" value="10" min="1" max="500" /></label>
            <label>有效天数<input id="card-days" type="number" value="30" min="1" /></label>
            <label>备注<input id="card-note" placeholder="例如：测试批次" /></label>
            <div class="btn-row"><button class="btn primary" data-action="generate-cards">生成卡密</button><button class="btn" data-action="export-cards">导出 CSV</button></div>
          </div>
        </div>
      </div>
      ${state.generatedCards.length ? `<div class="card card-pad"><div class="section-title"><h3>本次生成卡密</h3></div><div class="card-key-list">${state.generatedCards.map(card => `<div class="card-key-item"><div class="mono">${escapeHtml(card.card_key)}</div><div class="muted small">${card.duration_days} 天 · ${escapeHtml(card.note || '')}</div></div>`).join('')}</div></div>` : ''}
      <div class="card card-pad">
        <div class="section-title"><h2>用户列表</h2><button class="btn" data-action="load-users">刷新用户</button></div>
        <div class="table-wrap"><table><thead><tr><th>ID</th><th>账号</th><th>角色</th><th>到期时间 ISO</th><th>状态</th><th>改密码</th><th>操作</th></tr></thead><tbody>${state.users.map(userRow).join('') || '<tr><td colspan="7" class="muted">暂无数据，点击刷新用户。</td></tr>'}</tbody></table></div>
      </div>
      <div class="card card-pad">
        <div class="section-title"><h2>卡密列表</h2><button class="btn" data-action="load-cards">刷新卡密</button></div>
        <div class="table-wrap"><table><thead><tr><th>卡密</th><th>天数</th><th>备注</th><th>状态</th><th>使用者ID</th><th>创建时间</th></tr></thead><tbody>${state.allCards.map(cardRow).join('') || '<tr><td colspan="6" class="muted">暂无数据，点击刷新卡密。</td></tr>'}</tbody></table></div>
      </div>
    </div>`;
  }

  function userRow(user) {
    return `<tr>
      <td>${user.id}</td>
      <td>${escapeHtml(user.qq)}</td>
      <td><select id="user-role-${user.id}"><option value="admin" ${user.role === 'admin' ? 'selected' : ''}>管理员</option><option value="super_admin" ${user.role === 'super_admin' ? 'selected' : ''}>超级管理员</option></select></td>
      <td><input id="user-expire-${user.id}" value="${escapeHtml(user.expires_at || '')}" placeholder="留空表示永久" /></td>
      <td><label style="display:flex;align-items:center;gap:6px"><input id="user-active-${user.id}" type="checkbox" ${user.is_active ? 'checked' : ''} style="width:auto">启用</label></td>
      <td><input id="user-password-${user.id}" type="password" placeholder="不改则留空" /></td>
      <td><button class="btn" data-action="update-user" data-id="${user.id}">保存</button></td>
    </tr>`;
  }

  function cardRow(card) {
    return `<tr>
      <td class="mono">${escapeHtml(card.card_key)}</td>
      <td>${card.duration_days}</td>
      <td>${escapeHtml(card.note || '')}</td>
      <td>${card.is_used ? '<span class="badge danger">已使用</span>' : '<span class="badge good">未使用</span>'}</td>
      <td>${card.used_by_user_id ?? ''}</td>
      <td>${escapeHtml(card.created_at || '')}</td>
    </tr>`;
  }

  function appView() {
    return `<div class="shell">${topbar()}${navTabs()}${state.activeTab === 'editor' ? editorView() : state.activeTab === 'admin' ? adminView() : accountView()}</div>`;
  }

  function render() {
    $app.innerHTML = state.user && state.token ? appView() : loginView();
  }

  function setPath(path, value) {
    const [root, key] = path.split('.');
    if (!state[root] || !key) return;
    const current = state[root][key];
    state[root][key] = typeof current === 'number' ? Number(value) : value;
  }

  document.addEventListener('click', async (event) => {
    const target = event.target.closest('[data-action]');
    if (!target) return;
    const action = target.dataset.action;
    if (action === 'login-mode') { state.loginMode = target.dataset.mode; render(); }
    if (action === 'submit-login') loginOrRegister();
    if (action === 'logout') logout();
    if (action === 'tab') {
      state.activeTab = target.dataset.tab;
      render();
      if (state.activeTab === 'admin' && state.user?.role === 'super_admin' && !state.users.length) loadUsers();
    }
    if (action === 'editor-tab') { state.editorTab = target.dataset.tab; render(); }
    if (action === 'scope') { state[target.dataset.prefix].scope = target.dataset.value; render(); }
    if (action === 'refresh-lines') {
      try { await refreshLines(); showToast('线路已刷新'); } catch (err) { showToast(err.message, 'error'); }
    }
    if (action === 'test-engine') testEngine();
    if (action === 'export-font') exportFont();
    if (action === 'download-exported' && state.exportedBlobURL) downloadBlobURL(state.exportedBlobURL, state.exportedName || 'FontGlyphEditor_Export.ttf');
    if (action === 'delete-patch') deletePatch(target.dataset.id);
    if (action === 'duplicate-patch') duplicatePatch(target.dataset.id);
    if (action === 'load-users') loadUsers();
    if (action === 'create-user') createUser();
    if (action === 'update-user') updateUser(target.dataset.id);
    if (action === 'generate-cards') generateCards();
    if (action === 'load-cards') loadCards();
    if (action === 'export-cards') exportCardsCSV();
  });

  document.addEventListener('input', (event) => {
    const target = event.target;
    if (target.matches('[data-bind="outputFamilyName"]')) { state.outputFamilyName = target.value; return; }
    if (target.matches('[data-bind="previewText"]')) { state.previewText = target.value; render(); return; }
    if (target.dataset.path) { setPath(target.dataset.path, target.value); render(); return; }
    if (target.dataset.patch && target.dataset.field) { updatePatch(target.dataset.patch, target.dataset.field, target.type === 'range' ? Number(target.value) : target.value); }
  });

  document.addEventListener('change', (event) => {
    const target = event.target;
    if (target.dataset.action === 'font-file') loadFontFile(target.files[0]);
    if (target.dataset.action === 'patch-files') addPatchFiles(target.files);
    if (target.dataset.action === 'select-line') {
      state.selectedLineID = target.value;
      localStorage.setItem('fge_line_id', state.selectedLineID);
      render();
    }
    if (target.dataset.path) { setPath(target.dataset.path, target.value); render(); }
  });

  bootstrap();
})();
