const $ = (id) => document.getElementById(id);
const api = '/cgi-bin/api';
const advancedApi = '/cgi-bin/advanced';
let busy = false;
let yamlLoadedFile = '';
let panelUrl = 'http://192.168.31.1:9999/ui/';

function formBody(data) {
  return Object.keys(data).map((key) => (
    encodeURIComponent(key) + '=' + encodeURIComponent(data[key] ?? '')
  )).join('&');
}

async function request(action, data = {}) {
  return post(api, action, data);
}

async function advancedRequest(action, data = {}) {
  return post(advancedApi, action, data);
}

async function post(url, action, data = {}) {
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: formBody({ action, ...data })
  });
  return res.json();
}

function toast(message) {
  const box = $('toast');
  box.textContent = message;
  box.classList.add('show');
  clearTimeout(box.timer);
  box.timer = setTimeout(() => box.classList.remove('show'), 3200);
}

function pill(text, kind) {
  return `<span class="pill ${kind}">${text}</span>`;
}

function renderStatus(data) {
  $('pathLine').textContent = `目录：${data.crashDir || '--'} ｜ 管理页：${data.uiUrl}`;
  $('installDir').value = data.crashDir || $('installDir').value;
  $('directDomains').value = data.rules?.directDomains || '';
  $('proxyDomains').value = data.rules?.proxyDomains || '';
  $('directKeywords').value = data.rules?.directKeywords || '';
  $('proxyKeywords').value = data.rules?.proxyKeywords || '';
  panelUrl = data.panelUrl || panelUrl;
  $('panelPort').value = data.panelPort || $('panelPort').value;
  $('panelPath').value = data.panelPath || $('panelPath').value;
  if (!$('panelFrame').src) $('panelFrame').src = panelUrl;

  $('statusPills').innerHTML = [
    pill(data.installed ? '已安装' : '未安装', data.installed ? 'ok' : 'warn'),
    pill(data.shellcrashRunning ? '运行中' : '未运行', data.shellcrashRunning ? 'ok' : 'bad'),
    pill(data.subscriptionConfigured ? '订阅正常' : '未配置订阅', data.subscriptionConfigured ? 'ok' : 'warn'),
    pill(data.guardActive ? '防泄露开启' : '防泄露未开', data.guardActive ? 'ok' : 'warn'),
    pill((data.residential?.count || 0) > 0 ? `住宅 ${data.residential.count}` : '住宅未配', (data.residential?.count || 0) > 0 ? 'ok' : 'warn')
  ].join('');
}

function showTab(name) {
  // 只显示当前分区，避免所有配置堆在同一个页面里。
  document.querySelectorAll('[data-tab]').forEach((btn) => {
    btn.classList.toggle('active', btn.dataset.tab === name);
  });
  document.querySelectorAll('.tab-panel').forEach((panel) => {
    panel.classList.toggle('active', panel.id === `tab-${name}`);
  });
  if (name === 'yaml' && yamlLoadedFile !== $('yamlFile').value) readYaml(true);
}

function percentText(value) {
  return value === undefined || value === null || value === '' ? '--' : `${value}%`;
}

function mbText(used, total) {
  if (!total) return '--';
  return `${used || 0} / ${total} MB`;
}

function renderSystem(system) {
  if (!system) return;
  $('cpuUsage').textContent = percentText(system.cpuPercent);
  $('memUsage').textContent = percentText(system.memory?.percent);
  $('diskUsage').textContent = percentText(system.disk?.percent);
  $('systemLine').textContent = [
    `负载：${system.loadavg || '--'}`,
    `架构：${system.arch || '--'}`,
    `内存：${mbText(system.memory?.usedMB, system.memory?.totalMB)}`,
    `磁盘：${mbText(system.disk?.usedMB, system.disk?.totalMB)}（${system.disk?.path || '--'}）`
  ].join(' ｜ ');
}

async function refresh() {
  const data = await request('status');
  if (data.ok) renderStatus(data);
}

async function refreshAll() {
  await Promise.all([refresh(), refreshAdvanced()]);
}

async function refreshOverview(showToast = false) {
  await Promise.all([refreshAll(), testExit(false)]);
  if (showToast) toast('总览已刷新');
}

async function refreshSystem(showToast = false) {
  await refreshAll();
  if (showToast) toast('系统资源已刷新');
}

async function showLog(name) {
  const data = await request('log', { name });
  $('logBox').textContent = data.content || '暂无日志';
}

async function loadSubscription() {
  const data = await request('get_subscription');
  if (data.ok) {
    $('subscription').value = data.subscription || '';
    return data;
  } else {
    toast(data.message || '读取订阅失败');
    return data;
  }
}

function onOff(checked) {
  return checked ? 'ON' : 'OFF';
}

