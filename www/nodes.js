const nodesApi = '/cgi-bin/nodes';

async function nodeRequest(action, data = {}) {
  return post(nodesApi, action, data);
}

function nodeOnOff(id) {
  return $(id).checked ? 'ON' : 'OFF';
}

function nodeForm() {
  return {
    id: $('nodeId').value,
    enabled: nodeOnOff('nodeEnabled'),
    name: $('nodeName').value,
    type: $('nodeType').value,
    server: $('nodeServer').value,
    port: $('nodePort').value,
    username: $('nodeUsername').value,
    password: $('nodePassword').value,
    cipher: $('nodeCipher').value,
    uuid: $('nodeUuid').value,
    sni: $('nodeSni').value,
    flow: $('nodeFlow').value,
    public_key: $('nodePublicKey').value,
    short_id: $('nodeShortId').value,
    use_residential: nodeOnOff('nodeUseResidential')
  };
}

function clearNodeForm() {
  ['nodeId', 'nodeName', 'nodeServer', 'nodePort', 'nodeUsername', 'nodePassword',
    'nodeUuid', 'nodeSni', 'nodePublicKey', 'nodeShortId'].forEach((id) => { $(id).value = ''; });
  $('nodeType').value = 'shadowsocks';
  $('nodeCipher').value = 'aes-128-gcm';
  $('nodeFlow').value = 'xtls-rprx-vision';
  $('nodeEnabled').checked = true;
  $('nodeUseResidential').checked = false;
}

function h(text) {
  return String(text ?? '').replace(/[&<>"']/g, (ch) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
  })[ch]);
}

function editNode(node) {
  $('nodeId').value = node.id || '';
  $('nodeEnabled').checked = node.enabled !== 'OFF';
  $('nodeName').value = node.name || '';
  $('nodeType').value = node.type || 'shadowsocks';
  $('nodeServer').value = node.server || '';
  $('nodePort').value = node.port || '';
  $('nodeUsername').value = node.username || '';
  $('nodePassword').value = '';
  $('nodeCipher').value = node.cipher || 'aes-128-gcm';
  $('nodeUuid').value = node.uuid || '';
  $('nodeSni').value = node.sni || '';
  $('nodeFlow').value = node.flow || 'xtls-rprx-vision';
  $('nodePublicKey').value = node.publicKey || '';
  $('nodeShortId').value = node.shortId || '';
  $('nodeUseResidential').checked = node.useResidential === 'ON';
  toast('已载入节点，密码留空会保留旧值');
}

function renderNodes(nodes = []) {
  const box = $('nodeList');
  if (!nodes.length) {
    box.innerHTML = '<div class="empty">还没有自建节点。</div>';
    return;
  }
  box.innerHTML = nodes.map((node) => `
    <article class="node-card">
      <div>
        <strong>${h(node.name || '--')}</strong>
        <span>${h(node.type || '--')} ｜ ${h(node.server || '--')}:${h(node.port || '--')}</span>
      </div>
      <div class="node-meta">
        <span>${node.enabled === 'OFF' ? '已停用' : '已启用'}</span>
        <span>${node.useResidential === 'ON' ? '最终出口 IP' : '中转节点，不作为最终出口'}</span>
      </div>
      <div class="node-actions">
        <button data-node-edit="${node.id}">编辑</button>
        <button class="danger" data-node-delete="${node.id}">删除</button>
      </div>
    </article>
  `).join('');
  box.nodes = nodes;
}

async function loadNodes() {
  const data = await nodeRequest('list');
  if (data.ok) renderNodes(data.nodes || []);
}

async function runNodeAction(action) {
  let data;
  if (action === 'save') {
    data = await nodeRequest('save', nodeForm());
    $('nodePassword').value = '';
  } else if (action === 'clear') {
    clearNodeForm();
    return;
  }
  toast(data?.message || '节点操作完成');
  await loadNodes();
}

document.addEventListener('click', async (event) => {
  const action = event.target?.dataset?.nodeAction;
  const editId = event.target?.dataset?.nodeEdit;
  const deleteId = event.target?.dataset?.nodeDelete;
  if (action) runNodeAction(action);
  if (editId) {
    const node = ($('nodeList').nodes || []).find((item) => item.id === editId);
    if (node) editNode(node);
  }
  if (deleteId) {
    const node = ($('nodeList').nodes || []).find((item) => item.id === deleteId);
    if (!confirmAction(`确认删除自建节点“${node?.name || deleteId}”吗？`)) return;
    const data = await nodeRequest('delete', { id: deleteId });
    toast(data.message || '节点已删除');
    await loadNodes();
  }
});

clearNodeForm();
loadNodes();
