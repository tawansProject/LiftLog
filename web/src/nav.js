import { useEffect, useState } from 'preact/hooks';

// Tiny navigation: tabs plus a stack of full-screen pages on top.
let nav = { tab: 'workouts', stack: [] };
const subs = new Set();
const emit = () => subs.forEach((f) => f(nav));

export function useNav() {
  const [n, set] = useState(nav);
  useEffect(() => { subs.add(set); return () => subs.delete(set); }, []);
  return n;
}

export const setTab = (tab) => { nav = { tab, stack: [] }; emit(); };
export const push = (page) => { nav = { ...nav, stack: [...nav.stack, { key: Math.random(), ...page }] }; emit(); };
export const pop = (n = 1) => { nav = { ...nav, stack: nav.stack.slice(0, Math.max(0, nav.stack.length - n)) }; emit(); };
export const popTo = (type) => {
  const i = nav.stack.findIndex((p) => p.type === type);
  nav = { ...nav, stack: i < 0 ? [] : nav.stack.slice(0, i + 1) };
  emit();
};
export const clear = () => { nav = { ...nav, stack: [] }; emit(); };

let toastFn = null;
export const setToaster = (f) => { toastFn = f; };
export const toast = (msg) => toastFn?.(msg);
