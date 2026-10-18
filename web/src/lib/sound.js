let ctx = null;

/** Unlocks audio on the first tap (iOS only plays sound after a user gesture). */
export function unlockAudio() {
  try {
    ctx ||= new (window.AudioContext || window.webkitAudioContext)();
    if (ctx.state === 'suspended') ctx.resume();
  } catch { /* no audio */ }
}

/** Three short beeps when rest is over. */
export function beep() {
  try {
    unlockAudio();
    const t0 = ctx.currentTime;
    [0, 0.25, 0.5].forEach((d, i) => {
      const o = ctx.createOscillator(), g = ctx.createGain();
      o.frequency.value = i === 2 ? 1320 : 880;
      g.gain.setValueAtTime(0.0001, t0 + d);
      g.gain.exponentialRampToValueAtTime(0.4, t0 + d + 0.02);
      g.gain.exponentialRampToValueAtTime(0.0001, t0 + d + 0.18);
      o.connect(g).connect(ctx.destination);
      o.start(t0 + d); o.stop(t0 + d + 0.2);
    });
    navigator.vibrate?.([200, 100, 200]);
  } catch { /* ignore */ }
}
