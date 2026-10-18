/* ==========================================================================
   ClipBar landing page — vanilla JS, no build step
   ========================================================================== */
(function () {
  "use strict";

  // ---------------------------------------------------------------------
  // Configuration — the only place URLs / names / tiers live
  // ---------------------------------------------------------------------
  var CONFIG = {
    APP_NAME: "ClipBar",
    CREATOR_NAME: "Or (Leo) Davidai",
    CREATOR_SHORT: "Leo",
    DOWNLOAD_URL: "https://github.com/turhe123/clipbar/releases/latest/download/ClipBar.zip",
    RELEASES_URL: "https://github.com/turhe123/clipbar/releases/latest",
    RELEASE_API_URL: "https://api.github.com/repos/turhe123/clipbar/releases/latest",
    ASSET_NAME: "ClipBar.zip",
    REPO_URL: "https://github.com/turhe123/clipbar",
    KOFI_URL: "https://ko-fi.com/turhe123",
    TIERS: [0, 3, 5, 10],
    DEFAULT_TIER: 5,
    RESET_DELAY_MS: 2500
  };

  document.documentElement.classList.add("js");

  var $ = function (sel, root) { return (root || document).querySelector(sel); };
  var $$ = function (sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); };

  // ---------------------------------------------------------------------
  // Navigation: scrolled state + mobile toggle
  // ---------------------------------------------------------------------
  var navWrap = $(".nav-wrap");
  var navToggle = $("#nav-toggle");
  var navLinks = $("#nav-links");

  function onScroll() {
    if (navWrap) navWrap.classList.toggle("is-scrolled", window.scrollY > 8);
  }
  window.addEventListener("scroll", onScroll, { passive: true });
  onScroll();

  function closeNav() {
    if (!navToggle || !navLinks) return;
    navToggle.setAttribute("aria-expanded", "false");
    navLinks.classList.remove("is-open");
  }
  if (navToggle && navLinks) {
    navToggle.addEventListener("click", function () {
      var open = navToggle.getAttribute("aria-expanded") === "true";
      navToggle.setAttribute("aria-expanded", String(!open));
      navLinks.classList.toggle("is-open", !open);
    });
    $$("a, button", navLinks).forEach(function (el) { el.addEventListener("click", closeNav); });
    document.addEventListener("click", function (e) {
      if (!navWrap.contains(e.target)) closeNav();
    });
  }

  // ---------------------------------------------------------------------
  // Scroll reveal
  // ---------------------------------------------------------------------
  var reveals = $$(".reveal");
  if ("IntersectionObserver" in window && reveals.length) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-visible");
          io.unobserve(entry.target);
        }
      });
    }, { rootMargin: "0px 0px -8% 0px", threshold: 0.08 });
    reveals.forEach(function (el) { io.observe(el); });
    // Safety net: never leave content hidden if the observer is slow or never fires.
    setTimeout(function () {
      reveals.forEach(function (el) { el.classList.add("is-visible"); });
    }, 1500);
  } else {
    reveals.forEach(function (el) { el.classList.add("is-visible"); });
  }

  // Cursor-follow glow on feature cards (pointer devices only)
  if (window.matchMedia && window.matchMedia("(hover: hover)").matches) {
    $$(".card").forEach(function (card) {
      card.addEventListener("pointermove", function (e) {
        var r = card.getBoundingClientRect();
        card.style.setProperty("--mx", ((e.clientX - r.left) / r.width * 100).toFixed(1) + "%");
        card.style.setProperty("--my", ((e.clientY - r.top) / r.height * 100).toFixed(1) + "%");
      });
    });
  }

  // ---------------------------------------------------------------------
  // Pay What You Want modal
  // ---------------------------------------------------------------------
  var modal = $("#pwyw-modal");
  var backdrop = $("#pwyw-backdrop");
  var dialog = $("#pwyw-dialog");
  var closeBtn = $("#pwyw-close");
  var tierButtons = $$(".tier", $("#pwyw-tiers"));
  var actionBtn = $("#pwyw-action");
  var noteEl = $("#pwyw-note");
  var openers = $$("[data-open-pwyw]");

  var selectedAmount = CONFIG.DEFAULT_TIER;
  var lastOpener = null;
  var resetTimer = null;
  var actionBusy = false;

  function money(n) { return "$" + n; }

  function renderAction() {
    if (actionBusy) return;
    if (selectedAmount > 0) {
      actionBtn.textContent = "Support " + CONFIG.CREATOR_SHORT + " (" + money(selectedAmount) + ") & Download";
      noteEl.textContent = "Opens Ko-fi in a new tab and starts the " + CONFIG.ASSET_NAME + " download. Thank you! ❤️";
    } else {
      actionBtn.textContent = "Download for Free ($0)";
      noteEl.textContent = "No strings attached. Starts the " + CONFIG.ASSET_NAME + " download from GitHub Releases.";
    }
  }

  function selectTier(amount) {
    selectedAmount = amount;
    tierButtons.forEach(function (btn) {
      var isActive = Number(btn.getAttribute("data-amount")) === amount;
      btn.setAttribute("aria-pressed", String(isActive));
    });
    renderAction();
  }

  tierButtons.forEach(function (btn) {
    btn.addEventListener("click", function () {
      selectTier(Number(btn.getAttribute("data-amount")) || 0);
    });
  });

  function getFocusable() {
    return $$('button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])', dialog)
      .filter(function (el) { return !el.disabled && el.offsetParent !== null; });
  }

  function openModal(opener) {
    if (!modal) return;
    lastOpener = opener || document.activeElement;
    closeNav();
    modal.hidden = false;
    document.body.classList.add("modal-open");
    selectTier(selectedAmount);
    // Focus the preselected tier so keyboard users land somewhere meaningful.
    var pressed = tierButtons.filter(function (b) { return b.getAttribute("aria-pressed") === "true"; })[0];
    window.requestAnimationFrame(function () { (pressed || dialog).focus(); });
    document.addEventListener("keydown", onModalKeydown);
  }

  function closeModal() {
    if (!modal || modal.hidden) return;
    modal.hidden = true;
    document.body.classList.remove("modal-open");
    document.removeEventListener("keydown", onModalKeydown);
    if (lastOpener && typeof lastOpener.focus === "function") lastOpener.focus();
    lastOpener = null;
  }

  function onModalKeydown(e) {
    if (e.key === "Escape") { e.preventDefault(); closeModal(); return; }
    if (e.key === "Tab") {
      var items = getFocusable();
      if (!items.length) return;
      var first = items[0], last = items[items.length - 1];
      if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
      else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
    }
  }

  openers.forEach(function (btn) {
    btn.addEventListener("click", function () { openModal(btn); });
  });
  if (closeBtn) closeBtn.addEventListener("click", closeModal);
  if (backdrop) backdrop.addEventListener("click", closeModal);

  // ---------------------------------------------------------------------
  // Download + Ko-fi handoff
  // ---------------------------------------------------------------------
  function startDownload() {
    var a = document.createElement("a");
    a.href = CONFIG.DOWNLOAD_URL;
    a.setAttribute("download", CONFIG.ASSET_NAME);
    a.rel = "noopener";
    a.style.display = "none";
    document.body.appendChild(a);
    a.click();
    window.setTimeout(function () { if (a.parentNode) a.parentNode.removeChild(a); }, 1000);
  }

  if (actionBtn) {
    actionBtn.addEventListener("click", function () {
      if (actionBusy) return;
      var amount = selectedAmount;

      // Open Ko-fi synchronously inside the click handler so popup blockers allow it.
      if (amount > 0) {
        window.open(CONFIG.KOFI_URL, "_blank", "noopener,noreferrer");
      }
      startDownload();

      actionBusy = true;
      actionBtn.disabled = true;
      actionBtn.textContent = amount > 0 ? "Thank you! Downloading…" : "Downloading…";
      window.clearTimeout(resetTimer);
      resetTimer = window.setTimeout(function () {
        actionBusy = false;
        actionBtn.disabled = false;
        renderAction();
      }, CONFIG.RESET_DELAY_MS);
    });
  }

  // ---------------------------------------------------------------------
  // Optional: latest release metadata from GitHub (never blocks download)
  // ---------------------------------------------------------------------
  function formatBytes(bytes) {
    if (!bytes || bytes <= 0) return "";
    var mb = bytes / (1024 * 1024);
    return mb >= 1 ? mb.toFixed(1) + " MB" : Math.round(bytes / 1024) + " KB";
  }

  function applyReleaseInfo(release) {
    if (!release || !release.tag_name) return;
    var tag = String(release.tag_name);
    var asset = (release.assets || []).filter(function (x) { return x && x.name === CONFIG.ASSET_NAME; })[0];
    var size = asset ? formatBytes(asset.size) : "";
    var parts = [CONFIG.ASSET_NAME, tag];
    if (size) parts.push(size);

    var releaseMeta = $("#release-meta");
    var modalRelease = $("#pwyw-release");
    var heroVersion = $("#hero-version");
    if (releaseMeta) releaseMeta.textContent = parts.join(" · ");
    if (modalRelease) modalRelease.textContent = parts.join(" · ") + " · macOS 14+ · Universal";
    if (heroVersion) heroVersion.textContent = "Latest release " + tag;
  }

  if (window.fetch) {
    try {
      fetch(CONFIG.RELEASE_API_URL, { headers: { Accept: "application/vnd.github+json" } })
        .then(function (res) { return res.ok ? res.json() : null; })
        .then(applyReleaseInfo)
        .catch(function () { /* silent fallback to the static direct URL */ });
    } catch (err) { /* ignore */ }
  }

  // Initial render
  if (actionBtn && noteEl) selectTier(CONFIG.DEFAULT_TIER);
})();
