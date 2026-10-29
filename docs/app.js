/* moonurl docs: region navigation, theme toggle, and a playground run by
   moonurl itself, built to JavaScript into engine/moonurl.js. */
(function () {
  "use strict";

  const root = document.documentElement;
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  /* ---------------- Theme toggle ------------------------------------- */
  const themeToggle = document.getElementById("theme-toggle");
  const stored = (function () {
    try { return localStorage.getItem("moonurl-theme"); } catch (e) { return null; }
  })();
  if (stored === "dark") root.classList.add("dark");
  else if (stored === "light") root.classList.add("light");

  if (themeToggle) {
    themeToggle.addEventListener("click", function () {
      const isDark = root.classList.contains("dark") ||
        (!root.classList.contains("light") &&
         window.matchMedia("(prefers-color-scheme: dark)").matches);
      if (isDark) {
        root.classList.remove("dark"); root.classList.add("light");
        try { localStorage.setItem("moonurl-theme", "light"); } catch (e) {}
      } else {
        root.classList.remove("light"); root.classList.add("dark");
        try { localStorage.setItem("moonurl-theme", "dark"); } catch (e) {}
      }
      themeToggle.classList.remove("spin");
      // force reflow so the rotation animation replays each click
      void themeToggle.offsetWidth;
      themeToggle.classList.add("spin");
    });
  }

  /* ---------------- Region navigation -------------------------------- */
  const stage = document.getElementById("stage");
  const links = Array.prototype.slice.call(document.querySelectorAll(".rail a"));
  const regions = links.map(function (a) {
    return document.getElementById(a.dataset.target);
  });
  const rail = document.querySelector(".rail");
  const railThumb = document.getElementById("rail-thumb");
  const seen = Object.create(null);

  function moveThumb(link) {
    if (!railThumb || !link || !rail) return;
    const r = rail.getBoundingClientRect();
    const a = link.getBoundingClientRect();
    const top = a.top - r.top + a.height / 2 - 8; // 8 = half thumb height
    railThumb.style.top = top + "px";
  }

  function setActive(id) {
    links.forEach(function (a) {
      const on = a.dataset.target === id;
      a.classList.toggle("active", on);
      if (on) moveThumb(a);
    });
  }

  links.forEach(function (a) {
    a.addEventListener("click", function (e) {
      e.preventDefault();
      const el = document.getElementById(a.dataset.target);
      if (el) el.scrollIntoView({ behavior: reduceMotion ? "auto" : "smooth", block: "start" });
    });
  });

  if ("IntersectionObserver" in window) {
    // Reveal: animate a region once it has entered the view.
    const revealIO = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting && !entry.target.classList.contains("seen")) {
            entry.target.classList.add("seen");
          }
        });
      },
      { root: stage, threshold: 0.15 }
    );
    regions.forEach(function (r) { if (r) revealIO.observe(r); });

    // Active: whichever region crosses the middle band of the viewport.
    // A band (not a 0.5 ratio) keeps the rail correct for sections far
    // taller than one screen, where the intersection ratio never reaches 0.5.
    const activeIO = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) setActive(entry.target.id);
        });
      },
      { root: stage, rootMargin: "-45% 0px -45% 0px", threshold: 0 }
    );
    regions.forEach(function (r) { if (r) activeIO.observe(r); });
  } else {
    regions.forEach(function (r) { if (r) r.classList.add("seen"); });
  }

  /* ---------------- Scroll-progress hairline + mesh parallax --------- */
  const progress = document.getElementById("progress");
  const mesh = document.querySelector(".mesh");
  if (stage) {
    stage.addEventListener("scroll", function () {
      const max = stage.scrollHeight - stage.clientHeight;
      const pct = max > 0 ? (stage.scrollTop / max) * 100 : 0;
      if (progress) progress.style.width = pct + "%";
      if (mesh && !reduceMotion) {
        mesh.style.transform = "translate3d(0," + (stage.scrollTop * 0.05) + "px,0)";
      }
    }, { passive: true });
    // initial paint
    const max = stage.scrollHeight - stage.clientHeight;
    if (progress) progress.style.width = (max > 0 ? (stage.scrollTop / max) * 100 : 0) + "%";
  }

  /* ---------------- Helpers ----------------------------------------- */
  function setOut(el, text, isErr) {
    el.textContent = text;
    el.classList.toggle("err", !!isErr);
  }
  function escapeHtml(s) {
    return s.replace(/[&<>"]/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
    });
  }
  function chip(label, text) {
    return '<span class="chip">' + label + ": " + escapeHtml(text) + "</span>";
  }
  function segmented(seg, onPick) {
    if (!seg) return;
    Array.prototype.forEach.call(seg.querySelectorAll(".seg-btn"), function (btn) {
      btn.addEventListener("click", function () {
        seg.querySelectorAll(".seg-btn").forEach(function (b) { b.classList.remove("active"); });
        btn.classList.add("active");
        onPick(btn.dataset.mode);
      });
    });
  }

  /* ---------------- The engine: moonurl built to JavaScript ---------- */
  let engine = null;
  const ready = import("./engine/moonurl.js")
    .then(function (m) { engine = m; })
    .catch(function () { engine = null; });
  function call(out, run) {
    if (!engine) {
      setOut(out, "The moonurl engine did not load.", true);
      return null;
    }
    return JSON.parse(run(engine));
  }

  /* ---------------- IDNA demo (segmented control) ------------------- */
  const idnaIn = document.getElementById("idna-in");
  const idnaOut = document.getElementById("idna-out");
  const idnaChips = document.getElementById("idna-chips");
  let idnaMode = "a";
  segmented(document.getElementById("idna-seg"), function (mode) {
    idnaMode = mode;
    runIdna();
  });
  function runIdna() {
    const v = idnaIn.value.trim();
    if (!v) { setOut(idnaOut, "Type a host name first.", true); idnaChips.innerHTML = ""; return; }
    const r = call(idnaOut, function (e) { return e.idna(v); });
    if (!r) { idnaChips.innerHTML = ""; return; }
    const pick = idnaMode === "a" ? r.ascii : r.unicode;
    if (pick.errors.length) setOut(idnaOut, [pick.name].concat(pick.errors).join("\n"), true);
    else setOut(idnaOut, pick.name);
    idnaChips.innerHTML = chip("ASCII", r.ascii.name) + chip("Unicode", r.unicode.name);
  }
  const idnaRun = document.getElementById("idna-run");
  if (idnaRun) idnaRun.addEventListener("click", runIdna);

  /* ---------------- RFC 6570 expander ------------------------------- */
  const tplIn = document.getElementById("tpl-in");
  const tplVars = document.getElementById("tpl-vars");
  const tplOut = document.getElementById("tpl-out");
  const tplGo = document.getElementById("tpl-go");
  function runTemplate() {
    const r = call(tplOut, function (e) { return e.expand(tplIn.value.trim(), tplVars.value); });
    if (!r) return;
    if (r.ok) setOut(tplOut, r.result);
    else setOut(tplOut, r.error, true);
  }
  if (tplGo) tplGo.addEventListener("click", runTemplate);

  /* ---------------- URL splitter, by either grammar ----------------- */
  const urlIn = document.getElementById("url-in");
  const urlOut = document.getElementById("url-out");
  const urlGo = document.getElementById("url-go");
  let urlMode = "rfc3986";
  segmented(document.getElementById("url-seg"), function (mode) {
    urlMode = mode;
    runUrl();
  });
  function runUrl() {
    const s = urlIn.value.trim();
    const r = call(urlOut, function (e) { return e.split(s, urlMode); });
    if (!r) return;
    if (!r.ok) { setOut(urlOut, r.error, true); return; }
    const keys = ["scheme", "userinfo", "host", "port", "path", "query", "fragment", "normalized"];
    setOut(urlOut, keys.map(function (k) {
      return k.padEnd(10) + " = " + (r[k] === null ? "(none)" : JSON.stringify(r[k]));
    }).join("\n"));
  }
  if (urlGo) urlGo.addEventListener("click", runUrl);

  /* ---------------- Copy-to-clipboard for code cards ----------------- */
  const COPY_ICON = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V5a2 2 0 0 1 2-2h10"/></svg>';
  const CHECK_ICON = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>';
  Array.prototype.forEach.call(document.querySelectorAll(".copy"), function (btn) {
    const original = btn.innerHTML;
    btn.addEventListener("click", function () {
      const card = btn.closest(".codecard");
      const pre = card ? card.querySelector("pre") : null;
      const text = pre ? pre.innerText : "";
      const done = function () {
        btn.innerHTML = CHECK_ICON;
        btn.classList.add("copied");
        setTimeout(function () { btn.innerHTML = original; btn.classList.remove("copied"); }, 1400);
      };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(done, function () {});
      } else {
        const ta = document.createElement("textarea");
        ta.value = text; document.body.appendChild(ta); ta.select();
        try { document.execCommand("copy"); done(); } catch (e) {}
        document.body.removeChild(ta);
      }
    });
  });

  /* ---------------- First paint of the demos ------------------------ */
  ready.then(function () { runIdna(); runTemplate(); runUrl(); });
})();
