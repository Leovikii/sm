// ==UserScript==
// @name         e-hentai Plus
// @name:zh-CN   E-Hentai Plus
// @namespace    http://tampermonkey.net/
// @homepageURL   https://github.com/Leovikii/sm/tree/main/js
// @version      2.2
// @description       Continuous reading mode with floating page control and ultra-fast loading
// @description:zh-CN E-Hentai 的增强型连续阅读模式，具有高级功能和优化。
// @author       Viki
// @updateURL    https://raw.githubusercontent.com/Leovikii/sm/refs/heads/main/js/e-hentai%20Plus.js
// @downloadURL  https://raw.githubusercontent.com/Leovikii/sm/refs/heads/main/js/e-hentai%20Plus.js
// @match        https://e-hentai.org/g/*
// @match        https://exhentai.org/g/*
// @grant        GM_getValue
// @grant        GM_setValue
// @grant        GM_registerMenuCommand
// @license MIT
// ==/UserScript==

(function () {
    'use strict';

    let autoScroll = GM_getValue('autoScroll', false);
    let showControl = GM_getValue('showControl', true);
    let readMode = GM_getValue('readMode', 'scroll'); // 'scroll' or 'single'
    let autoEnterSinglePage = GM_getValue('autoEnterSinglePage', false);
    let autoPlay = GM_getValue('autoPlay', false);
    let autoPlayInterval = GM_getValue('autoPlayInterval', 3000); // 默认3秒

    const CFG = {
        nextPage: '3000px 0px',
        prefetchDistance: 5000,
        maxRetries: 3,
        retryDelay: 1000
    };

    const style = document.createElement('style');
    style.textContent = `
        html,body{background-color:#111!important;color:#ccc!important;margin:0;overflow-x:hidden}
        #gdt{display:flex;flex-direction:column;align-items:center;width:100%;max-width:1200px;margin:auto;padding-bottom:100px}
        .page-batch{width:100%;display:flex;flex-direction:column;align-items:center;margin-bottom:60px}
        .r-img{display:block;width:auto;max-width:100%;margin-bottom:20px;background:transparent;box-shadow:0 0 20px rgba(0,0,0,0.5)}
        .r-ph{color:#555;margin-bottom:50px;text-align:center;min-height:400px;display:flex;align-items:center;justify-content:center;font-family:sans-serif;font-size:18px;border:1px dashed #333;width:100%;flex-direction:column;gap:10px}
        .r-ph.loading{color:#888;border-color:#555}
        .r-ph.error{color:#d44;border-color:#d44}
        .retry-btn{padding:8px 16px;background:#333;color:#fff;border:none;border-radius:4px;cursor:pointer;font-size:14px;margin-top:10px}
        .retry-btn:hover{background:#555}
        .float-control{position:fixed;right:30px;bottom:30px;z-index:9999;display:flex;flex-direction:column;align-items:center;gap:10px;transition:opacity 0.3s;padding-left:220px}
        .float-control.hidden{opacity:0;pointer-events:none}
        .arrow-up{width:40px;height:40px;background:#333;border-radius:50%;display:flex;align-items:center;justify-content:center;cursor:pointer;transition:all 0.3s;opacity:0;transform:translateY(10px);pointer-events:none}
        .float-control:hover .arrow-up{opacity:1;transform:translateY(0);pointer-events:auto}
        .arrow-up:hover{background:#555;transform:scale(1.1) translateY(0)}
        .arrow-up.disabled{opacity:0.3!important;cursor:not-allowed;pointer-events:none!important}
        .arrow-up svg{width:20px;height:20px;fill:#fff;transform:rotate(-90deg)}
        .circle-control{width:70px;height:70px;background:#1a1a1a;border:2px solid #555;border-radius:50%;display:flex;flex-direction:column;align-items:center;justify-content:center;cursor:pointer;transition:all 0.3s;box-shadow:0 4px 12px rgba(0,0,0,0.5);position:relative}
        .circle-control:hover{border-color:#888;box-shadow:0 6px 16px rgba(0,0,0,0.7);transform:scale(1.05)}
        .circle-page{font-size:18px;font-weight:bold;color:#fff;font-family:monospace;line-height:1}
        .circle-total{font-size:11px;color:#888;font-family:monospace;margin-top:2px}
        .circle-control.input-mode{background:#222}
        .circle-input{width:50px;background:transparent;border:none;color:#fff;text-align:center;font-size:16px;font-family:monospace;outline:none;border-bottom:1px solid #555}
        .circle-input:focus{border-bottom-color:#fff}
        .arrow-down{width:40px;height:40px;background:#333;border-radius:50%;display:flex;align-items:center;justify-content:center;cursor:pointer;transition:all 0.3s;opacity:0;transform:translateY(-10px);pointer-events:none}
        .float-control:hover .arrow-down{opacity:1;transform:translateY(0);pointer-events:auto}
        .arrow-down:hover{background:#555;transform:scale(1.1) translateY(0)}
        .arrow-down.disabled{opacity:0.3!important;cursor:not-allowed;pointer-events:none!important}
        .arrow-down svg{width:20px;height:20px;fill:#fff;transform:rotate(90deg)}
        .reader-btn{position:absolute;left:-50px;top:50%;transform:translateY(-46px);width:36px;height:36px;background:#333;border-radius:50%;display:none;align-items:center;justify-content:center;cursor:pointer;transition:all 0.3s;opacity:0.4}
        .reader-btn.visible{display:flex}
        .float-control:hover .reader-btn{opacity:1}
        .reader-btn:hover{background:#555;transform:translateY(-46px) scale(1.1)}
        .reader-btn svg{width:18px;height:18px;fill:#fff}
        .settings-btn{position:absolute;left:-50px;top:50%;transform:translateY(10px);width:36px;height:36px;background:#333;border-radius:50%;display:flex;align-items:center;justify-content:center;cursor:pointer;transition:all 0.3s;opacity:0;pointer-events:none}
        .float-control:hover .settings-btn, .settings-btn:hover, .settings-panel:hover ~ .settings-btn{opacity:1;pointer-events:auto}
        .settings-btn:hover{background:#555;transform:translateY(10px) scale(1.1)}
        .settings-btn svg{width:18px;height:18px;fill:#fff}
        .settings-panel{position:absolute;left:-210px;top:50%;transform:translateY(-50%) translateX(-10px);background:#1a1a1a;border:1px solid #555;border-radius:8px;padding:12px;min-width:160px;opacity:0;pointer-events:none;transition:all 0.3s;box-shadow:0 4px 12px rgba(0,0,0,0.5)}
        .settings-panel.show{opacity:1;pointer-events:auto;transform:translateY(-50%) translateX(0)}
        .float-control:hover .settings-panel.show, .settings-panel.show:hover{opacity:1;pointer-events:auto}
        .settings-item{display:flex;align-items:center;justify-content:space-between;margin-bottom:8px;font-size:13px;color:#ccc}
        .settings-item:last-child{margin-bottom:0}
        .settings-item.expandable{flex-direction:column;align-items:stretch}
        .settings-item-row{display:flex;align-items:center;justify-content:space-between;width:100%}
        .settings-item-expand{max-height:0;overflow:hidden;transition:max-height 0.3s;margin-top:0}
        .settings-item-expand.show{max-height:50px;margin-top:8px}
        .interval-input{width:60px;background:#333;border:1px solid #555;border-radius:4px;color:#fff;padding:4px 8px;font-size:12px;text-align:center}
        .interval-input:focus{outline:none;border-color:#888}
        .settings-label{margin-right:10px}
        .toggle-switch{width:40px;height:20px;background:#333;border-radius:10px;position:relative;cursor:pointer;transition:background 0.3s}
        .toggle-switch.on{background:#4CAF50}
        .toggle-slider{width:16px;height:16px;background:#fff;border-radius:50%;position:absolute;top:2px;left:2px;transition:left 0.3s}
        .toggle-switch.on .toggle-slider{left:22px}
        .single-page-overlay{position:fixed;top:0;left:0;width:100vw;height:100vh;background:#000;z-index:9998;display:none;align-items:center;justify-content:center}
        .single-page-overlay.active{display:flex}
        .sp-image-container{width:100%;height:100%;display:flex;align-items:center;justify-content:center;position:relative}
        .sp-current-image{max-width:100%;max-height:100%;object-fit:contain;user-select:none}
        .sp-close-btn{position:absolute;top:20px;right:20px;width:40px;height:40px;background:rgba(51,51,51,0.8);border-radius:50%;display:flex;align-items:center;justify-content:center;cursor:pointer;font-size:24px;color:#fff;transition:all 0.3s;z-index:10}
        .sp-close-btn:hover{background:rgba(85,85,85,0.9);transform:scale(1.1)}
        .sp-scrollbar{position:absolute;right:40px;top:10%;width:12px;height:80%;background:rgba(40,40,40,0.3);border-radius:6px;z-index:10;transition:background 0.3s}
        .sp-scrollbar:hover{background:rgba(50,50,50,0.5)}
        .sp-scrollbar-thumb{position:absolute;left:0;width:100%;min-height:60px;background:rgba(255,255,255,0.4);border-radius:6px;transition:background 0.3s;cursor:grab;user-select:none}
        .sp-scrollbar-thumb:hover{background:rgba(255,255,255,0.6)}
        .sp-scrollbar-thumb:active{cursor:grabbing;background:rgba(255,255,255,0.7)}
        .sp-scrollbar-label{position:absolute;right:calc(100% + 16px);top:50%;transform:translateY(-50%);background:rgba(26,26,26,0.95);padding:8px 14px;border-radius:8px;color:#fff;font-family:monospace;font-size:14px;white-space:nowrap;opacity:0;pointer-events:none;transition:opacity 0.3s;box-shadow:0 2px 8px rgba(0,0,0,0.3)}
        .sp-scrollbar:hover .sp-scrollbar-label{opacity:1}
        .sp-loading{color:#888;font-size:18px;font-family:sans-serif}
        .sp-controls{position:absolute;bottom:20px;left:50%;transform:translateX(-50%);display:flex;align-items:center;gap:12px;background:rgba(26,26,26,0.95);padding:12px 20px;border-radius:8px;z-index:10;box-shadow:0 2px 8px rgba(0,0,0,0.3)}
        .sp-play-btn{width:36px;height:36px;background:rgba(51,51,51,0.8);border-radius:50%;display:flex;align-items:center;justify-content:center;cursor:pointer;transition:all 0.3s}
        .sp-play-btn:hover{background:rgba(85,85,85,0.9);transform:scale(1.1)}
        .sp-play-btn svg{width:18px;height:18px;fill:#fff}
        .sp-interval-control{display:flex;align-items:center;gap:8px;font-size:13px;color:#ccc}
        .sp-interval-control .interval-input{width:50px}
    `;
    document.head.appendChild(style);

    const q = (s, d = document) => d.querySelector(s);
    const qa = (s, d = document) => d.querySelectorAll(s);

    ['#nb', '#fb', '#cdiv', '.gt', '.gpc', '.ptt', '#db'].forEach(k => {
        const e = q(k);
        if (e) e.style.display = 'none';
    });

    const mainBox = q('#gdt');
    if (!mainBox) return;

    let currPage = 1;
    let totalPage = 1;
    let nextUrl = null;
    let isFetching = false;
    let nextPagePrefetched = false;
    const parser = new DOMParser();
    const prefetchedUrls = new Set();

    const svgArrow = `<svg viewBox="0 0 24 24"><path d="M10 6L8.59 7.41 13.17 12l-4.58 4.59L10 18l6-6z"/></svg>`;
    const svgSettings = `<svg viewBox="0 0 24 24"><path d="M19.14,12.94c0.04-0.3,0.06-0.61,0.06-0.94c0-0.32-0.02-0.64-0.07-0.94l2.03-1.58c0.18-0.14,0.23-0.41,0.12-0.61 l-1.92-3.32c-0.12-0.22-0.37-0.29-0.59-0.22l-2.39,0.96c-0.5-0.38-1.03-0.7-1.62-0.94L14.4,2.81c-0.04-0.24-0.24-0.41-0.48-0.41 h-3.84c-0.24,0-0.43,0.17-0.47,0.41L9.25,5.35C8.66,5.59,8.12,5.92,7.63,6.29L5.24,5.33c-0.22-0.08-0.47,0-0.59,0.22L2.74,8.87 C2.62,9.08,2.66,9.34,2.86,9.48l2.03,1.58C4.84,11.36,4.8,11.69,4.8,12s0.02,0.64,0.07,0.94l-2.03,1.58 c-0.18,0.14-0.23,0.41-0.12,0.61l1.92,3.32c0.12,0.22,0.37,0.29,0.59,0.22l2.39-0.96c0.5,0.38,1.03,0.7,1.62,0.94l0.36,2.54 c0.05,0.24,0.24,0.41,0.48,0.41h3.84c0.24,0,0.44-0.17,0.47-0.41l0.36-2.54c0.59-0.24,1.13-0.56,1.62-0.94l2.39,0.96 c0.22,0.08,0.47,0,0.59-0.22l1.92-3.32c0.12-0.22,0.07-0.47-0.12-0.61L19.14,12.94z M12,15.6c-1.98,0-3.6-1.62-3.6-3.6 s1.62-3.6,3.6-3.6s3.6,1.62,3.6,3.6S13.98,15.6,12,15.6z"/></svg>`;
    const svgReader = `<svg viewBox="0 0 24 24"><path d="M21 5c-1.11-.35-2.33-.5-3.5-.5-1.95 0-4.05.4-5.5 1.5-1.45-1.1-3.55-1.5-5.5-1.5S2.45 4.9 1 6v14.65c0 .25.25.5.5.5.1 0 .15-.05.25-.05C3.1 20.45 5.05 20 6.5 20c1.95 0 4.05.4 5.5 1.5 1.35-.85 3.8-1.5 5.5-1.5 1.65 0 3.35.3 4.75 1.05.1.05.15.05.25.05.25 0 .5-.25.5-.5V6c-.6-.45-1.25-.75-2-1zm0 13.5c-1.1-.35-2.3-.5-3.5-.5-1.7 0-4.15.65-5.5 1.5V8c1.35-.85 3.8-1.5 5.5-1.5 1.2 0 2.4.15 3.5.5v11.5z"/></svg>`;
    const svgPlay = `<svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg>`;
    const svgPause = `<svg viewBox="0 0 24 24"><path d="M6 4h4v16H6V4zm8 0h4v16h-4V4z"/></svg>`;

    const calcTotal = (doc, fallbackLinkCount) => {
        const gpc = q('.gpc', doc);
        if (gpc) {
            const txt = gpc.textContent;
            const m = txt.match(/of\s+(\d+)\s+images/);
            if (m && m[1]) {
                const totalImgs = parseInt(m[1]);
                const perPage = fallbackLinkCount || 20;
                return Math.ceil(totalImgs / perPage);
            }
        }
        const lastA = Array.from(qa('.ptt td a', doc)).pop();
        if (lastA) {
            const t = parseInt(lastA.innerText);
            if (!isNaN(t)) return t;
        }
        return 1;
    };

    const getNextUrl = (doc) => {
        const ptt = q('.ptt', doc);
        if (!ptt) return null;
        const nextBtn = Array.from(qa('td a', ptt)).find(a => a.innerText.includes('>'));
        return nextBtn ? nextBtn.href : null;
    };

    const jumpTo = (p) => {
        const u = new URL(window.location.href);
        u.searchParams.set('p', p - 1);
        window.location.href = u.toString();
    };

    const loadImageWithRetry = async (url, retries = 0) => {
        try {
            const response = await fetch(url);
            if (!response.ok) throw new Error(`HTTP ${response.status}`);
            const html = await response.text();
            const doc = parser.parseFromString(html, 'text/html');
            const imgSrc = q('#img', doc)?.src;
            if (!imgSrc) throw new Error('Image not found');
            return imgSrc;
        } catch (err) {
            if (retries < CFG.maxRetries) {
                await new Promise(resolve => setTimeout(resolve, CFG.retryDelay));
                return loadImageWithRetry(url, retries + 1);
            }
            return null;
        }
    };

    const createRetryHandler = (url, placeholder, pIndex, index) => {
        return () => {
            placeholder.className = 'r-ph loading';
            placeholder.textContent = `P${pIndex}-${index + 1} Reloading...`;
            loadImageWithRetry(url).then(newSrc => {
                if (newSrc) {
                    const newImg = document.createElement('img');
                    newImg.src = newSrc;
                    newImg.className = 'r-img';
                    placeholder.parentNode?.replaceChild(newImg, placeholder);
                }
            });
        };
    };

    const createFloatControl = () => {
        const container = document.createElement('div');
        container.className = 'float-control';
        if (!showControl) container.classList.add('hidden');

        const arrowUp = document.createElement('div');
        arrowUp.className = 'arrow-up';
        arrowUp.innerHTML = svgArrow;
        arrowUp.onclick = () => {
            if (currPage > 1) jumpTo(currPage - 1);
        };

        const circle = document.createElement('div');
        circle.className = 'circle-control';

        const pageNum = document.createElement('div');
        pageNum.className = 'circle-page';
        pageNum.textContent = currPage;

        const totalNum = document.createElement('div');
        totalNum.className = 'circle-total';
        totalNum.textContent = `/ ${totalPage}`;

        const pageDisplay = document.createElement('div');
        pageDisplay.style.cssText = 'display:flex;flex-direction:column;align-items:center;justify-content:center;';
        pageDisplay.appendChild(pageNum);
        pageDisplay.appendChild(totalNum);

        circle.appendChild(pageDisplay);

        circle.onclick = () => {
            if (circle.classList.contains('input-mode')) return;

            circle.classList.add('input-mode');
            pageDisplay.style.display = 'none';

            const input = document.createElement('input');
            input.className = 'circle-input';
            input.type = 'number';
            input.value = currPage;
            input.min = 1;
            input.max = totalPage;

            circle.insertBefore(input, circle.firstChild);
            input.focus();
            input.select();

            const exitInput = () => {
                circle.classList.remove('input-mode');
                if (input.parentNode) input.remove();
                pageDisplay.style.display = 'flex';
                pageNum.textContent = currPage;
                totalNum.textContent = `/ ${totalPage}`;
            };

            input.onblur = exitInput;
            input.onkeydown = (e) => {
                if (e.key === 'Enter') {
                    const val = parseInt(input.value);
                    if (!isNaN(val) && val > 0 && val <= totalPage) {
                        jumpTo(val);
                    } else {
                        exitInput();
                    }
                } else if (e.key === 'Escape') {
                    exitInput();
                }
            };
        };

        const arrowDown = document.createElement('div');
        arrowDown.className = 'arrow-down';
        arrowDown.innerHTML = svgArrow;
        arrowDown.onclick = () => {
            if (currPage < totalPage) jumpTo(currPage + 1);
        };

        const settingsBtn = document.createElement('div');
        settingsBtn.className = 'settings-btn';
        settingsBtn.innerHTML = svgSettings;

        const readerBtn = document.createElement('div');
        readerBtn.className = 'reader-btn';
        readerBtn.innerHTML = svgReader;
        if (readMode === 'single') readerBtn.classList.add('visible');
        readerBtn.onclick = (e) => {
            e.stopPropagation();
            // 如果已经在单页模式，则退出；否则进入
            if (overlay.classList.contains('active')) {
                closeSinglePageMode();
            } else {
                openSinglePageMode();
            }
        };

        const updateReaderButton = () => {
            if (readMode === 'single') {
                readerBtn.classList.add('visible');
            } else {
                readerBtn.classList.remove('visible');
            }
        };

        const settingsPanel = document.createElement('div');
        settingsPanel.className = 'settings-panel';

        const autoScrollItem = document.createElement('div');
        autoScrollItem.className = 'settings-item';
        autoScrollItem.innerHTML = `
            <span class="settings-label">Auto Scroll</span>
            <div class="toggle-switch ${autoScroll ? 'on' : ''}">
                <div class="toggle-slider"></div>
            </div>
        `;
        const autoScrollToggle = autoScrollItem.querySelector('.toggle-switch');
        autoScrollToggle.onclick = (e) => {
            e.stopPropagation();
            autoScroll = !autoScroll;
            GM_setValue('autoScroll', autoScroll);
            autoScrollToggle.classList.toggle('on');
            if (autoScroll && nextUrl) {
                pageObs.observe(scrollSent);
            } else {
                pageObs.disconnect();
            }
        };

        const showControlItem = document.createElement('div');
        showControlItem.className = 'settings-item';
        showControlItem.innerHTML = `
            <span class="settings-label">Show Control</span>
            <div class="toggle-switch ${showControl ? 'on' : ''}">
                <div class="toggle-slider"></div>
            </div>
        `;
        const showControlToggle = showControlItem.querySelector('.toggle-switch');
        showControlToggle.onclick = (e) => {
            e.stopPropagation();
            showControl = !showControl;
            GM_setValue('showControl', showControl);
            showControlToggle.classList.toggle('on');
            container.classList.toggle('hidden');
        };

        const readModeItem = document.createElement('div');
        readModeItem.className = 'settings-item';
        readModeItem.innerHTML = `
            <span class="settings-label">Read Mode</span>
            <div class="toggle-switch ${readMode === 'single' ? 'on' : ''}">
                <div class="toggle-slider"></div>
            </div>
        `;
        const readModeToggle = readModeItem.querySelector('.toggle-switch');
        readModeToggle.onclick = (e) => {
            e.stopPropagation();
            readMode = readMode === 'scroll' ? 'single' : 'scroll';
            GM_setValue('readMode', readMode);
            readModeToggle.classList.toggle('on');
            updateReaderButton();
        };

        const autoEnterItem = document.createElement('div');
        autoEnterItem.className = 'settings-item';
        autoEnterItem.innerHTML = `
            <span class="settings-label">Auto Enter</span>
            <div class="toggle-switch ${autoEnterSinglePage ? 'on' : ''}">
                <div class="toggle-slider"></div>
            </div>
        `;
        const autoEnterToggle = autoEnterItem.querySelector('.toggle-switch');
        autoEnterToggle.onclick = (e) => {
            e.stopPropagation();
            autoEnterSinglePage = !autoEnterSinglePage;
            GM_setValue('autoEnterSinglePage', autoEnterSinglePage);
            autoEnterToggle.classList.toggle('on');
        };

        settingsPanel.appendChild(autoScrollItem);
        settingsPanel.appendChild(showControlItem);
        settingsPanel.appendChild(readModeItem);
        settingsPanel.appendChild(autoEnterItem);

        settingsBtn.onclick = (e) => {
            e.stopPropagation();
            settingsPanel.classList.toggle('show');
        };

        document.addEventListener('click', (e) => {
            if (!settingsPanel.contains(e.target) && !settingsBtn.contains(e.target)) {
                settingsPanel.classList.remove('show');
            }
        });

        circle.appendChild(readerBtn);
        circle.appendChild(settingsBtn);
        circle.appendChild(settingsPanel);

        container.appendChild(arrowUp);
        container.appendChild(circle);
        container.appendChild(arrowDown);

        document.body.appendChild(container);

        const updateArrows = () => {
            if (currPage <= 1) {
                arrowUp.classList.add('disabled');
            } else {
                arrowUp.classList.remove('disabled');
            }

            if (currPage >= totalPage) {
                arrowDown.classList.add('disabled');
            } else {
                arrowDown.classList.remove('disabled');
            }
        };

        updateArrows();

        return { pageNum, totalNum, updateArrows };
    };

    const processBatch = (links, pIndex) => {
        const batchDiv = document.createElement('div');
        batchDiv.className = 'page-batch';
        const fragment = document.createDocumentFragment();

        let loadedCount = 0;
        const totalCount = links.length;

        links.forEach((url, index) => {
            const placeholder = document.createElement('div');
            placeholder.className = 'r-ph loading';
            placeholder.textContent = `P${pIndex}-${index + 1} Loading...`;
            fragment.appendChild(placeholder);

            loadImageWithRetry(url)
                .then(imgSrc => {
                    if (imgSrc) {
                        const img = document.createElement('img');
                        img.className = 'r-img';

                        img.onerror = () => {
                            if (placeholder.parentNode) {
                                placeholder.className = 'r-ph error';
                                placeholder.innerHTML = `
                                    <div>P${pIndex}-${index + 1} Failed</div>
                                    <button class="retry-btn">Retry</button>
                                `;
                                placeholder.querySelector('.retry-btn').onclick = createRetryHandler(url, placeholder, pIndex, index);
                                placeholder.parentNode.replaceChild(placeholder, img);
                            }
                        };

                        img.onload = () => {
                            loadedCount++;
                            if (loadedCount % 5 === 0 || loadedCount === totalCount) {
                                console.log(`[✓] P${pIndex} Loaded ${loadedCount}/${totalCount}`);
                            }
                        };

                        img.src = imgSrc;
                        placeholder.parentNode?.replaceChild(img, placeholder);
                    } else {
                        placeholder.className = 'r-ph error';
                        placeholder.innerHTML = `
                            <div>P${pIndex}-${index + 1} Failed</div>
                            <button class="retry-btn">Retry</button>
                        `;
                        placeholder.querySelector('.retry-btn').onclick = createRetryHandler(url, placeholder, pIndex, index);
                    }
                })
                .catch(() => {
                    placeholder.className = 'r-ph error';
                    placeholder.textContent = `P${pIndex}-${index + 1} Network Error`;
                });
        });

        batchDiv.appendChild(fragment);
        mainBox.appendChild(batchDiv);
    };

    const urlP = new URLSearchParams(window.location.search).get('p');
    currPage = urlP ? parseInt(urlP) + 1 : 1;

    const initLinks = Array.from(qa('#gdt a', document)).map(a => a.href);

    const galleryId = window.location.pathname;
    const savedTotal = localStorage.getItem(`eh_total_${galleryId}`);

    if (savedTotal && parseInt(savedTotal) > 0) {
        totalPage = parseInt(savedTotal);
    } else {
        totalPage = calcTotal(document, initLinks.length);
        localStorage.setItem(`eh_total_${galleryId}`, totalPage);
    }

    nextUrl = getNextUrl(document);

    mainBox.innerHTML = '';

    console.log(`[Fast Load] Starting to load ${initLinks.length} images`);
    processBatch(initLinks, currPage);

    const floatControl = createFloatControl();

    const scrollSent = document.createElement('div');
    document.body.appendChild(scrollSent);

    const pageObs = new IntersectionObserver((entries) => {
        if (entries[0].isIntersecting && nextUrl && !isFetching && autoScroll) {
            isFetching = true;
            fetch(nextUrl).then(r => r.text()).then(html => {
                const doc = parser.parseFromString(html, 'text/html');
                const links = Array.from(qa('#gdt a', doc)).map(a => a.href);
                const nUrl = getNextUrl(doc);

                currPage++;
                processBatch(links, currPage);

                floatControl.pageNum.textContent = currPage;
                floatControl.updateArrows();

                nextUrl = nUrl;
                isFetching = false;
                nextPagePrefetched = false;
                if (!nextUrl) pageObs.disconnect();
            }).catch(() => isFetching = false);
        }
    }, { rootMargin: CFG.nextPage });

    if (autoScroll) {
        pageObs.observe(scrollSent);
    }

    const prefetchNextPage = () => {
        if (!nextUrl || nextPagePrefetched || prefetchedUrls.has(nextUrl)) return;

        const scrollTop = window.pageYOffset || document.documentElement.scrollTop;
        const windowHeight = window.innerHeight;
        const documentHeight = document.documentElement.scrollHeight;
        const distanceToBottom = documentHeight - (scrollTop + windowHeight);

        if (distanceToBottom < CFG.prefetchDistance) {
            nextPagePrefetched = true;
            prefetchedUrls.add(nextUrl);
            console.log(`[Prefetch] ${distanceToBottom}px to bottom, prefetching next page`);

            fetch(nextUrl).then(r => r.text()).then(html => {
                const doc = parser.parseFromString(html, 'text/html');
                const links = Array.from(qa('#gdt a', doc)).map(a => a.href);

                console.log(`[Prefetch] Found ${links.length} images, loading in parallel`);

                let prefetchedCount = 0;
                links.forEach((url) => {
                    loadImageWithRetry(url).then(imgSrc => {
                        if (imgSrc) {
                            const preloadImg = new Image();
                            preloadImg.onload = () => {
                                prefetchedCount++;
                                if (prefetchedCount % 5 === 0 || prefetchedCount === links.length) {
                                    console.log(`[Prefetch✓] ${prefetchedCount}/${links.length}`);
                                }
                            };
                            preloadImg.src = imgSrc;
                        }
                    }).catch(() => null);
                });
            }).catch((err) => {
                console.error('[Prefetch Failed]', err);
                nextPagePrefetched = false;
                prefetchedUrls.delete(nextUrl);
            });
        }
    };

    let scrollTimer;
    window.addEventListener('scroll', () => {
        clearTimeout(scrollTimer);
        scrollTimer = setTimeout(prefetchNextPage, 200);
    }, { passive: true });

    // Single Page Mode
    let currentImageIndex = 0;
    let allImages = [];
    let autoPlayTimer = null;
    const overlay = document.createElement('div');
    overlay.className = 'single-page-overlay';

    const closeBtn = document.createElement('div');
    closeBtn.className = 'sp-close-btn';
    closeBtn.innerHTML = '✕';

    const pageIndicator = document.createElement('div');
    pageIndicator.className = 'sp-scrollbar';

    const scrollbarThumb = document.createElement('div');
    scrollbarThumb.className = 'sp-scrollbar-thumb';

    const scrollbarLabel = document.createElement('div');
    scrollbarLabel.className = 'sp-scrollbar-label';

    pageIndicator.appendChild(scrollbarThumb);
    pageIndicator.appendChild(scrollbarLabel);

    const imageContainer = document.createElement('div');
    imageContainer.className = 'sp-image-container';

    const currentImage = document.createElement('img');
    currentImage.className = 'sp-current-image';

    imageContainer.appendChild(currentImage);

    // 创建底部控制栏
    const controlsBar = document.createElement('div');
    controlsBar.className = 'sp-controls';

    const playBtn = document.createElement('div');
    playBtn.className = 'sp-play-btn';
    playBtn.innerHTML = svgPlay;

    const intervalControl = document.createElement('div');
    intervalControl.className = 'sp-interval-control';
    intervalControl.innerHTML = `
        <span>Interval:</span>
        <input type="number" class="interval-input" min="1" max="60" step="0.5" value="${autoPlayInterval / 1000}" />
        <span>s</span>
    `;

    const intervalInput = intervalControl.querySelector('.interval-input');
    intervalInput.onclick = (e) => e.stopPropagation();
    intervalInput.onchange = (e) => {
        const value = parseFloat(e.target.value);
        if (!isNaN(value) && value >= 1 && value <= 60) {
            autoPlayInterval = value * 1000;
            GM_setValue('autoPlayInterval', autoPlayInterval);
            // 如果正在播放，重启定时器以应用新间隔
            if (autoPlay) {
                stopAutoPlay();
                startAutoPlay();
            }
        }
    };

    controlsBar.appendChild(playBtn);
    controlsBar.appendChild(intervalControl);

    overlay.appendChild(closeBtn);
    overlay.appendChild(pageIndicator);
    overlay.appendChild(imageContainer);
    overlay.appendChild(controlsBar);
    document.body.appendChild(overlay);

    const updateSinglePageImage = () => {
        const img = allImages[currentImageIndex];
        if (img && img.src && !img.src.includes('data:')) {
            currentImage.src = img.src;
            updateScrollbar();
        } else {
            currentImage.src = '';
            const loading = document.createElement('div');
            loading.className = 'sp-loading';
            loading.textContent = 'Loading...';
            imageContainer.innerHTML = '';
            imageContainer.appendChild(loading);

            setTimeout(() => {
                const img = allImages[currentImageIndex];
                if (img && img.src && !img.src.includes('data:')) {
                    imageContainer.innerHTML = '';
                    currentImage.src = img.src;
                    imageContainer.appendChild(currentImage);
                    updateScrollbar();
                }
            }, 500);
        }
    };

    const updateScrollbar = () => {
        if (allImages.length === 0) return;

        // 计算滑块高度：根据图片数量动态调整
        // 使用更合理的比例，让滑块在少量图片时也不会太长
        const trackHeight = pageIndicator.offsetHeight;
        let thumbHeight;

        if (allImages.length <= 10) {
            // 10张以内：固定最小高度
            thumbHeight = 60;
        } else if (allImages.length <= 50) {
            // 10-50张：线性缩小
            thumbHeight = Math.max(60, trackHeight * (10 / allImages.length));
        } else {
            // 50张以上：更小的比例
            thumbHeight = Math.max(60, trackHeight * (5 / allImages.length));
        }

        // 计算滑块位置：确保第一张图片时滑块在顶部，最后一张在底部
        const scrollProgress = currentImageIndex / Math.max(1, allImages.length - 1);
        const maxThumbTop = trackHeight - thumbHeight;
        const thumbTop = scrollProgress * maxThumbTop;

        scrollbarThumb.style.height = `${thumbHeight}px`;
        scrollbarThumb.style.top = `${thumbTop}px`;
        scrollbarLabel.textContent = `${currentImageIndex + 1} / ${allImages.length}`;
    };

    const nextImage = () => {
        if (currentImageIndex < allImages.length - 1) {
            // 检查下一张图片是否已加载
            const nextImg = allImages[currentImageIndex + 1];
            if (nextImg && (!nextImg.src || nextImg.src.includes('data:'))) {
                // 图片未加载完成，显示提示但不切换
                console.log('[Single Page] Next image not loaded yet, waiting...');
                return;
            }

            currentImageIndex++;
            updateSinglePageImage();

            // 检查是否需要自动加载下一页（接近末尾时）
            checkAndLoadNextPage();
        } else {
            // 到达最后一张图片时停止自动播放
            if (autoPlay) {
                autoPlay = false;
                GM_setValue('autoPlay', false);
                stopAutoPlay();
                playBtn.innerHTML = svgPlay;
                console.log('[Auto Play] Reached last image, stopped');
            }
        }
    };

    const previousImage = () => {
        if (currentImageIndex > 0) {
            currentImageIndex--;
            updateSinglePageImage();
            // 用户手动操作时重置自动播放
            if (autoPlay) {
                stopAutoPlay();
                startAutoPlay();
            }
        }
    };

    // 单页模式下检查并自动加载下一页
    const checkAndLoadNextPage = () => {
        if (!autoScroll || !nextUrl || isFetching) return;

        // 当浏览到倒数第10张图片时，提前自动加载下一页
        const remainingImages = allImages.length - currentImageIndex;
        if (remainingImages <= 10) {
            console.log(`[Single Page] Near end (${remainingImages} remaining), loading next page`);

            isFetching = true;
            fetch(nextUrl).then(r => r.text()).then(html => {
                const doc = parser.parseFromString(html, 'text/html');
                const links = Array.from(qa('#gdt a', doc)).map(a => a.href);
                const nUrl = getNextUrl(doc);

                currPage++;
                processBatch(links, currPage);

                // 更新滚动模式的控制器
                floatControl.pageNum.textContent = currPage;
                floatControl.updateArrows();

                // 实时更新图片列表，不需要延迟
                // 使用 MutationObserver 监听新图片的添加
                const updateImageList = () => {
                    const newImages = Array.from(qa('.r-img'));
                    if (newImages.length > allImages.length) {
                        allImages = newImages;
                        updateScrollbar();
                        console.log(`[Single Page] Updated image list, now ${allImages.length} images`);
                    }
                };

                // 立即更新一次
                setTimeout(updateImageList, 500);
                // 再次更新确保完整
                setTimeout(updateImageList, 1500);

                nextUrl = nUrl;
                isFetching = false;
                nextPagePrefetched = false;
                if (!nextUrl) {
                    console.log('[Single Page] No more pages to load');
                }
            }).catch((err) => {
                console.error('[Single Page] Load failed', err);
                isFetching = false;
            });
        }
    };

    const startAutoPlay = () => {
        if (autoPlayTimer) {
            clearInterval(autoPlayTimer);
        }
        if (autoPlay) {
            autoPlayTimer = setInterval(() => {
                nextImage();
            }, autoPlayInterval);
            console.log(`[Auto Play] Started with ${autoPlayInterval}ms interval`);
        }
    };

    const stopAutoPlay = () => {
        if (autoPlayTimer) {
            clearInterval(autoPlayTimer);
            autoPlayTimer = null;
            console.log('[Auto Play] Stopped');
        }
    };

    // 播放按钮点击事件
    playBtn.onclick = (e) => {
        e.stopPropagation();
        autoPlay = !autoPlay;
        GM_setValue('autoPlay', autoPlay);

        if (autoPlay) {
            playBtn.innerHTML = svgPause;
            startAutoPlay();
        } else {
            playBtn.innerHTML = svgPlay;
            stopAutoPlay();
        }
    };

    const openSinglePageMode = () => {
        allImages = Array.from(qa('.r-img'));
        if (allImages.length === 0) {
            alert('Please wait for images to load');
            return;
        }

        // 查找视口中心最近的图片（性能优化：只检查视口附近）
        const viewportCenter = window.scrollY + window.innerHeight / 2;
        const searchRange = window.innerHeight * 2; // 搜索范围：上下各1屏

        let closestIndex = 0;
        let minDistance = Infinity;

        allImages.forEach((img, index) => {
            const rect = img.getBoundingClientRect();
            const imgTop = rect.top + window.scrollY;

            // 只检查视口附近的图片，避免遍历所有图片
            if (Math.abs(imgTop - viewportCenter) < searchRange) {
                const imgCenter = imgTop + rect.height / 2;
                const distance = Math.abs(imgCenter - viewportCenter);

                if (distance < minDistance) {
                    minDistance = distance;
                    closestIndex = index;
                }
            }
        });

        currentImageIndex = closestIndex;
        overlay.classList.add('active');
        document.body.style.overflow = 'hidden';
        updateSinglePageImage();

        // 根据autoPlay状态设置按钮图标
        if (autoPlay) {
            playBtn.innerHTML = svgPause;
            startAutoPlay();
        } else {
            playBtn.innerHTML = svgPlay;
        }
    };

    const closeSinglePageMode = () => {
        stopAutoPlay();
        overlay.classList.remove('active');
        document.body.style.overflow = '';

        // 退出时滚动到当前查看的图片位置
        // 重新获取图片列表（自动翻页可能已增加图片）
        const currentImages = Array.from(qa('.r-img'));

        // 验证索引有效性
        if (currentImageIndex >= 0 && currentImageIndex < currentImages.length) {
            const targetImg = currentImages[currentImageIndex];
            if (targetImg) {
                // 延迟执行，确保 overlay 已完全关闭，避免滚动冲突
                setTimeout(() => {
                    targetImg.scrollIntoView({
                        behavior: 'smooth',
                        block: 'center'
                    });
                }, 100);
            }
        }
    };

    closeBtn.onclick = () => {
        closeSinglePageMode();
    };

    pageIndicator.onclick = (e) => {
        if (e.target === scrollbarThumb) return;

        const rect = pageIndicator.getBoundingClientRect();
        const clickY = e.clientY - rect.top;
        const trackHeight = rect.height;

        // 计算点击位置对应的图片索引
        const scrollProgress = Math.min(1, Math.max(0, clickY / trackHeight));
        const targetIndex = Math.round(scrollProgress * (allImages.length - 1));

        if (targetIndex >= 0 && targetIndex < allImages.length) {
            currentImageIndex = targetIndex;
            updateSinglePageImage();
            // 用户手动操作时重置自动播放
            if (autoPlay) {
                stopAutoPlay();
                startAutoPlay();
            }
        }
    };

    // 拖动功能
    let isDragging = false;
    let dragStartY = 0;
    let thumbStartTop = 0;

    scrollbarThumb.onmousedown = (e) => {
        e.preventDefault();
        e.stopPropagation();
        isDragging = true;
        dragStartY = e.clientY;
        thumbStartTop = scrollbarThumb.offsetTop;
        document.body.style.userSelect = 'none';
    };

    document.addEventListener('mousemove', (e) => {
        if (!isDragging) return;

        const deltaY = e.clientY - dragStartY;
        const newTop = thumbStartTop + deltaY;
        const trackHeight = pageIndicator.offsetHeight;
        const thumbHeight = scrollbarThumb.offsetHeight;
        const maxTop = trackHeight - thumbHeight;

        // 限制滑块在轨道范围内
        const clampedTop = Math.max(0, Math.min(maxTop, newTop));
        const scrollProgress = maxTop > 0 ? clampedTop / maxTop : 0;
        const targetIndex = Math.round(scrollProgress * (allImages.length - 1));

        if (targetIndex >= 0 && targetIndex < allImages.length && targetIndex !== currentImageIndex) {
            currentImageIndex = targetIndex;
            updateSinglePageImage();
        }
    });

    document.addEventListener('mouseup', () => {
        if (isDragging) {
            isDragging = false;
            document.body.style.userSelect = '';
            // 拖动结束时重置自动播放
            if (autoPlay) {
                stopAutoPlay();
                startAutoPlay();
            }
        }
    });

    scrollbarThumb.onclick = (e) => {
        e.stopPropagation();
    };

    let wheelTimeout;
    let wheelDelta = 0;
    let isScrolling = false;

    overlay.addEventListener('wheel', (e) => {
        e.preventDefault();
        wheelDelta += e.deltaY;

        if (!isScrolling) {
            isScrolling = true;
            processWheelScroll();
        }

        clearTimeout(wheelTimeout);
        wheelTimeout = setTimeout(() => {
            isScrolling = false;
            wheelDelta = 0;
        }, 150);
    }, { passive: false });

    const processWheelScroll = () => {
        if (!isScrolling) return;

        const threshold = 100;
        if (Math.abs(wheelDelta) >= threshold) {
            if (wheelDelta > 0) {
                nextImage();
            } else {
                previousImage();
            }
            wheelDelta = wheelDelta > 0 ? wheelDelta - threshold : wheelDelta + threshold;
        }

        if (isScrolling) {
            requestAnimationFrame(processWheelScroll);
        }
    };

    document.addEventListener('keydown', (e) => {
        if (!overlay.classList.contains('active')) return;
        if (e.key === 'Escape') {
            closeSinglePageMode();
        } else if (e.key === 'ArrowDown' || e.key === 'ArrowRight') {
            nextImage();
        } else if (e.key === 'ArrowUp' || e.key === 'ArrowLeft') {
            previousImage();
        }
    });

    if (readMode === 'single' && autoEnterSinglePage) {
        setTimeout(() => openSinglePageMode(), 1000);
    }

    GM_registerMenuCommand('Toggle Auto Scroll', () => {
        autoScroll = !autoScroll;
        GM_setValue('autoScroll', autoScroll);
        alert(`Auto Scroll ${autoScroll ? 'Enabled' : 'Disabled'}`);
        location.reload();
    });

    GM_registerMenuCommand('Toggle Control Display', () => {
        showControl = !showControl;
        GM_setValue('showControl', showControl);
        alert(`Control Display ${showControl ? 'Enabled' : 'Disabled'}`);
        location.reload();
    });

    GM_registerMenuCommand('Toggle Read Mode', () => {
        readMode = readMode === 'scroll' ? 'single' : 'scroll';
        GM_setValue('readMode', readMode);
        alert(`Read Mode: ${readMode === 'single' ? 'Single Page' : 'Scroll'}`);
        location.reload();
    });

    GM_registerMenuCommand('Toggle Auto Enter Single Page', () => {
        autoEnterSinglePage = !autoEnterSinglePage;
        GM_setValue('autoEnterSinglePage', autoEnterSinglePage);
        alert(`Auto Enter Single Page ${autoEnterSinglePage ? 'Enabled' : 'Disabled'}`);
        location.reload();
    });

})();
