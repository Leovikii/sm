// ==UserScript==
// @name         e-hentai Plus
// @name:zh-CN   E-Hentai Plus
// @namespace    http://tampermonkey.net/
// @homepageURL   https://github.com/Leovikii/sm/tree/main/js
// @version      2.1
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
        .settings-btn{position:absolute;left:-50px;top:50%;transform:translateY(-50%);width:36px;height:36px;background:#333;border-radius:50%;display:flex;align-items:center;justify-content:center;cursor:pointer;transition:all 0.3s;opacity:0;pointer-events:none}
        .float-control:hover .settings-btn, .settings-btn:hover, .settings-panel:hover ~ .settings-btn{opacity:1;pointer-events:auto}
        .settings-btn:hover{background:#555;transform:translateY(-50%) scale(1.1)}
        .settings-btn svg{width:18px;height:18px;fill:#fff}
        .settings-panel{position:absolute;left:-210px;top:50%;transform:translateY(-50%) translateX(-10px);background:#1a1a1a;border:1px solid #555;border-radius:8px;padding:12px;min-width:160px;opacity:0;pointer-events:none;transition:all 0.3s;box-shadow:0 4px 12px rgba(0,0,0,0.5)}
        .settings-panel.show{opacity:1;pointer-events:auto;transform:translateY(-50%) translateX(0)}
        .float-control:hover .settings-panel.show, .settings-panel.show:hover{opacity:1;pointer-events:auto}
        .settings-item{display:flex;align-items:center;justify-content:space-between;margin-bottom:8px;font-size:13px;color:#ccc}
        .settings-item:last-child{margin-bottom:0}
        .settings-label{margin-right:10px}
        .toggle-switch{width:40px;height:20px;background:#333;border-radius:10px;position:relative;cursor:pointer;transition:background 0.3s}
        .toggle-switch.on{background:#4CAF50}
        .toggle-slider{width:16px;height:16px;background:#fff;border-radius:50%;position:absolute;top:2px;left:2px;transition:left 0.3s}
        .toggle-switch.on .toggle-slider{left:22px}
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

        circle.appendChild(pageNum);
        circle.appendChild(totalNum);

        circle.onclick = () => {
            if (circle.classList.contains('input-mode')) return;

            circle.classList.add('input-mode');
            circle.innerHTML = '';

            const input = document.createElement('input');
            input.className = 'circle-input';
            input.type = 'number';
            input.value = currPage;
            input.min = 1;
            input.max = totalPage;

            circle.appendChild(input);
            input.focus();
            input.select();

            const exitInput = () => {
                circle.classList.remove('input-mode');
                circle.innerHTML = '';
                pageNum.textContent = currPage;
                totalNum.textContent = `/ ${totalPage}`;
                circle.appendChild(pageNum);
                circle.appendChild(totalNum);
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

        settingsPanel.appendChild(autoScrollItem);
        settingsPanel.appendChild(showControlItem);

        settingsBtn.onclick = (e) => {
            e.stopPropagation();
            settingsPanel.classList.toggle('show');
        };

        document.addEventListener('click', (e) => {
            if (!settingsPanel.contains(e.target) && !settingsBtn.contains(e.target)) {
                settingsPanel.classList.remove('show');
            }
        });

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

})();
