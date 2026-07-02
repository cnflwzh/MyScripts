// ==UserScript==
// @name         Fix PEOPLE1 FANCLUB video height issue
// @namespace    https://chatgpt.com/
// @version      1.0.0
// @description  修复 ULIZA 播放器 iframe 高度 100% 导致视频显示不全的问题
// @match        https://ppppeople1.com/*
// @run-at       document-end
// @grant        none
// @license      MIT
// @downloadURL https://update.greasyfork.org/scripts/579266/Fix%20PEOPLE1%20FANCLUB%20video%20height%20issue.user.js
// @updateURL https://update.greasyfork.org/scripts/579266/Fix%20PEOPLE1%20FANCLUB%20video%20height%20issue.meta.js
// ==/UserScript==

(function () {
  'use strict';

  // 视频比例。普通横屏视频一般是 16:9
  const VIDEO_RATIO = 9 / 16;

  // 只处理 ULIZA 播放器 iframe
  const IFRAME_SELECTOR = 'iframe[src*="player-api.p.uliza.jp"]';

  function fixIframe(iframe) {
    if (!iframe) return;

    // 避免重复处理
    iframe.dataset.ulizaHeightFixed = 'true';

    // 移除原本的 height="100%"
    iframe.removeAttribute('height');

    // 基础样式
    iframe.style.display = 'block';
    iframe.style.width = '100%';
    iframe.style.maxWidth = '100%';
    iframe.style.border = 'none';

    // 根据当前宽度计算高度
    function resize() {
      const width = iframe.clientWidth || iframe.parentElement?.clientWidth || 0;

      if (width > 0) {
        const height = Math.round(width * VIDEO_RATIO);
        iframe.style.height = `${height}px`;
        iframe.style.minHeight = `${height}px`;

        // 尽量避免父容器裁切
        const parent = iframe.parentElement;
        if (parent) {
          parent.style.minHeight = `${height}px`;

          const computed = window.getComputedStyle(parent);
          if (computed.overflow === 'hidden' || computed.overflowY === 'hidden') {
            parent.style.overflow = 'visible';
          }
        }
      }
    }

    resize();

    // 窗口大小变化时重新计算
    window.addEventListener('resize', resize);

    // 如果浏览器支持 ResizeObserver，用它监听 iframe 宽度变化
    if ('ResizeObserver' in window) {
      const observer = new ResizeObserver(resize);
      observer.observe(iframe);
      if (iframe.parentElement) observer.observe(iframe.parentElement);
    }

    // 延迟再修几次，防止页面懒加载/脚本后续改样式
    setTimeout(resize, 300);
    setTimeout(resize, 1000);
    setTimeout(resize, 2500);
  }

  function scan() {
    document.querySelectorAll(IFRAME_SELECTOR).forEach(fixIframe);
  }

  // 初始执行
  scan();

  // 监听后续动态插入的 iframe
  const mutationObserver = new MutationObserver(() => {
    scan();
  });

  mutationObserver.observe(document.documentElement, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ['src', 'height', 'style']
  });
})();