#!/usr/bin/env python3
import os, sys, time, threading, http.server, socketserver
from playwright.sync_api import sync_playwright

PORT = 8912
webroot = os.path.abspath('module/webroot')
screenshots_dir = os.path.abspath('screenshots')
os.makedirs(screenshots_dir, exist_ok=True)

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=webroot, **kwargs)

class ReusableTCPServer(socketserver.TCPServer):
    allow_reuse_address = True

httpd = ReusableTCPServer(('127.0.0.1', PORT), Handler)
t = threading.Thread(target=httpd.serve_forever, daemon=True)
t.start()

mock_js = """
window.ksu = {
  exec: function(cmd, opts, cb) {
    var out = '';
    if (cmd.indexOf('pid_attest') !== -1) {
      out = 'pid_attest=2418\\ndeny_cnt=12\\nhma_status=1\\nhma_mod=0\\nhma_cfg=1\\nhidden_cnt=6\\ntarget_cnt=8\\nspoof_model=Pixel 6a\\nselinux=Enforcing';
    } else if (cmd.indexOf('description=') !== -1) {
      out = 'Strong Play Integrity in one drop-in module. TEE-Simulator-RS + PlayIntegrityFork, auto-refreshed.';
    } else if (cmd.indexOf('keybox.xml') !== -1) {
      out = '16384|evokerrkey36';
    } else if (cmd.indexOf('pif_name') !== -1) {
      out = 'n=Pixel 6a\\nm=bluejay';
    } else if (cmd.indexOf('SECURITY_PATCH') !== -1) {
      out = '2026-11-05';
    } else if (cmd.indexOf('hidden_apps') !== -1) {
      out = 'com.topjohnwu.magisk\\nme.weishu.kernelsu\\norg.lsposed.manager\\nio.github.vvb2060.magisk\\nbin.mt.plus\\ncom.termux';
    } else if (cmd.indexOf('target.txt') !== -1) {
      out = 'com.google.android.gms\\ncom.android.vending\\ncom.google.android.apps.walletnfcrel\\ncom.snapchat.android\\ncom.zhiliaoapp.musically\\ncom.paytm.app';
    } else if (cmd.indexOf('config') !== -1 || cmd.indexOf('STORE get') !== -1) {
      out = 'auto_fp=1\\nauto_kb=1\\nstatus_pfx=1\\ninterval_sec=3600';
    } else if (cmd.indexOf('pm list packages') !== -1) {
      out = 'com.topjohnwu.magisk\\nme.weishu.kernelsu\\norg.lsposed.manager\\nio.github.vvb2060.magisk\\nbin.mt.plus\\ncom.termux\\ncom.google.android.gms\\ncom.android.vending\\ncom.google.android.apps.walletnfcrel\\ncom.snapchat.android\\ncom.paytm.app';
    }
    setTimeout(function() {
      if (window[cb]) window[cb](0, out, '');
    }, 10);
  },
  getPackagesInfo: function(jsonStr) {
    var pkgs = JSON.parse(jsonStr || '[]');
    var map = {
      'com.topjohnwu.magisk': 'Magisk',
      'me.weishu.kernelsu': 'KernelSU',
      'org.lsposed.manager': 'LSPosed',
      'io.github.vvb2060.magisk': 'Alpha Magisk',
      'bin.mt.plus': 'MT Manager',
      'com.termux': 'Termux',
      'com.google.android.gms': 'Google Play Services',
      'com.android.vending': 'Google Play Store',
      'com.google.android.apps.walletnfcrel': 'Google Wallet',
      'com.snapchat.android': 'Snapchat',
      'com.paytm.app': 'Paytm'
    };
    var res = pkgs.map(function(p) {
      return { packageName: p, appLabel: map[p] || p };
    });
    return JSON.stringify(res);
  }
};
"""

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    
    # 1. Main Configuration WebUI Screenshot
    context = browser.new_context(
        viewport={'width': 412, 'height': 846},
        device_scale_factor=2.621359,
        color_scheme='dark'
    )
    context.add_init_script(mock_js)
    page = context.new_page()
    page.goto(f'http://127.0.0.1:{PORT}/index.html')
    time.sleep(1.2)
    webui_path = os.path.join(screenshots_dir, 'webui.jpg')
    page.screenshot(path=webui_path, type='jpeg', quality=95)
    print(f'Generated: {webui_path}')

    # 2. Advanced Tab Screenshot
    page.click('button[data-pg="pgAdv"]')
    time.sleep(0.5)
    adv_path = os.path.join(screenshots_dir, 'advanced.jpg')
    page.screenshot(path=adv_path, type='jpeg', quality=95)
    print(f'Generated: {adv_path}')

    # 3. Languages Modal Screenshot
    page.click('button[data-pg="pgMain"]')
    time.sleep(0.3)
    page.click('#langBtn')
    time.sleep(0.5)
    lang_path = os.path.join(screenshots_dir, 'languages.jpg')
    page.screenshot(path=lang_path, type='jpeg', quality=95)
    print(f'Generated: {lang_path}')

    # 4. App Isolation (Zero-APK HMA) Modal Screenshot
    page.reload()
    time.sleep(1.0)
    page.click('#hideRow')
    time.sleep(0.8)
    isolation_path = os.path.join(screenshots_dir, 'app_isolation.jpg')
    page.screenshot(path=isolation_path, type='jpeg', quality=95)
    print(f'Generated: {isolation_path}')

    browser.close()

httpd.shutdown()
print('All screenshots generated successfully!')
