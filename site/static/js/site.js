(function () {
  'use strict';
  var reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* ---------- scroll reveal ---------- */
  var reveals = document.querySelectorAll('.reveal');
  if (reduce || !('IntersectionObserver' in window)) {
    reveals.forEach(function (el) { el.classList.add('is-in'); });
  } else {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) { e.target.classList.add('is-in'); io.unobserve(e.target); }
      });
    }, { rootMargin: '0px 0px -10% 0px', threshold: 0.1 });
    reveals.forEach(function (el) { io.observe(el); });
  }

  /* ---------- mouse-follow glow on cards ---------- */
  document.querySelectorAll('[data-glow-card]').forEach(function (card) {
    card.addEventListener('pointermove', function (ev) {
      var r = card.getBoundingClientRect();
      card.style.setProperty('--mx', ((ev.clientX - r.left) / r.width * 100).toFixed(2) + '%');
      card.style.setProperty('--my', ((ev.clientY - r.top) / r.height * 100).toFixed(2) + '%');
    });
  });

  /* ---------- hero terminal ---------- */
  var term = document.querySelector('[data-terminal]');
  if (term) {
    var cmdEl = term.querySelector('[data-t-cmd]');
    var caret = term.querySelector('[data-t-caret]');
    var out = term.querySelector('[data-t-out]');
    var command = '/intake-oss "add a sum command that adds its integer arguments"';
    var script = [
      ['<span class="t-k">saw</span>     a sentence describing a change', 500],
      ['<span class="t-k">intent</span>  code · one ticket', 220],
      ['<span class="t-k">next</span>    create LOCAL-1, run prepare', 220],
      ['', 400],
      ['<span class="t-dim">LOCAL-1</span>  <span class="t-stage">prepare</span>     r1  cartographer · decomposer → 1 task', 900],
      ['<span class="t-dim">LOCAL-1</span>  <span class="t-stage">spec-task</span>   r1  spec ✓  intent ✓  critic ✓  build ✓  qa ✓  mutation 94%', 1500],
      ['<span class="t-dim">LOCAL-1</span>  <span class="t-stage">verify</span>      r1  fuzzer · attacker · stranger', 1300],
      ['<span class="t-hit"><span class="t-bad">FINDINGS 1</span>  sum abc → traceback, not a message  <span class="t-dim">(fuzzer)</span></span>', 700],
      ['<span class="t-dim">LOCAL-1</span>  <span class="t-stage">prepare</span>     r2  reading finding f-3a9c', 900],
      ['<span class="t-dim">LOCAL-1</span>  <span class="t-stage">spec-task</span>   r2  spec ✓  build ✓  qa ✓  burn-in ✓', 1400],
      ['<span class="t-dim">LOCAL-1</span>  <span class="t-stage">verify</span>      r2  <span class="t-ok">CLEAN</span>', 900],
      ['<span class="t-dim">LOCAL-1</span>  <span class="t-stage">pr</span>          #12 draft · body from intake, build, qa', 800],
      ['<span class="t-dim">LOCAL-1</span>  <span class="t-stage">nurse</span>       ci green · 0 open comments · sanity MATCH', 1100],
      ['<span class="t-dim">LOCAL-1</span>  <span class="t-stage">merge</span>       <span class="t-warn">gated</span>  → /intake-oss LOCAL-1 go', 2600]
    ];
    var timer = null;
    function clear() { if (timer) { clearTimeout(timer); timer = null; } }
    function run() {
      clear();
      cmdEl.textContent = '';
      out.innerHTML = '';
      caret.classList.remove('is-hidden');
      if (reduce) {
        cmdEl.textContent = command;
        caret.classList.add('is-hidden');
        script.forEach(function (s) { var d = document.createElement('div'); d.innerHTML = s[0] || '&nbsp;'; out.appendChild(d); });
        return;
      }
      var i = 0;
      function type() {
        if (i <= command.length) {
          cmdEl.textContent = command.slice(0, i++);
          timer = setTimeout(type, 28 + Math.random() * 40);
        } else {
          timer = setTimeout(function () { caret.classList.add('is-hidden'); emit(0); }, 420);
        }
      }
      function emit(k) {
        if (k >= script.length) { timer = setTimeout(run, 3200); return; }
        var d = document.createElement('div');
        d.innerHTML = script[k][0] || '&nbsp;';
        out.appendChild(d);
        timer = setTimeout(function () { emit(k + 1); }, script[k][1]);
      }
      type();
    }
    if ('IntersectionObserver' in window && !reduce) {
      var tio = new IntersectionObserver(function (entries) {
        entries.forEach(function (e) {
          if (e.isIntersecting) { if (!timer) run(); } else { clear(); }
        });
      }, { threshold: 0.3 });
      tio.observe(term);
    } else {
      run();
    }
  }

  /* ---------- pipeline animation ---------- */
  var pipe = document.querySelector('[data-pipeline]');
  if (pipe) {
    var svg = pipe.querySelector('svg');
    var token = pipe.querySelector('[data-token]');
    var pMain = pipe.querySelector('[data-path-main]');
    var pLoop = pipe.querySelector('[data-path-loop]');
    var pTail = pipe.querySelector('[data-path-tail]');
    var loopTrack = pipe.querySelector('[data-loop-track]');
    var vFind = pipe.querySelector('[data-verdict-findings]');
    var vClean = pipe.querySelector('[data-verdict-clean]');
    var hudRound = pipe.querySelector('[data-hud-round]');
    var hudStage = pipe.querySelector('[data-hud-stage]');
    var hudVerdict = pipe.querySelector('[data-hud-verdict]');
    var toggle = pipe.querySelector('[data-pipeline-toggle]');
    var nodes = {};
    pipe.querySelectorAll('[data-node]').forEach(function (n) { nodes[n.getAttribute('data-node')] = n; });

    // Nodes along each path, with the fraction of the path at which the token reaches them.
    function stops(path, names) {
      var L = path.getTotalLength();
      return names.map(function (name) {
        var g = nodes[name];
        var m = /translate\(([-\d.]+)\s+([-\d.]+)\)/.exec(g.getAttribute('transform'));
        var cx = parseFloat(m[1]), cy = parseFloat(m[2]);
        // find the closest point on the path by sampling
        var best = 0, bestD = Infinity;
        for (var s = 0; s <= 200; s++) {
          var pt = path.getPointAtLength(L * s / 200);
          var d = (pt.x - cx) * (pt.x - cx) + (pt.y - cy) * (pt.y - cy);
          if (d < bestD) { bestD = d; best = s / 200; }
        }
        return { name: name, at: best };
      });
    }
    var mainStops = stops(pMain, ['input', 'classify', 'ticket', 'prepare', 'spec', 'verify']);
    var loopStops = stops(pLoop, ['prepare']);
    var tailStops = stops(pTail, ['pr', 'nurse', 'merge', 'sentinel', 'learn', 'done']);

    var speed = 170; // px per second
    var paused = false, raf = null, visible = false;

    function setToken(path, t) {
      var pt = path.getPointAtLength(path.getTotalLength() * t);
      token.setAttribute('cx', pt.x); token.setAttribute('cy', pt.y);
    }
    function clearNodes() {
      Object.keys(nodes).forEach(function (k) { nodes[k].classList.remove('is-active', 'is-done'); });
    }
    function activate(name) {
      Object.keys(nodes).forEach(function (k) {
        if (nodes[k].classList.contains('is-active')) { nodes[k].classList.remove('is-active'); nodes[k].classList.add('is-done'); }
      });
      nodes[name].classList.add('is-active');
      hudStage.textContent = name === 'learn' ? 'learner' : name === 'verify' ? 'adversarial-review' : name;
    }
    function wait(ms) {
      return new Promise(function (res) {
        var t0 = null;
        function step(ts) {
          if (!visible || paused) { t0 = null; raf = requestAnimationFrame(step); return; }
          if (t0 === null) t0 = ts;
          if (ts - t0 >= ms) res(); else raf = requestAnimationFrame(step);
        }
        raf = requestAnimationFrame(step);
      });
    }
    function travel(path, stopList, from) {
      return new Promise(function (res) {
        var L = path.getTotalLength();
        var dur = (L * (1 - from)) / speed * 1000;
        var t0 = null, last = null, elapsed = 0, hit = {};
        stopList.forEach(function (s) { if (s.at <= from + 1e-6) hit[s.name] = true; });
        function step(ts) {
          if (!visible || paused) { last = null; raf = requestAnimationFrame(step); return; }
          if (last !== null) elapsed += ts - last;
          last = ts;
          var p = Math.min(1, elapsed / dur);
          var t = from + (1 - from) * p;
          setToken(path, t);
          stopList.forEach(function (s) {
            if (!hit[s.name] && t >= s.at - 0.004) { hit[s.name] = true; activate(s.name); }
          });
          if (p < 1) raf = requestAnimationFrame(step); else res();
        }
        raf = requestAnimationFrame(step);
      });
    }
    function reset() {
      clearNodes();
      token.classList.remove('is-findings', 'is-clean');
      vFind.classList.remove('is-on'); vClean.classList.remove('is-on');
      loopTrack.classList.remove('is-active');
      hudRound.textContent = '1';
      hudVerdict.textContent = '—'; hudVerdict.className = 'hud-v';
      setToken(pMain, 0);
    }
    function cycle() {
      reset();
      return wait(600)
        .then(function () { return travel(pMain, mainStops, 0); })
        .then(function () { return wait(700); })
        .then(function () {
          // round 1: findings
          hudVerdict.textContent = 'FINDINGS 1'; hudVerdict.className = 'hud-v is-findings';
          vFind.classList.add('is-on'); loopTrack.classList.add('is-active'); token.classList.add('is-findings');
          return wait(900);
        })
        .then(function () { return travel(pLoop, loopStops, 0); })
        .then(function () {
          hudRound.textContent = '2'; hudVerdict.textContent = '—'; hudVerdict.className = 'hud-v';
          vFind.classList.remove('is-on'); loopTrack.classList.remove('is-active'); token.classList.remove('is-findings');
          nodes.prepare.classList.add('is-active');
          return wait(500);
        })
        .then(function () { return travel(pMain, mainStops.filter(function (s) { return s.name !== 'prepare'; }), mainStops[3].at); })
        .then(function () { return wait(700); })
        .then(function () {
          hudVerdict.textContent = 'CLEAN'; hudVerdict.className = 'hud-v is-clean';
          vClean.classList.add('is-on'); token.classList.add('is-clean');
          return wait(900);
        })
        .then(function () { return travel(pTail, tailStops, 0); })
        .then(function () { return wait(2600); })
        .then(cycle);
    }
    if (reduce) {
      // Static end state: every node lit, token parked at done.
      Object.keys(nodes).forEach(function (k) { nodes[k].classList.add('is-done'); });
      nodes.done.classList.add('is-active');
      vClean.classList.add('is-on');
      hudRound.textContent = '2'; hudStage.textContent = 'done'; hudVerdict.textContent = 'CLEAN'; hudVerdict.className = 'hud-v is-clean';
      setToken(pTail, 1);
      if (toggle) toggle.hidden = true;
    } else {
      if (toggle) {
        toggle.addEventListener('click', function () {
          paused = !paused;
          toggle.textContent = paused ? 'play' : 'pause';
          toggle.setAttribute('aria-label', paused ? 'Resume animation' : 'Pause animation');
        });
      }
      if ('IntersectionObserver' in window) {
        new IntersectionObserver(function (entries) {
          entries.forEach(function (e) { visible = e.isIntersecting; });
        }, { threshold: 0.2 }).observe(pipe);
      } else {
        visible = true;
      }
      cycle();
    }
  }
})();
