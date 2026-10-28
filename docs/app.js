/* moonurl docs — region navigation, theme toggle, and an interactive
   playground. Self-contained: punycode (RFC 3492) and a UTS 46 subset
   (NFC via String.normalize), plus an RFC 6570 level-4 expander.
   No dependencies. */
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
    const io = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) {
            const id = entry.target.id;
            setActive(id);
            if (!seen[id]) { seen[id] = true; entry.target.classList.add("seen"); }
          }
        });
      },
      { root: stage, threshold: 0.5 }
    );
    regions.forEach(function (r) { if (r) io.observe(r); });
  } else {
    regions.forEach(function (r) { if (r) r.classList.add("seen"); });
  }

  /* ---------------- Scroll-progress hairline ------------------------- */
  const progress = document.getElementById("progress");
  if (stage && progress) {
    stage.addEventListener("scroll", function () {
      const max = stage.scrollHeight - stage.clientHeight;
      const pct = max > 0 ? (stage.scrollTop / max) * 100 : 0;
      progress.style.width = pct + "%";
    }, { passive: true });
    // initial paint
    const max = stage.scrollHeight - stage.clientHeight;
    progress.style.width = (max > 0 ? (stage.scrollTop / max) * 100 : 0) + "%";
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
  function isAscii(s) {
    for (let i = 0; i < s.length; i++) {
      if (s.charCodeAt(i) > 127) return false;
    }
    return true;
  }

  /* ---------------- RFC 3492 punycode ------------------------------- */
  const BASE = 36, TMIN = 1, TMAX = 26, SKEW = 38, DAMP = 700,
        INIT_BIAS = 72, INIT_N = 128;

  function adapt(delta, numPoints, firstTime) {
    delta = firstTime ? Math.floor(delta / DAMP) : delta >> 1;
    delta += Math.floor(delta / numPoints);
    let k = 0;
    while (delta > ((BASE - TMIN) * TMAX) >> 1) {
      delta = Math.floor(delta / (BASE - TMIN));
      k += BASE;
    }
    return k + Math.floor(((BASE - TMIN + 1) * delta) / (delta + SKEW));
  }
  function digitToBasic(d) {
    return String.fromCharCode(d + 22 + 75 * (d < 26 ? 1 : 0));
  }
  function basicToDigit(cp) {
    if (cp >= 48 && cp <= 57) return cp - 22;   // 0-9
    if (cp >= 65 && cp <= 90) return cp - 65;   // A-Z
    if (cp >= 97 && cp <= 122) return cp - 97;  // a-z
    return -1;
  }
  function punyEncode(input) {
    const cps = Array.from(input);
    let n = INIT_N, delta = 0, bias = INIT_BIAS;
    let output = [], basic = [];
    for (let i = 0; i < cps.length; i++) {
      const cp = cps[i].codePointAt(0);
      if (cp < 128) basic.push(cps[i]);
    }
    let b = basic.length;
    output = basic.slice();
    let h = b;
    if (b > 0 && h < cps.length) output.push("-");
    while (h < cps.length) {
      let m = Infinity;
      for (let i = 0; i < cps.length; i++) {
        const cp = cps[i].codePointAt(0);
        if (cp >= n && cp < m) m = cp;
      }
      delta += (m - n) * (h + 1);
      n = m;
      for (let i = 0; i < cps.length; i++) {
        const cp = cps[i].codePointAt(0);
        if (cp < n) delta++;
        if (cp === n) {
          let q = delta;
          for (let k = BASE; ; k += BASE) {
            const t = k <= bias ? TMIN : k >= bias + TMAX ? TMAX : k - bias;
            if (q < t) break;
            const qc = t + ((q - t) % (BASE - t));
            output.push(digitToBasic(qc));
            q = Math.floor((q - t) / (BASE - t));
          }
          output.push(digitToBasic(q));
          bias = adapt(delta, h + 1, h === b);
          delta = 0;
          h++;
        }
      }
      delta++;
      n++;
    }
    return output.join("");
  }
  function punyDecode(input) {
    let n = INIT_N, i = 0, bias = INIT_BIAS;
    let output = [];
    const basic = input.lastIndexOf("-");
    let start = 0;
    if (basic > 0) {
      for (let j = 0; j < basic; j++) {
        const cp = input.charCodeAt(j);
        if (cp >= 128) throw new Error("non-ASCII in basic part");
        output.push(input[j]);
      }
      start = basic + 1;
    }
    while (start < input.length) {
      const oldi = i;
      let w = 1;
      for (let k = BASE; ; k += BASE) {
        if (start >= input.length) throw new Error("malformed input");
        const digit = basicToDigit(input.charCodeAt(start++));
        if (digit < 0) throw new Error("bad digit");
        i += digit * w;
        const t = k <= bias ? TMIN : k >= bias + TMAX ? TMAX : k - bias;
        if (digit < t) break;
        w *= BASE - t;
      }
      const outLen = output.length + 1;
      bias = adapt(i - oldi, outLen, oldi === 0);
      n += Math.floor(i / outLen);
      i %= outLen;
      output.splice(i, 0, String.fromCodePoint(n));
      i++;
    }
    return output.join("");
  }

  /* ---------------- UTS 46 (subset) --------------------------------- */
  function toAsciiName(name) {
    const labels = name.split(".");
    const out = [];
    for (const raw of labels) {
      const label = raw.toLowerCase();
      if (label.length === 0) { out.push(label); continue; }
      if (isAscii(label)) {
        if (label.indexOf("xn--") === 0) {
          out.push("xn--" + punyDecode(label.slice(4)));
        } else {
          out.push(label);
        }
      } else {
        const norm = label.normalize("NFC");
        out.push("xn--" + punyEncode(norm));
      }
    }
    return out.join(".");
  }
  function toUnicodeName(name) {
    const labels = name.split(".");
    const out = [];
    for (const raw of labels) {
      const label = raw.toLowerCase();
      if (label.indexOf("xn--") === 0 && label.length > 4) {
        out.push(punyDecode(label.slice(4)));
      } else {
        out.push(label);
      }
    }
    return out.join(".");
  }

  /* ---------------- IDNA demo (segmented control) ------------------- */
  const idnaIn = document.getElementById("idna-in");
  const idnaOut = document.getElementById("idna-out");
  const idnaChips = document.getElementById("idna-chips");
  const idnaSeg = document.getElementById("idna-seg");
  let idnaMode = "a";

  if (idnaSeg) {
    Array.prototype.forEach.call(idnaSeg.querySelectorAll(".seg-btn"), function (btn) {
      btn.addEventListener("click", function () {
        idnaSeg.querySelectorAll(".seg-btn").forEach(function (b) { b.classList.remove("active"); });
        btn.classList.add("active");
        idnaMode = btn.dataset.mode;
        runIdna();
      });
    });
  }
  function runIdna() {
    const v = idnaIn.value.trim();
    if (!v) { setOut(idnaOut, "Type a host name first.", true); idnaChips.innerHTML = ""; return; }
    try {
      const result = idnaMode === "a" ? toAsciiName(v) : toUnicodeName(v);
      setOut(idnaOut, result);
      const ascii = toAsciiName(v);
      idnaChips.innerHTML =
        '<span class="chip">ASCII: ' + escapeHtml(ascii) + "</span>" +
        '<span class="chip">Unicode: ' + escapeHtml(toUnicodeName(v)) + "</span>";
    } catch (e) {
      setOut(idnaOut, e.message, true);
      idnaChips.innerHTML = "";
    }
  }
  const idnaRun = document.getElementById("idna-run");
  if (idnaRun) idnaRun.addEventListener("click", runIdna);

  /* ---------------- RFC 6570 expander ------------------------------- */
  const RESERVED = ":/?#[]@!$&'()*+,;=";
  function isUnreserved(ch) { return /[A-Za-z0-9._~-]/.test(ch); }
  function pct(str, reserved) {
    let out = "";
    for (const ch of str) {
      const cp = ch.codePointAt(0);
      const ok = cp <= 0x7f && (reserved
        ? RESERVED.indexOf(ch) !== -1 || isUnreserved(ch)
        : isUnreserved(ch));
      if (ok) out += ch;
      else {
        const bytes = new TextEncoder().encode(ch);
        for (const b of bytes) out += "%" + b.toString(16).toUpperCase().padStart(2, "0");
      }
    }
    return out;
  }
  function expandExpr(expr, vars) {
    const opChars = "+#./;?&";
    let op = "", rest = expr;
    if (opChars.indexOf(expr[0]) !== -1) { op = expr[0]; rest = expr.slice(1); }
    const named = op === ";" || op === "?" || op === "&";
    const reserved = op === "+" || op === "#";
    const specs = rest.split(",");
    const join = op === "" || op === "+" || op === "#" ? "," :
                 op === "." ? "." : op === "/" ? "/" :
                 op === ";" ? ";" : "&";
    const firstPrefix = (op === "" || op === "+") ? "" : op;
    let out = "", first = true;
    for (const spec of specs) {
      const m = spec.match(/^([^:*]+)(:\d+|\*)?$/);
      if (!m) continue;
      const name = m[1], mod = m[2] || "";
      if (!Object.prototype.hasOwnProperty.call(vars, name)) continue;
      const v = vars[name];
      const items = itemsOf(v, mod);
      const explode = mod === "*";
      let piece;
      if (v.type === "pairs") {
        if (explode) {
          piece = items.map(function (it) {
            return pct(it.name, reserved) + "=" + pct(it.value, reserved);
          }).join(join);
        } else {
          const flat = items.map(function (it) {
            return pct(it.name, reserved) + "," + pct(it.value, reserved);
          }).join(",");
          piece = named ? name + "=" + flat : flat;
        }
      } else if (v.type === "list") {
        if (explode) {
          piece = named
            ? items.map(function (it) { return name + "=" + pct(it.value, reserved); }).join(join)
            : items.map(function (it) { return pct(it.value, reserved); }).join(join);
        } else {
          const flat = items.map(function (it) { return pct(it.value, reserved); }).join(",");
          piece = named ? name + "=" + flat : flat;
        }
      } else {
        const val = items[0] ? items[0].value : "";
        piece = named ? name + "=" + pct(val, reserved) : pct(val, reserved);
      }
      if (first) { out += firstPrefix; first = false; }
      else { out += join; }
      out += piece;
    }
    return out;
  }
  function itemsOf(v, mod) {
    if (v.type === "scalar") {
      let s = String(v.value);
      if (mod.charAt(0) === ":") s = s.slice(0, parseInt(mod.slice(1), 10));
      return [{ name: "", value: s }];
    }
    if (v.type === "list") {
      return v.value.map(function (x) { return { name: "", value: String(x) }; });
    }
    if (v.type === "pairs") {
      return v.value.map(function (kv) { return { name: String(kv[0]), value: String(kv[1]) }; });
    }
    return [];
  }
  function expandTemplate(tpl, vars) {
    let result = "", i = 0;
    while (i < tpl.length) {
      if (tpl[i] === "{") {
        const end = tpl.indexOf("}", i);
        if (end === -1) { result += tpl.slice(i); break; }
        result += expandExpr(tpl.slice(i + 1, end), vars);
        i = end + 1;
      } else { result += tpl[i]; i++; }
    }
    return result;
  }
  function jsonToVars(text) {
    const obj = JSON.parse(text);
    const vars = {};
    for (const k of Object.keys(obj)) {
      const val = obj[k];
      if (Array.isArray(val)) {
        if (val.length && typeof val[0] === "object" && val[0] !== null && !Array.isArray(val[0])) {
          vars[k] = { type: "pairs", value: val.map(function (e) { return [e[0], e[1]]; }) };
        } else {
          vars[k] = { type: "list", value: val };
        }
      } else if (val && typeof val === "object") {
        vars[k] = { type: "pairs", value: Object.keys(val).map(function (kk) { return [kk, val[kk]]; }) };
      } else {
        vars[k] = { type: "scalar", value: val };
      }
    }
    return vars;
  }
  const tplIn = document.getElementById("tpl-in");
  const tplVars = document.getElementById("tpl-vars");
  const tplOut = document.getElementById("tpl-out");
  const tplGo = document.getElementById("tpl-go");
  if (tplGo) tplGo.addEventListener("click", function () {
    try {
      const vars = jsonToVars(tplVars.value);
      setOut(tplOut, expandTemplate(tplIn.value.trim(), vars));
    } catch (e) {
      setOut(tplOut, "Variables: " + e.message, true);
    }
  });

  /* ---------------- Plain URL splitter ------------------------------ */
  const urlIn = document.getElementById("url-in");
  const urlOut = document.getElementById("url-out");
  const urlGo = document.getElementById("url-go");
  if (urlGo) urlGo.addEventListener("click", function () {
    const s = urlIn.value.trim();
    const m = s.match(/^(([^:/?#]+):)?(\/\/([^/?#]*))?([^?#]*)(\?([^#]*))?(#(.*))?$/);
    if (!m) { setOut(urlOut, "Could not parse.", true); return; }
    const authority = m[4] || "";
    let userinfo = "", host = authority, port = "";
    const at = authority.lastIndexOf("@");
    if (at !== -1) { userinfo = authority.slice(0, at); host = authority.slice(at + 1); }
    const colon = host.lastIndexOf(":");
    if (colon !== -1 && host[colon + 1] !== "]") {
      const maybe = host.slice(colon + 1);
      if (/^\d+$/.test(maybe)) { port = maybe; host = host.slice(0, colon); }
    }
    const lines = [
      ["scheme", m[2] || ""], ["userinfo", userinfo], ["host", host],
      ["port", port], ["path", m[5] || ""], ["query", m[7] || ""], ["fragment", m[9] || ""]
    ];
    setOut(urlOut, lines.map(function (l) {
      return l[0] + " = " + (l[1] === "" ? "(none)" : JSON.stringify(l[1]));
    }).join("\n"));
  });

  /* ---------------- Copy-to-clipboard for code cards ----------------- */
  Array.prototype.forEach.call(document.querySelectorAll(".copy"), function (btn) {
    btn.addEventListener("click", function () {
      const card = btn.closest(".codecard");
      const pre = card ? card.querySelector("pre") : null;
      const text = pre ? pre.innerText : "";
      const done = function () {
        btn.classList.add("copied");
        setTimeout(function () { btn.classList.remove("copied"); }, 1400);
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
  runIdna();
})();