function setChecked(id, value) {
  $(id).checked = value === true || value === 'ON';
}

async function refreshAdvanced() {
  const data = await advancedRequest('status');
  if (!data.ok) return;
  const s = data.settings || {};
  const l = data.leak || {};
  renderSystem(data.system);

  $('redirMod').value = s.redirMod || '混合模式';
  $('dnsMod').value = s.dnsMod || 'mix';
  $('firewallArea').value = s.firewallArea || '1';
  $('dnsPort').value = s.dnsPort || '1053';
  $('startDelay').value = s.startDelay || '0';
  setChecked('skipCert', s.skipCert);
  setChecked('sniffer', s.sniffer);
  setChecked('commonPorts', s.commonPorts);
  setChecked('quicReject', s.quicReject);
  setChecked('cnIpRoute', s.cnIpRoute);
  setChecked('startOld', s.startOld);
  setChecked('networkCheck', s.networkCheck || 'ON');

  $('lanIface').value = l.lanIface || 'br-lan';
  setChecked('blockQuic', l.blockQuic);
  setChecked('blockStun', l.blockStun);
  setChecked('blockDot', l.blockDot);
  setChecked('blockIpv6', l.blockIpv6);
  setChecked('excludeChina', l.excludeChina);
}

async function showAdvancedLog() {
  const data = await advancedRequest('log');
  $('taskBox').textContent = data.content || '暂无高级日志';
}

async function loadTasks() {
  const data = await advancedRequest('task_list');
  $('taskBox').textContent = data.content || '暂无任务列表';
}

async function testExit(showToast = false) {
  $('exitIp').textContent = '检测中';
  $('exitLoc').textContent = '--';
  $('exitHttp').textContent = '--';
  $('exitLine').textContent = '正在检测 ChatGPT 请求看到的出口，请稍等。';
  const data = await request('test_exit');
  if (data.ok) {
    $('exitIp').textContent = data.ip || '--';
    $('exitLoc').textContent = data.loc || '--';
    $('exitHttp').textContent = data.http || '--';
    $('exitLine').textContent = '这个结果代表海外网站看到的出口，不是路由器本地地址。';
  } else {
    $('exitIp').textContent = '检测失败';
    $('exitLine').textContent = data.message || '暂时没有拿到出口结果，可以稍后刷新。';
  }
  if (showToast) toast(data.message || (data.ok ? '出口已刷新' : '出口检测失败'));
  return data;
}

function panelForm() {
  return {
    panel_port: $('panelPort').value,
    panel_path: $('panelPath').value,
    external_ui_url: $('externalUi').value
  };
}

function setPanelFrame(url) {
  panelUrl = url || `http://192.168.31.1:${$('panelPort').value || 9999}${$('panelPath').value || '/ui'}/`;
  $('panelFrame').src = panelUrl;
}

async function readYaml(silent = false) {
  $('yamlLine').textContent = '正在读取当前 YAML 文件。';
  const data = await advancedRequest('read_yaml', { file: $('yamlFile').value });
  if (data.ok) {
    yamlLoadedFile = $('yamlFile').value;
    $('yamlContent').value = data.content || '';
    $('yamlContent').readOnly = data.readonly === true;
    updateYamlMode();
    $('yamlLine').textContent = data.readonly
      ? `已读取：${data.path}。这是运行时最终配置，只能查看。`
      : `已读取：${data.path}。保存前请确认 YAML 缩进没有被破坏。`;
    if (!silent) toast(data.readonly ? '已读取只读 YAML' : 'YAML 已读取');
  } else {
    $('yamlLine').textContent = data.message || '读取 YAML 失败。';
    if (!silent) toast(data.message || '读取 YAML 失败');
  }
}

function updateYamlMode() {
  const readonly = $('yamlFile').value === 'merged';
  const saveBtn = document.querySelector('[data-advanced="saveYaml"]');
  $('yamlContent').readOnly = readonly;
  if (saveBtn) {
    saveBtn.disabled = readonly;
    saveBtn.title = readonly ? '运行时合并配置只能查看，不能直接保存' : '';
  }
  if (readonly && !yamlLoadedFile) {
    $('yamlLine').textContent = '运行时合并配置用于查看最终生效结果，只能查看，不能保存。';
  }
}

