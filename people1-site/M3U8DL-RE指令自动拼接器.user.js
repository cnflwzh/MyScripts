// ==UserScript==
// @name         M3U8 DL-RE 指令自动拼接器
// @namespace    http://tampermonkey.net/
// @version      2.3
// @description  专用于 ppppeople1.com，跨域拦截 m3u8 与 Key 并生成下载指令。需要搭配 https://github.com/nilaoda/N_m3u8DL-RE 使用。
// @author       Performance Expert
// @match        *://*/*
// @grant        none
// @run-at       document-start
// @license      MIT
// ==/UserScript==

(function() {
    'use strict';

    // 目标主域名判断
    const IS_MAIN_PAGE = window.location.href.includes('ppppeople1.com/member/contents/');

    let lastM3u8 = '';
    let lastKeyHex = '';
    let currentCommand = '';
    const seenCommands = new Set();

    // --- 1. 界面逻辑：仅在主页面运行 ---
    let copyBtn = null;
    const createButtonOnMainPage = (command) => {
        if (!IS_MAIN_PAGE || window !== window.top) return;

        if (!copyBtn) {
            copyBtn = document.createElement('button');
            copyBtn.style.cssText = `
                position: fixed; bottom: 30px; right: 30px; z-index: 2147483647;
                padding: 14px 24px; background: #e91e63; color: white;
                border: 2px solid #fff; border-radius: 50px; cursor: pointer;
                box-shadow: 0 6px 20px rgba(0,0,0,0.4); font-family: sans-serif;
                font-weight: bold; font-size: 14px; transition: all 0.2s;
            `;

            copyBtn.onclick = () => {
                const textArea = document.createElement("textarea");
                textArea.value = currentCommand;
                document.body.appendChild(textArea);
                textArea.select();
                const success = document.execCommand('copy');
                document.body.removeChild(textArea);

                if (success) {
                    const oldText = copyBtn.innerText;
                    copyBtn.innerText = '✅ 已复制到剪贴板';
                    copyBtn.style.background = '#4caf50';
                    setTimeout(() => {
                        copyBtn.innerText = oldText;
                        copyBtn.style.background = '#e91e63';
                    }, 2000);
                }
            };
            document.body.appendChild(copyBtn);
        }

        currentCommand = command;
        copyBtn.innerText = '📋 复制下载指令';
        copyBtn.style.display = 'block';
    };

    // --- 2. 通信逻辑：处理跨 iframe 数据传递 ---
    if (IS_MAIN_PAGE && window === window.top) {
        // 主页面监听来自 iframe 的指令
        window.addEventListener('message', (event) => {
            if (event.data && event.data.type === 'M3U8_CMD_FOUND') {
                createButtonOnMainPage(event.data.command);
            }
        });
    }

    const broadcastCommand = (command) => {
        // 将指令发送给顶层窗口
        window.top.postMessage({ type: 'M3U8_CMD_FOUND', command: command }, '*');
    };

    // --- 3. 抓取逻辑：在所有窗口（含 iframe）运行 ---
    const isTargetM3U8 = (url) => {
        const pureUrl = url.split('?')[0];
        return pureUrl.endsWith('.m3u8') && url.includes('cloudfront.net') && !url.includes('vms-api');
    };

    const isKeyRequest = (url) => /license|key|drm|auth/i.test(url);

    const bufferToHex = (buffer) => {
        const view = new Uint8Array(buffer);
        return Array.from(view).map(b => b.toString(16).padStart(2, '0')).join('');
    };

    const tryGenerate = () => {
        if (lastM3u8 && lastKeyHex) {
            const command = `.\\N_m3u8DL-RE "${lastM3u8}" --custom-hls-key ${lastKeyHex}`;
            if (!seenCommands.has(command)) {
                console.log('%c[指令生成]:', 'color: #e91e63; font-weight: bold;', command);
                seenCommands.add(command);
                broadcastCommand(command);
            }
        }
    };

    // 拦截 Fetch
    const originalFetch = window.fetch;
    window.fetch = async function(...args) {
        const url = typeof args[0] === 'string' ? args[0] : (args[0].url || '');
        if (isTargetM3U8(url)) lastM3u8 = url;

        const response = await originalFetch.apply(this, args);
        if (isKeyRequest(url)) {
            const clone = response.clone();
            clone.arrayBuffer().then(buffer => {
                lastKeyHex = bufferToHex(buffer);
                tryGenerate();
            }).catch(() => {});
        }
        return response;
    };

    // 拦截 XMLHttpRequest
    const originalOpen = XMLHttpRequest.prototype.open;
    const originalSend = XMLHttpRequest.prototype.send;

    XMLHttpRequest.prototype.open = function(method, url) {
        this._url = url;
        if (isTargetM3U8(url)) lastM3u8 = url;
        return originalOpen.apply(this, arguments);
    };

    XMLHttpRequest.prototype.send = function() {
        this.addEventListener('load', function() {
            if (isKeyRequest(this._url)) {
                const buffer = this.response instanceof ArrayBuffer ? this.response :
                               (new TextEncoder().encode(this.responseText)).buffer;
                if (buffer) {
                    lastKeyHex = bufferToHex(buffer);
                    tryGenerate();
                }
            }
        });
        return originalSend.apply(this, arguments);
    };

})();