(() => {
  'use strict';
  if (window.__xDesktop) return;
  let lastMessage = '';
  // Native preferences, installed by a separate document-start script in this world.
  const options = Object.assign({ followingRecent: true }, window.__xDesktopOptions);
  let desiredFeed = null;
  let restoreClickedAt = -Infinity;
  let restoreDeadline = 0;
  let restoreFailed = false;
  // The reader picked For you or Following in this document; that choice outranks restoration.
  let feedChosen = false;
  let followingSort = 'idle';
  let sortStartedAt = 0;
  let sortDeadline = 0;
  let sortClickedAt = 0;
  let lastActivity = -Infinity;
  let lastPress = -Infinity;
  let lastWheel = -Infinity;
  let marker = null;
  let foreground = true;
  let queued = false;
  const activelyWatched = new WeakSet();
  let pointer = { x: innerWidth / 2, y: innerHeight / 2 };
  const visible = element => !!element && element.getClientRects().length > 0;
  const all = (selector, root = document) => Array.from(root.querySelectorAll(selector));
  const editorSelector = '[contenteditable="true"],textarea';
  const menuSelector = '[role="menu"],[role="listbox"]';
  const mainColumn = () => document.querySelector('[data-testid="primaryColumn"]') || document.querySelector('main');
  // Logged-out landing, login, signup, and account-challenge routes.
  const signInPath = /^\/(?:$|(?:login|logout|signup|account\/access)(?:\/|$)|i\/flow\/)/;

  // A post's own permalink is the link around its timestamp.
  const statusID = article => {
    const link = article.querySelector('a[href*="/status/"] time')?.closest('a') || article.querySelector('a[href*="/status/"]');
    return link?.getAttribute('href')?.match(/\/status\/(\d{1,25})(?:[/?#]|$)/)?.[1] || null;
  };

  // The post at the top of the screen, as its status ID and its distance from the top of the
  // viewport, so a reload can bring it back. Only while scrolled down: at the top of the feed,
  // new posts belong above, so there is no place to keep.
  function placeAnchor() {
    const scrollRoot = document.scrollingElement;
    const main = mainColumn();
    if (!scrollRoot || scrollRoot.scrollTop <= 1 || !main) return null;
    const covered = main.querySelector('[role="tablist"]')?.getBoundingClientRect().bottom ?? 0;
    for (const article of all('article', main)) {
      const rect = article.getBoundingClientRect();
      if (rect.bottom <= covered + 8 || rect.height === 0) continue;
      const id = statusID(article);
      if (id) return { id, offset: Math.round(Math.max(rect.top, covered)) };
    }
    return null;
  }

  // A thin line above the post the reader was at, outside X's own page tree, removed after a while.
  function markPlace(article) {
    marker?.remove();
    const rect = article.getBoundingClientRect();
    marker = document.createElement('div');
    marker.setAttribute('aria-hidden', 'true');
    Object.assign(marker.style, { position: 'absolute', zIndex: '2', pointerEvents: 'none', height: '0',
      left: rect.left + scrollX + 'px', top: rect.top + scrollY - 1 + 'px', width: rect.width + 'px',
      borderTop: '2px solid #e2b552' });
    const label = document.createElement('span');
    label.textContent = 'You were here';
    Object.assign(label.style, { position: 'absolute', right: '12px', top: '-10px', padding: '1px 7px',
      borderRadius: '9px', background: '#e2b552', color: '#141414', font: '600 11px/16px -apple-system, sans-serif' });
    marker.append(label);
    document.body.append(marker);
    const placed = marker;
    setTimeout(() => { if (marker === placed) { marker.remove(); marker = null; } }, 20000);
  }

  // X may reset Following to Popular on every document load. Select Recent once
  // through its own controls, without overriding later manual choices in this document.
  function defaultFollowingSort(tab, blocked, layers) {
    if (followingSort === 'done' || followingSort === 'failed') return false;
    if (followingSort === 'opening') {
      const menu = layers && all(menuSelector, layers).find(visible);
      const options = menu ? all('[role="menuitem"],[role="menuitemradio"],button', menu).filter(visible) : [];
      const named = name => options.find(option => option.textContent.trim() === name);
      const recent = named('Recent');
      // Require both choices so an unrelated menu can never be acted upon.
      if (!blocked && recent && named('Popular')) {
        followingSort = 'done';
        recent.click();
        return true;
      }
      const now = performance.now();
      if (now >= sortDeadline) {
        followingSort = 'failed';
        // A recognized sort menu is ours to close. An unrecognized one (another language,
        // renamed options) opened after our click, so close it too unless the reader has
        // pressed something since: an open menu would otherwise hold refresh back indefinitely.
        if (recent && named('Popular')) tab.click();
        else if (menu && lastPress < sortStartedAt) {
          if (tab.getAttribute('aria-expanded') === 'true') tab.click();
          else menu.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', code: 'Escape', keyCode: 27, bubbles: true }));
        }
        return false;
      }
      // X can render the tab before React attaches its handlers. Retry only while
      // the dropdown remains closed, never toggle an already opened menu shut.
      if (!blocked && !menu && tab.getAttribute('aria-expanded') !== 'true' && now - sortClickedAt >= 500) {
        sortClickedAt = now;
        tab.click();
      }
      return true;
    }
    if (!options.followingRecent) return false;
    const menuOpen = layers && all(menuSelector, layers).some(visible);
    if (blocked || menuOpen) return false;
    // The dropdown may appear after the initial tab render. Check again later;
    // layouts without a sort control keep working without opening anything.
    if (!tab.hasAttribute('aria-expanded') && !tab.hasAttribute('aria-haspopup')) return false;
    followingSort = 'opening';
    sortStartedAt = sortClickedAt = performance.now();
    sortDeadline = sortClickedAt + 5000;
    tab.click();
    return true;
  }

  function state() {
    const fixture = location.protocol === 'file:' && location.pathname.endsWith('/home.html') ?
      document.documentElement.dataset.xDesktopFixture : undefined;
    const home = location.pathname === '/home' || fixture === 'true';
    const signIn = (location.protocol === 'https:' && signInPath.test(location.pathname)) || fixture === 'signin';
    const main = mainColumn();
    const feedTabs = main?.querySelector('[role="tablist"]');
    const tabs = feedTabs ? all('[role="tab"]', feedTabs).filter(visible) : [];
    const selected = tabs.findIndex(tab => tab.getAttribute('aria-selected') === 'true');
    const recognized = home && tabs.length >= 2 && selected >= 0 && selected < 2;
    // A pinned list or community tab is a valid home view, just not one this app refreshes.
    const otherTab = home && tabs.length >= 2 && selected >= 2;
    // X keeps its own pinned-tab choice across reloads; restoring For you or Following would override it.
    if (otherTab) desiredFeed = null;
    const modal = all('[role="dialog"],[aria-modal="true"]').some(visible);
    // X renders popover menus into #layers; an open one means the reader is mid-action.
    const layers = document.getElementById('layers') || (fixture === undefined ? null : document);
    const menuOpen = !!layers && all(menuSelector, layers).some(visible);
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
    // A pinned list or community tab refreshes like the two feeds.
    const ready = (recognized || otherTab) && (contentLoaded || !busy) && !failed;

    if (recognized && desiredFeed !== null && desiredFeed !== selected) {
      const now = performance.now();
      if (now >= restoreDeadline) {
        desiredFeed = null;
        restoreFailed = true;
      } else if (!typing && !modal && now - restoreClickedAt >= 500) {
        // X can render tabs before React attaches their handlers, so keep trying
        // until the click takes or the deadline passes.
        restoreClickedAt = now;
        tabs[desiredFeed]?.click();
        return null;
      }
    }
    const restored = desiredFeed === null || selected === desiredFeed;
    if (restored) desiredFeed = null;
    const sortingFollowing = recognized && selected === 1 && restored &&
      defaultFollowingSort(tabs[1], typing || modal || playing, layers);

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
    return { home, recognized, ready: !!ready && restored && !sortingFollowing, selected: recognized ? selected : -1,
      atTop: atTop && inTimeline, feedTop, protected: typing || playing || modal, draft,
      failed: home && failed, otherTab, feedChosen, restoreFailed,
      reason: signIn ? 'Sign in to load your feeds' :
        typing ? 'Auto-refresh paused while composing' :
        playing ? 'Auto-refresh paused while media plays' :
        modal ? 'Auto-refresh paused while a dialog is open' :
        !home ? 'Open Home to auto-refresh' :
        !recognized && !otherTab ? 'Waiting for the home feed' :
        !restored ? 'Restoring your last feed' :
        failed ? 'X could not load the feed' :
        sortingFollowing ? 'Selecting Recent for Following' :
        selected === 1 && followingSort === 'failed' ? 'Could not select Recent; use the Following sort menu' :
        restoreFailed ? 'Could not restore your last feed' : '',
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
    // With withPlace, also the post at the top of the screen, which a reload is about to replace.
    snapshot(withPlace) {
      const value = state();
      if (value && withPlace) value.place = placeAnchor();
      return value;
    },
    // After a reload, find the post the reader was at, scrolling down a screen at a time while X
    // loads more, and put it back where it was. Any key, click or wheel from the reader stops it.
    async restorePlace(id, offset) {
      if (!/^\d{1,25}$/.test(String(id)) || !Number.isFinite(offset)) return 'invalid';
      const started = performance.now();
      const find = () => all('article', mainColumn() || document).find(article => statusID(article) === id);
      for (let step = 0; step < 15; step++) {
        if (lastPress > started || lastWheel > started) return 'interrupted';
        const article = find();
        if (article) {
          window.scrollBy(0, article.getBoundingClientRect().top - offset);
          markPlace(article);
          soon();
          return 'restored';
        }
        window.scrollBy(0, innerHeight * 0.9);
        await new Promise(resolve => setTimeout(resolve, 350));
      }
      if (lastPress <= started && lastWheel <= started) window.scrollTo(0, 0);
      soon();
      return 'missing';
    },
    // X's own "Show N posts" button at the top of the feed. Using it is lighter than a reload and
    // keeps X's state. Matched by its exact English wording, so nothing else is ever clicked.
    showNewPosts() {
      const main = mainColumn();
      if (!main) return false;
      const button = all('[role="button"],button', main).find(element =>
        visible(element) && /^Show \d[\d,]*\+? posts?$/.test(element.textContent.trim()));
      if (!button) return false;
      button.click();
      soon();
      return true;
    },
    // Native navigation bookkeeping resets its copy, so always resend.
    refreshState() { lastMessage = ''; publish(); },
    restoreFeed(index) {
      if (index !== 0 && index !== 1) return;
      desiredFeed = index;
      restoreClickedAt = -Infinity;
      restoreDeadline = performance.now() + 10000;
      restoreFailed = false;
      feedChosen = false;
      publish();
    },
    // A menu command chose this feed, which counts as the reader's own choice.
    selectFeed(index) {
      const list = mainColumn()?.querySelector('[role="tablist"]');
      const tabs = list ? all('[role="tab"]', list).filter(visible) : [];
      if ((index !== 0 && index !== 1) || !tabs[index]) return false;
      desiredFeed = null; restoreFailed = false; feedChosen = true;
      tabs[index].click();
      soon();
      return true;
    },
    setOptions(value) { Object.assign(options, value); soon(); },
    // The native window cannot be seen, so the heartbeat can slow down.
    setForeground(value) { foreground = !!value; if (foreground) soon(); },
    // The https image beneath a context-menu click, in CSS pixels.
    imageAt(x, y) {
      for (const element of document.elementsFromPoint(x, y)) {
        const source = element instanceof HTMLImageElement ? element.currentSrc || element.src : '';
        if (/^https:\/\//.test(source)) return source;
      }
      return null;
    },
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
  const press = event => { if (event.isTrusted) lastPress = performance.now(); };
  document.addEventListener('pointerdown', event => { press(event); markWatching(event); touch(); soon(); }, true);
  document.addEventListener('keydown', event => {
    press(event);
    if (event.key === ' ' || event.key === 'Enter') markWatching(event);
    touch(); soon();
  }, true);
  // Only a real click or key press on a feed tab counts as the reader choosing a feed.
  document.addEventListener('click', event => {
    if (!event.isTrusted || !(event.target instanceof Element)) return;
    const tab = event.target.closest('[role="tab"]');
    if (tab && mainColumn()?.querySelector('[role="tablist"]')?.contains(tab)) {
      feedChosen = true; desiredFeed = null; restoreFailed = false; soon();
    }
  }, true);
  document.addEventListener('visibilitychange', soon);
  document.addEventListener('pointermove', event => {
    // WebKit repeats moves at a resting pointer when content shifts beneath it; only real motion counts.
    if (event.clientX === pointer.x && event.clientY === pointer.y) return;
    pointer = { x: event.clientX, y: event.clientY };
    touch();
  }, { passive: true });
  document.addEventListener('wheel', event => {
    if (event.isTrusted) lastWheel = performance.now();
    pointer = { x: event.clientX, y: event.clientY }; touch(); soon();
  }, { passive: true });
  document.addEventListener('scroll', () => { touch(); soon(); }, { passive: true, capture: true });
  document.addEventListener('selectionchange', touch);
  // A small heartbeat catches SPA route changes and playback/scroll state transitions.
  // While the native window cannot be seen, check only every five seconds.
  let beats = 0;
  setInterval(() => { if (foreground || ++beats % 10 === 0) publish(); }, 500);
  publish();
})();