async function runAdvanced(action) {
  let data;
  if (action === 'saveSettings') {
    data = await advancedRequest('save_settings', {
      redir_mod: $('redirMod').value,
      dns_mod: $('dnsMod').value,
      firewall_area: $('firewallArea').value,
      dns_port: $('dnsPort').value,
      skip_cert: onOff($('skipCert').checked),
      sniffer: onOff($('sniffer').checked),
      common_ports: onOff($('commonPorts').checked),
      quic_rj: onOff($('quicReject').checked),
      cn_ip_route: onOff($('cnIpRoute').checked),
      start_old: onOff($('startOld').checked),
      network_check: onOff($('networkCheck').checked),
      start_delay: $('startDelay').value
    });
  } else if (action === 'saveLeak') {
    data = await advancedRequest('save_leak', {
      block_quic: onOff($('blockQuic').checked),
      block_stun: onOff($('blockStun').checked),
      block_dot: onOff($('blockDot').checked),
      block_ipv6: onOff($('blockIpv6').checked),
      exclude_china: onOff($('excludeChina').checked),
      lan_iface: $('lanIface').value
    });
  } else if (action === 'addTask') {
    data = await advancedRequest('add_task', {
      name: $('taskName').value,
      command: $('taskCommand').value
    });
    await loadTasks();
  } else if (action === 'deleteTask') {
    data = await advancedRequest('delete_task', { id: $('deleteTaskId').value });
    await loadTasks();
  } else if (action === 'runCustomCommand') {
    data = await advancedRequest('run_custom_command', { command: $('taskCommand').value });
    await showAdvancedLog();
  } else if (action === 'taskList') {
    await loadTasks();
    return;
  } else if (action === 'advancedLog') {
    await showAdvancedLog();
    return;
  } else if (action === 'readYaml') {
    await readYaml();
    return;
  } else if (action === 'saveYaml') {
    if ($('yamlFile').value === 'merged') {
      toast('运行时合并配置只能查看，不能直接保存');
      return;
    }
    data = await advancedRequest('save_yaml', {
      file: $('yamlFile').value,
      content: $('yamlContent').value
    });
  }
  toast(data?.message || '操作完成');
  await refreshAdvanced();
}

async function run(action) {
  if (busy) return;
  busy = true;
  document.querySelectorAll('button').forEach((btn) => btn.disabled = true);
  try {
    let data;
    if (action === 'install') {
      data = await request('install_shellcrash', {
        install_url: $('installUrl').value,
        release: $('release').value,
        install_dir: $('installDir').value,
        alias: $('alias').value
      });
      await showLog('install');
    } else if (action === 'saveSubscription') {
      data = await request('save', {
        scope: 'subscription',
        subscription_url: $('subscription').value
      });
    } else if (action === 'saveRules') {
      data = await request('save', {
        scope: 'rules',
        direct_domains: $('directDomains').value,
        proxy_domains: $('proxyDomains').value,
        direct_keywords: $('directKeywords').value,
        proxy_keywords: $('proxyKeywords').value
      });
    } else if (action === 'savePanel') {
      data = await request('save_panel', panelForm());
      if (data.ok) setPanelFrame(data.panelUrl);
    } else if (action === 'installPanel') {
      data = await request('save_panel', panelForm());
      if (!data.ok) throw new Error(data.message || '面板地址保存失败');
      setPanelFrame(data.panelUrl);
      data = await advancedRequest('install_panel', {
        panel_type: $('panelType').value,
        ...panelForm()
      });
    } else if (action === 'refreshPanel') {
      setPanelFrame(panelUrl);
      data = { ok: true, message: '面板已刷新' };
    } else if (action === 'test') {
      data = await testExit(false);
    } else {
      const map = { updateSub: 'update_subscription' };
      data = await request(map[action] || action, action === 'updateSub' ? {
        subscription_url: $('subscription').value
      } : {});
    }
    toast(data.message || (data.ok ? '操作完成' : '操作失败'));
    await refresh();
  } catch (err) {
    toast('请求失败：' + err.message);
  } finally {
    busy = false;
    document.querySelectorAll('button').forEach((btn) => btn.disabled = false);
    updateYamlMode();
  }
}

document.addEventListener('click', (event) => {
  const tab = event.target?.dataset?.tab;
  const action = event.target?.dataset?.action;
  const advanced = event.target?.dataset?.advanced;
  const builtIn = event.target?.dataset?.builtIn;
  if (tab) showTab(tab);
  else if (advanced) runAdvanced(advanced);
  else if (builtIn) {
    advancedRequest('run_builtin', { cmd: builtIn }).then(async (data) => {
      toast(data.message || '命令已执行');
      await showAdvancedLog();
    });
  }
  else if (action === 'refresh') refreshSystem(true);
  else if (action === 'logInstall') showLog('install');
  else if (action === 'logService') showLog('service');
  else if (action) run(action);
});

document.addEventListener('change', (event) => {
  if (event.target?.id === 'yamlFile') {
    yamlLoadedFile = '';
    updateYamlMode();
    readYaml(true);
  }
});

// 页面打开后先拉一次状态，避免用户凭旧信息操作。
updateYamlMode();
refreshOverview();
loadSubscription();
loadTasks();
