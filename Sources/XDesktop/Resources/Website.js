(() => {
  'use strict';
  if (window.__xDesktop) return;
  let lastMessage = '';
  let desiredFeed = null;
  let restoreAttempted = false;
  let lastActivity = -Infinity;
  let queued = false;
  const activelyWatched = new WeakSet();
  let pointer = { x: innerWidth / 2, y: innerHeight / 2 };
  const visible = element => !!element && element.getClientRects().length > 0;
  const all = (selector, root = document) => Array.from(root.querySelectorAll(selector));
  const editorSelector = '[contenteditable="true"],textarea';
  // Logged-out landing, login, signup, and account-challenge routes.
  const signInPath = /^\/(?:$|(?:login|logout|signup|account\/access)(?:\/|$)|i\/flow\/)/;

  function state() {
    const fixture = location.protocol === 'file:' && location.pathname.endsWith('/home.html') ?
      document.documentElement.dataset.xDesktopFixture : undefined;
    const home = location.pathname === '/home' || fixture === 'true';
    const signIn = (location.protocol === 'https:' && signInPath.test(location.pathname)) || fixture === 'signin';
    const main = document.querySelector('[data-testid="primaryColumn"]') || document.querySelector('main');
    const feedTabs = main?.querySelector('[role="tablist"]');
    const tabs = feedTabs ? all('[role="tab"]', feedTabs).filter(visible) : [];
    const selected = tabs.findIndex(tab => tab.getAttribute('aria-selected') === 'true');
    const recognized = home && tabs.length >= 2 && selected >= 0 && selected < 2;
    // A pinned list or community tab is a valid home view, just not one this app refreshes.
    const otherTab = home && tabs.length >= 2 && selected >= 2;
    const modal = all('[role="dialog"],[aria-modal="true"]').some(visible);
    // X renders popover menus into #layers; an open one means the reader is mid-action.
    const layers = document.getElementById('layers') || (fixture === undefined ? null : document);
    const menuOpen = !!layers && all('[role="menu"],[role="listbox"]', layers).some(visible);
    const editorFocused = document.activeElement?.matches(editorSelector) || false;
    const draftText = all(editorSelector).some(element => visible(element) &&
      ((element.value || element.textContent || '').trim().length > 0));
    const attachedFile = all('input[type="file"]').some(element => element.files?.length > 0);
    const draft = draftText || attachedFile;
    const typing = editorFocused || draft;
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
    const feedTop = !scrollRoot || scrollRoot.scrollTop <= 1;
    if (!feedTop) atTop = false;
    return { home, recognized, ready: !!ready && restored, selected: recognized ? selected : -1,
      atTop: atTop && inTimeline, feedTop, protected: typing || playing || modal, draft,
      failed: home && failed, otherTab,
      reason: signIn ? 'Sign in to load your feeds' :
        typing ? 'Auto-refresh paused while composing' :
        playing ? 'Auto-refresh paused while media plays' :
        modal ? 'Auto-refresh paused while a dialog is open' :
        !home ? 'Open Home to auto-refresh' :
        otherTab ? 'Auto-refresh covers For you and Following only' :
        !recognized ? 'Waiting for the home feed' :
        !restored ? 'Feed selection could not be restored' : failed ? 'X could not load the feed' : '',
      // One second outlasts the half-second heartbeat, so no input burst goes unseen.
      active: menuOpen || performance.now() - lastActivity < 1000 };
  }

  function publish() {
    queued = false;
    const value = state();
    if (!value) return;
    const message = JSON.stringify(value);
    if (message !== lastMessage) {
      window.webkit.messageHandlers.websiteState.postMessage(value);
      lastMessage = message;
    }
  }
  // Report promptly after input so native code sees fresh boundaries and drafts,
  // without evaluating the page on every event.
  function soon() {
    if (queued) return;
    queued = true;
    setTimeout(publish, 120);
  }
  window.__xDesktop = {
    snapshot() { return state(); },
    // Native navigation bookkeeping resets its copy, so always resend.
    refreshState() { lastMessage = ''; publish(); },
    restoreFeed(index) { if (index === 0 || index === 1) { desiredFeed = index; restoreAttempted = false; publish(); } },
    pauseMedia() { all('video,audio').forEach(element => element.pause()); }
  };
  const touch = () => { lastActivity = performance.now(); };
  for (const name of ['input', 'focusin', 'focusout', 'play', 'pause', 'ended', 'volumechange',
                      'fullscreenchange', 'webkitfullscreenchange', 'popstate', 'hashchange']) {
    document.addEventListener(name, soon, true);
  }
  const markWatching = event => {
    if (!event.isTrusted || !(event.target instanceof Element)) return;
    const container = event.target.closest('video,audio,[data-testid="videoPlayer"],[data-testid="videoComponent"]');
    if (!container) return;
    const media = container.matches('video,audio') ? [container] : all('video,audio', container);
    media.forEach(element => activelyWatched.add(element));
  };
  document.addEventListener('pointerdown', event => { markWatching(event); touch(); soon(); }, true);
  document.addEventListener('keydown', event => {
    if (event.key === ' ' || event.key === 'Enter') markWatching(event);
    touch(); soon();
  }, true);
  document.addEventListener('pointermove', event => {
    // WebKit repeats moves at a resting pointer when content shifts beneath it; only real motion counts.
    if (event.clientX === pointer.x && event.clientY === pointer.y) return;
    pointer = { x: event.clientX, y: event.clientY };
    touch();
  }, { passive: true });
  document.addEventListener('wheel', event => { pointer = { x: event.clientX, y: event.clientY }; touch(); soon(); }, { passive: true });
  document.addEventListener('scroll', () => { touch(); soon(); }, { passive: true, capture: true });
  document.addEventListener('selectionchange', touch);
  // A small heartbeat catches SPA route changes and playback/scroll state transitions.
  setInterval(publish, 500);
  publish();
})();
