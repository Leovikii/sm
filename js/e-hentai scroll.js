// ==UserScript==
// @name         e-hentai scroll
// @namespace    http://tampermonkey.net/
// @version      1.0
// @description  在 e-hentai 上启用连续阅读模式，并强制启用黑色主题。
// @author       Viki
// @match        https://e-hentai.org/g/*
// @match        https://exhentai.org/g/*
// @grant        none
// @downloadURL https://update.sleazyfork.org/scripts/528012/e-hentai%20%E8%BF%9E%E7%BB%AD%E9%98%85%E8%AF%BB%E6%A8%A1%E5%BC%8F%EF%BC%88%E9%BB%91%E8%89%B2%E4%B8%BB%E9%A2%98%EF%BC%89.user.js
// @updateURL https://update.sleazyfork.org/scripts/528012/e-hentai%20%E8%BF%9E%E7%BB%AD%E9%98%85%E8%AF%BB%E6%A8%A1%E5%BC%8F%EF%BC%88%E9%BB%91%E8%89%B2%E4%B8%BB%E9%A2%98%EF%BC%89.meta.js
// ==/UserScript==

(function () {
    'use strict';
    const s = document.createElement('style');
    s.textContent = 'html,body{background-color:#000!important;color:#fff!important;margin:0}#gdt{display:flex;flex-direction:column;align-items:center;width:100%;max-width:1200px;margin:auto}.r-img{display:block;width:auto;max-width:100%;margin-bottom:20px;background:transparent;box-shadow:0 0 20px rgba(255,255,255,0.2);min-height:500px}.r-ph{color:#fff;margin-bottom:50px;text-align:center;height:300px;display:flex;align-items:center;justify-content:center;font-family:sans-serif;font-size:18px;color:#888}';
    document.head.appendChild(s);
    const q = (sel) => document.querySelector(sel);
    const qa = (sel) => document.querySelectorAll(sel);
    ['#nb', '#fb', '#cdiv', '.gt', '.gpc'].forEach(id => {
        const e = q(id);
        if (e) e.style.display = 'none';
    });
    const c = q('#gdt');
    if (!c) return;
    const ls = Array.from(qa('#gdt a')).map(a => a.href);
    c.innerHTML = '';
    const obs = new IntersectionObserver((es, o) => {
        es.forEach(e => {
            if (e.isIntersecting) {
                const t = e.target;
                o.unobserve(t);
                fetch(t.dataset.url).then(r => r.text()).then(h => {
                    const d = new DOMParser().parseFromString(h, 'text/html');
                    const i = d.querySelector('#img');
                    if (i) {
                        const n = document.createElement('img');
                        n.src = i.src;
                        n.className = 'r-img';
                        c.replaceChild(n, t);
                    } else {
                        t.textContent = 'Error';
                    }
                }).catch(() => t.textContent = 'Error');
            }
        });
    }, { rootMargin: '800px 0px' });
    ls.forEach((u, i) => {
        const d = document.createElement('div');
        d.className = 'r-ph';
        d.textContent = (i + 1);
        d.dataset.url = u;
        c.appendChild(d);
        obs.observe(d);
    });
})();