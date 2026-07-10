/* 二蛋 · 插画骨骼动画引擎(DOM-SVG,无第三方依赖)
 * 对精美插画 dragon.svg 的分组做逐帧变换:
 *   whole 蹦跳/前倾/挤压/朝向, head 点头, tail 摆动, arms 摆臂,
 *   eyes 眨眼+眼神, mouth 说话, body/belly 呼吸。
 * 对外:window.PetDragon = { setMotion(state,dir), setTalking(on), poke(), setSleep(on), ready }
 */
(() => {
  const wrap = document.getElementById('dragon-wrap');
  // 各分组的旋转/缩放支点(dragon.svg 的用户坐标系 viewBox 0..400)
  const PIV = {
    whole: [200, 372], head: [200, 250], tail: [258, 316],
    arms: [200, 268], eyes: [200, 158], mouth: [200, 222], body: [200, 300],
  };
  let svg = null, G = {};

  function attach() {
    svg = wrap.querySelector('svg');
    if (!svg) return false;
    G.whole = svg.querySelector('g');                 // 最外层包裹组
    for (const id of ['head', 'tail', 'arms', 'eyes', 'mouth', 'body', 'belly'])
      G[id] = svg.getElementById(id);
    return !!G.whole;
  }

  // ---------- 状态 ----------
  let state = 'idle', dir = 1, phase = 0, t = 0, sleeping = false;
  let jumpT = -1, pokeT = -1, talkUntil = 0;
  let blinkT = 1.5 + Math.random() * 3, blinkV = 0;
  let lookX = 0, lookTarget = 0, lookTimer = 2;

  // 自发小动作(手势):待机时偶尔触发一个,让二蛋更活泼。key=名字,value=时长(秒)
  const GESTURES = { stretch: 1.6, yawn: 1.9, wave: 1.5, spin: 0.9, happy: 1.1, wiggle: 1.5 };
  let gesture = null, gTime = 0;
  function playGesture(name) { if (sleeping || !GESTURES[name]) return; gesture = name; gTime = 0; }

  function setMotion(s, d) {
    if (s === 'jump' && state !== 'jump') jumpT = 0;
    if (s !== 'idle') gesture = null;                 // 走/跑/跳时打断手势
    state = s; if (d === 1 || d === -1) dir = d;
  }

  function T(el, str) { if (el) el.setAttribute('transform', str); }
  function squash(pivot, sx, sy) {
    const [px, py] = pivot;
    return `translate(${px},${py}) scale(${sx},${sy}) translate(${-px},${-py})`;
  }
  function rot(pivot, deg) { return `rotate(${deg},${pivot[0]},${pivot[1]})`; }

  let last = performance.now();
  function frame(nowMs) {
    requestAnimationFrame(frame);
    if (!svg && !attach()) return;
    const dt = Math.min(0.05, (nowMs - last) / 1000); last = nowMs; t += dt;

    // 眨眼
    blinkT -= dt;
    if (blinkT <= 0) { blinkV = 1; blinkT = 2 + Math.random() * 4; }
    blinkV = Math.max(0, blinkV - dt * 7);
    let eyeSy = sleeping ? 0.08 : (1 - blinkV * 0.92);

    // 眼神游移
    lookTimer -= dt;
    if (lookTimer <= 0) { lookTarget = (Math.random() - 0.5) * 8; lookTimer = 1.5 + Math.random() * 3; }
    lookX += (lookTarget - lookX) * dt * 4;

    let bob = 0, lean = 0, sx = 1, sy = 1, headR = 0, headY = 0, tailR = 0, armR = 0, breath = Math.sin(t * 2) * 0.02;
    let spinSX = 1, gMouth = 0;   // spinSX: 转圈用的水平翻转;gMouth: 手势叠加的张嘴幅度

    if (sleeping) {
      breath = Math.sin(t * 1.1) * 0.035; headR = 5; tailR = Math.sin(t * 0.8) * 4;
    } else if (state === 'walk' || state === 'run') {
      const fast = state === 'run';
      phase += dt * (fast ? 13 : 8);
      bob = -Math.abs(Math.sin(phase)) * (fast ? 11 : 6);
      lean = dir * (fast ? 9 : 5);
      headR = Math.sin(phase * 2) * (fast ? 5 : 3);
      tailR = Math.sin(phase * 2) * (fast ? 20 : 13);
      armR = Math.sin(phase) * (fast ? 16 : 10);
      sx = 1 + Math.abs(Math.sin(phase)) * 0.03; sy = 1 - Math.abs(Math.sin(phase)) * 0.03;
    } else { // idle
      lean = Math.sin(t * 1.5) * 2.2;
      headR = Math.sin(t * 1.2) * 3;
      tailR = Math.sin(t * 1.6) * 8;
      armR = Math.sin(t * 1.5) * 3;
      headY = Math.sin(t * 2) * 1.5;
    }

    // 自发小动作:在待机基础上叠加一段有始有终的表演(bell 曲线 ease 保证平滑起收)
    if (gesture) {
      gTime += dt;
      const dur = GESTURES[gesture];
      const p = Math.min(1, gTime / dur);
      const ease = Math.sin(p * Math.PI);              // 0→1→0
      if (gesture === 'stretch') {                     // 伸懒腰:拔高、举手、头后仰
        sy = 1 + ease * 0.20; sx = 1 - ease * 0.10; bob = -ease * 10; armR = -ease * 46; headR = -ease * 14;
      } else if (gesture === 'yawn') {                 // 打哈欠:张大嘴、眯眼、头微仰
        gMouth = ease * 1.7; eyeSy = Math.min(eyeSy, 1 - ease * 0.85); headR = ease * 9; headY = ease * 3;
      } else if (gesture === 'wave') {                 // 挥手:举臂快速摆动
        armR = -32 - Math.sin(p * Math.PI * 6) * 22; lean = dir * 4; headR = -4; tailR = Math.sin(t * 3) * 8;
      } else if (gesture === 'spin') {                 // 转圈:水平翻转一周,带一点腾空
        spinSX = Math.cos(p * Math.PI * 2); bob = -Math.sin(p * Math.PI) * 8;
      } else if (gesture === 'happy') {                // 开心:连蹦两下、甩尾、举手
        const h = Math.abs(Math.sin(p * Math.PI * 2));
        bob = -h * 16; sy = 1 - h * 0.06; sx = 1 + h * 0.05; tailR = Math.sin(p * Math.PI * 8) * 22; armR = -h * 30; headR = Math.sin(p * Math.PI * 6) * 4;
      } else if (gesture === 'wiggle') {               // 扭一扭:左右摇摆 + 甩尾
        lean = Math.sin(p * Math.PI * 6) * 10; tailR = Math.sin(p * Math.PI * 6) * 22; headR = -Math.sin(p * Math.PI * 6) * 6;
      }
      if (gTime >= dur) gesture = null;
    }

    // 跳跃时间线(垂直高度由原生窗口负责;这里做蓄力/腾空/落地的挤压与手臂)
    if (jumpT >= 0) {
      jumpT += dt;
      if (jumpT < 0.16) { sy = 0.82; sx = 1.14; bob = 6; armR = -20; }         // 蓄力下蹲
      else if (jumpT < 0.72) { sy = 1.12; sx = 0.92; bob = -6; armR = -34; tailR = -18; } // 腾空拉伸
      else if (jumpT < 0.92) { sy = 0.9; sx = 1.1; bob = 4; }                   // 落地缓冲
      else jumpT = -1;
    }
    // 戳一下:弹跳
    if (pokeT >= 0) { pokeT += dt; const k = Math.sin((pokeT / 0.45) * Math.PI); sy = 1 + k * 0.14; sx = 1 - k * 0.11; if (pokeT > 0.45) pokeT = -1; }

    // 说话:嘴开合(手势的张嘴幅度取较大值叠加)
    const talking = t < talkUntil;
    const mouthSy = Math.max(talking ? (1 + Math.abs(Math.sin(t * 20)) * 0.9) : 1, 1 + gMouth);

    // 组合变换
    T(G.whole, `translate(0,${bob}) ${rot(PIV.whole, lean)} ${squash(PIV.whole, dir * sx * spinSX, sy)}`);
    T(G.head, `${rot(PIV.head, headR)} translate(0,${headY})`);
    T(G.tail, rot(PIV.tail, tailR));
    T(G.arms, rot(PIV.arms, armR));
    T(G.eyes, `${squash(PIV.eyes, 1, eyeSy)} translate(${lookX},0)`);
    T(G.mouth, squash(PIV.mouth, 1, mouthSy));
    const bo = Math.sin(t * 2) * 0.018;
    T(G.body, squash(PIV.body, 1 + bo, 1 - bo));
    T(G.belly, squash(PIV.body, 1 + bo * 0.8, 1 - bo * 0.8));
  }

  function boot() {
    if (!attach()) { setTimeout(boot, 80); return; }
    requestAnimationFrame(frame);
    window.PetDragon = {
      setMotion,
      setTalking(on) { talkUntil = on ? t + 2.4 : 0; },
      poke() { pokeT = 0; },
      setSleep(on) { sleeping = on; if (on) state = 'idle'; },
      playGesture,
      ready: true,
    };
    window.dispatchEvent(new Event('petdragon-ready'));

    // 待机时每隔一会儿随机来一个小动作
    (function autoGesture() {
      const names = Object.keys(GESTURES);
      const tick = () => setTimeout(() => {
        if (!sleeping && state === 'idle' && !document.body.classList.contains('chat'))
          playGesture(names[Math.floor(Math.random() * names.length)]);
        tick();
      }, (12 + Math.random() * 16) * 1000);
      tick();
    })();
  }
  boot();
})();
