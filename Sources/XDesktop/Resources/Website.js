(() => {
  'use strict';
  if (window.__xDesktop) return;
  let lastMessage = '';
  let dirty = true;
  let desiredFeed = null;
  let restoreAttempted = false;
  let lastScroll = 0;
  const activelyWatched = new WeakSet();
  let pointer = { x: innerWidth / 2, y: innerHeight / 2 };
  const visible = element => !!element && element.getClientRects().length > 0;
  const all = (selector, root = document) => Array.from(root.querySelectorAll(selector));
  const editorSelector = '[contenteditable="true"],textarea';

  function state() {
    const home = location.pathname === '/home' || (location.protocol === 'file:' && location.pathname.endsWith('/home.html') && document.documentElement.dataset.xDesktopFixture === 'true');
    const main = document.querySelector('[data-testid="primaryColumn"]') || document.querySelector('main');
    const feedTabs = main?.querySelector('[role="tablist"]');
    const tabs = feedTabs ? all('[role="tab"]', feedTabs).filter(visible) : [];
    const selected = tabs.findIndex(tab => tab.getAttribute('aria-selected') === 'true');
    const recognized = home && tabs.length >= 2 && selected >= 0 && selected < 2;
    const modal = all('[role="dialog"],[aria-modal="true"]').some(visible);
    const editorFocused = document.activeElement?.matches(editorSelector) || false;
    const draft = all(editorSelector).some(element => visible(element) &&
      ((element.value || element.textContent || '').trim().length > 0));
    const attachedFile = all('input[type="file"]').some(element => element.files?.length > 0);
    const typing = editorFocused || draft || attachedFile;
    const playing = all('video,audio').some(element => !element.paused && !element.ended && (
      element.tagName === 'AUDIO' || (!element.muted && element.volume > 0) ||
      activelyWatched.has(element) || element.webkitDisplayingFullscreen ||
      document.fullscreenElement?.contains(element)));
    const failed = all('[data-testid="error-detail"],[data-testid="retry"]', main || document).some(visible);
    // A skeleton or busy region is not a completed feed. No post content leaves this world.
    const busy = main && all('[role="progressbar"],[aria-busy="true"]', main).some(visible);
    const contentLoaded = main && !!main.querySelector('article,[data-testid="emptyState"]');
    const ready = recognized && (contentLoaded || !busy) && !failed;

    if (recognized && desiredFeed !== null && desiredFeed !== selected && !restoreAttempted && !typing && !modal) {
      restoreAttempted = true;
      tabs[desiredFeed]?.click();
      dirty = true;
      return null;
    }
    const restored = desiredFeed === null || selected === desiredFeed;
    if (restored) desiredFeed = null;

    // Check the container beneath the pointer and its scrolling ancestors. This also
    // prevents pulls in nested scrollable content from refreshing the outer feed.
    const target = document.elementFromPoint(pointer.x, pointer.y);
    let inTimeline = !!main && !!target && main.contains(target);
    let atTop = true;
    for (let node = target; node instanceof Element; node = node.parentElement) {
      const style = getComputedStyle(node);
      if (/(auto|scroll)/.test(style.overflowY) && node.scrollHeight > node.clientHeight + 1) {
        if (node.scrollTop > 1) atTop = false;
      }
    }
    const scrollRoot = document.scrollingElement;
    if (scrollRoot && scrollRoot.scrollTop > 1) atTop = false;
    return { home, recognized, ready: !!ready && restored, selected: recognized ? selected : -1,
      atTop: atTop && inTimeline, protected: typing || playing || modal,
      reason: typing ? 'Finish composing' : playing ? 'Media playing' : modal ? 'Dialog open' :
        !home ? 'Open Home to auto-refresh' : !recognized ? 'Waiting for the home feed' :
        !restored ? 'Feed selection could not be restored' : failed ? 'Feed could not load' : '',
      scrolling: performance.now() - lastScroll < 500 };
  }

  function publish() {
    if (!dirty) return;
    dirty = false;
    const value = state();
    if (!value) return;
    const message = JSON.stringify(value);
    if (message !== lastMessage) {
      window.webkit.messageHandlers.websiteState.postMessage(value);
      lastMessage = message;
    }
  }
  window.__xDesktop = {
    snapshot() { return state(); },
    refreshState() { dirty = true; publish(); },
    restoreFeed(index) { if (index === 0 || index === 1) { desiredFeed = index; restoreAttempted = false; dirty = true; publish(); } }
  };
  new MutationObserver(() => { dirty = true; }).observe(document, {
    childList: true, subtree: true, attributes: true,
    attributeFilter: ['aria-selected', 'aria-busy', 'contenteditable', 'role', 'style', 'class']
  });
  for (const name of ['input', 'focusin', 'focusout', 'play', 'pause', 'ended', 'volumechange', 'fullscreenchange', 'popstate', 'hashchange', 'visibilitychange']) {
    document.addEventListener(name, () => { dirty = true; }, true);
  }
  const markWatching = event => {
    if (!event.isTrusted || !(event.target instanceof Element)) return;
    const container = event.target.closest('video,audio,[data-testid="videoPlayer"],[data-testid="videoComponent"]');
    if (!container) return;
    const media = container.matches('video,audio') ? [container] : all('video,audio', container);
    media.forEach(element => activelyWatched.add(element));
    dirty = true;
  };
  document.addEventListener('pointerdown', markWatching, true);
  document.addEventListener('keydown', event => {
    if (event.key === ' ' || event.key === 'Enter') markWatching(event);
  }, true);
  document.addEventListener('pointermove', event => { pointer = { x: event.clientX, y: event.clientY }; dirty = true; }, { passive: true });
  document.addEventListener('wheel', event => { pointer = { x: event.clientX, y: event.clientY }; lastScroll = performance.now(); dirty = true; }, { passive: true });
  document.addEventListener('scroll', () => { lastScroll = performance.now(); dirty = true; }, { passive: true, capture: true });
  // A small heartbeat catches SPA route changes and playback/scroll state transitions.
  setInterval(() => { dirty = true; publish(); }, 500);
  publish();
})();
