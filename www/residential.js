const residentialApi = '/cgi-bin/residential';

function resOnOff(id) {
  return $(id).checked ? 'ON' : 'OFF';
}

async function residentialRequest(action, data = {}) {
  return post(residentialApi, action, data);
}

function resH(text) {
  return String(text ?? '').replace(/[&<>"']/g, (ch) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
  })[ch]);
}

function residentialForm() {
  return {
    id: $('resId').value,
    enabled: resOnOff('resEnabled'),
    name: $('resName').value,
    server: $('resServer').value,
    port: $('resPort').value,
    username: $('resUsername').value,
    password: $('resPassword').value
  };
}

function clearResidentialForm() {
  ['resId', 'resName', 'resServer', 'resPort', 'resUsername', 'resPassword'].forEach((id) => { $(id).value = ''; });
  $('resPort').value = '443';
  $('resEnabled').checked = true;
}

function editResidential(node) {
  $('resId').value = node.id || '';
  $('resEnabled').checked = node.enabled !== 'OFF';
  $('resName').value = node.name || '';
  $('resServer').value = node.server || '';
  $('resPort').value = node.port || '443';
  $('resUsername').value = node.username || '';
  $('resPassword').value = '';
  toast('已载入静态住宅出口，密码留空会保留旧值');
}

function renderResidential(nodes = []) {
  const box = $('resList');
  if (!nodes.length) {
    box.innerHTML = '<div class="empty">还没有静态住宅出口。</div>';
    return;
  }
  box.innerHTML = nodes.map((node) => `
    <article class="node-card">
      <div>
        <strong>${resH(node.name || '--')}</strong>
        <span>${resH(node.server || '--')}:${resH(node.port || '--')} ｜ ${resH(node.username || '未填账号')}</span>
      </div>
      <div class="node-meta">
        <span>${node.enabled === 'OFF' ? '已停用' : '已启用'}</span>
        <span>SOCKS5 最终出口</span>
      </div>
      <div class="node-actions">
        <button data-res-edit="${node.id}">编辑</button>
        <button class="danger" data-res-delete="${node.id}">删除</button>
      </div>
    </article>
  `).join('');
  box.nodes = nodes;
}

async function loadResidential() {
  const data = await residentialRequest('list');
  if (data.ok) renderResidential(data.nodes || []);
}

async function runResidential(action) {
  let data;
  if (action === 'save') {
    data = await residentialRequest('save', residentialForm());
    $('resPassword').value = '';
  } else if (action === 'clear') {
    clearResidentialForm();
    return;
  }
  toast(data?.message || '静态住宅出口操作完成');
  await loadResidential();
  await refresh();
}

document.addEventListener('click', async (event) => {
  const action = event.target?.dataset?.resAction;
  const editId = event.target?.dataset?.resEdit;
  const deleteId = event.target?.dataset?.resDelete;
  if (action) runResidential(action);
  if (editId) {
    const node = ($('resList').nodes || []).find((item) => item.id === editId);
    if (node) editResidential(node);
  }
  if (deleteId) {
    const node = ($('resList').nodes || []).find((item) => item.id === deleteId);
    if (!confirmAction(`确认删除静态住宅出口“${node?.name || deleteId}”吗？`)) return;
    const data = await residentialRequest('delete', { id: deleteId });
    toast(data.message || '静态住宅出口已删除');
    await loadResidential();
    await refresh();
  }
});

clearResidentialForm();
loadResidential();
