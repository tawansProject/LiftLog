// Front / back body map: which drawn region each exercise-library muscle lights up,
// and the figure geometry (same shapes as the native app's BodyMapView).

export const REGION_LABELS = {
  traps: 'Traps', frontDelts: 'Front shoulders', rearDelts: 'Rear shoulders', chest: 'Chest', biceps: 'Biceps',
  triceps: 'Triceps', forearms: 'Forearms', abs: 'Abs', obliques: 'Obliques', upperBack: 'Upper back', lats: 'Lats',
  lowerBack: 'Lower back', glutes: 'Glutes', quads: 'Quads', adductors: 'Inner thighs', hamstrings: 'Hamstrings',
  calves: 'Calves', shins: 'Shins',
};

const MUSCLE_REGIONS = [
  [['pectorals', 'chest', 'upper chest', 'lower chest'], ['chest']],
  [['serratus anterior'], ['obliques']],
  [['deltoids', 'delts', 'shoulders'], ['frontDelts', 'rearDelts']],
  [['front deltoids', 'anterior deltoids'], ['frontDelts']],
  [['rear deltoids', 'posterior deltoids'], ['rearDelts']],
  [['rotator cuff'], ['rearDelts', 'upperBack']],
  [['biceps', 'brachialis'], ['biceps']],
  [['triceps'], ['triceps']],
  [['forearms', 'wrist flexors', 'wrist extensors', 'grip muscles', 'wrists', 'hands'], ['forearms']],
  [['abdominals', 'abs', 'core', 'lower abs'], ['abs']],
  [['obliques'], ['obliques']],
  [['hip flexors', 'adductors', 'groin', 'inner thighs'], ['adductors']],
  [['quadriceps', 'quads'], ['quads']],
  [['hamstrings'], ['hamstrings']],
  [['glutes', 'abductors'], ['glutes']],
  [['calves', 'soleus', 'gastrocnemius'], ['calves', 'shins']],
  [['tibialis anterior', 'shins', 'ankles', 'ankle stabilizers', 'feet'], ['shins']],
  [['latissimus dorsi', 'lats'], ['lats']],
  [['upper back', 'rhomboids', 'teres major'], ['upperBack']],
  [['trapezius', 'traps', 'levator scapulae'], ['traps']],
  [['erector spinae', 'lower back', 'spine'], ['lowerBack']],
  [['back'], ['lats', 'upperBack']],
];

export function regionsForMuscle(muscle) {
  const m = muscle.toLowerCase();
  return MUSCLE_REGIONS.find(([names]) => names.includes(m))?.[1] || [];
}

/** Per region: primary and secondary sets, score, and the share of the busiest region. */
export function bodyHeat(loads) {
  const heat = {};
  for (const l of loads) {
    for (const r of regionsForMuscle(l.muscle)) {
      const h = (heat[r] ||= { primary: 0, secondary: 0 });
      h.primary += l.primary;
      h.secondary += l.secondary;
    }
  }
  let max = 0;
  for (const h of Object.values(heat)) { h.score = h.primary + h.secondary * 0.5; max = Math.max(max, h.score); }
  for (const h of Object.values(heat)) h.share = max ? h.score / max : 0;
  return heat;
}

// Geometry in a 200 × 420 box. Shapes are the figure's left half, mirrored.
const W = 200;
const blob = (region, pts, mirrored = true) => ({ region, pts, mirrored });
const oval = (x, y, w, h, mirrored = true) => ({ region: null, oval: [x, y, w, h], mirrored });

const SILHOUETTE_LEFT = [
  [100, 48], [89, 50], [88, 64], [70, 70], [53, 77], [46, 96], [44, 130], [43, 152], [37, 184],
  [34, 208], [31, 230], [38, 243], [47, 238], [49, 214], [55, 190], [61, 166], [63, 134], [66, 126],
  [66, 142], [70, 168], [66, 192], [62, 224], [64, 262], [69, 292], [64, 320], [63, 345], [67, 382],
  [61, 402], [64, 414], [87, 414], [86, 390], [86, 350], [87, 315], [88, 296], [92, 262], [95, 236], [100, 216],
];
export const SILHOUETTE = [...SILHOUETTE_LEFT, ...SILHOUETTE_LEFT.slice(1, -1).reverse().map(([x, y]) => [W - x, y])];

const FRAME = [
  oval(80, 6, 40, 48, false),
  blob(null, [[92, 50], [108, 50], [110, 66], [90, 66]], false),
  oval(34, 214, 14, 26),
  oval(69, 293, 18, 17),
  blob(null, [[70, 388], [62, 404], [66, 412], [86, 412], [85, 390]]),
];
const FOREARM = blob('forearms', [[46, 164], [40, 184], [37, 208], [44, 212], [53, 192], [59, 166]]);

export const FRONT = [...FRAME,
  blob('traps', [[91, 60], [74, 70], [69, 76], [88, 74]]),
  blob('frontDelts', [[70, 74], [56, 80], [49, 96], [53, 113], [64, 104], [72, 88]]),
  blob('chest', [[98, 78], [76, 78], [66, 94], [68, 112], [82, 120], [98, 116]]),
  blob('biceps', [[52, 116], [46, 132], [45, 150], [52, 161], [60, 148], [62, 124]]),
  FOREARM,
  blob('abs', [[86, 122], [98, 122], [98, 139], [86, 139]]),
  blob('abs', [[86, 141], [98, 141], [98, 158], [86, 158]]),
  blob('abs', [[86, 160], [98, 160], [98, 177], [86, 177]]),
  blob('abs', [[86, 179], [98, 179], [98, 202], [89, 196]]),
  blob('obliques', [[84, 124], [72, 118], [67, 140], [71, 168], [80, 188], [84, 160]]),
  blob('quads', [[87, 198], [70, 190], [63, 224], [65, 262], [73, 290], [86, 292], [90, 262], [88, 226]]),
  blob('adductors', [[99, 210], [93, 206], [90, 236], [94, 262], [99, 250]]),
  blob('shins', [[70, 312], [65, 340], [69, 380], [78, 385], [84, 350], [85, 314]]),
];

export const BACK = [...FRAME,
  blob('traps', [[100, 56], [90, 62], [70, 76], [84, 84], [96, 104], [100, 114]]),
  blob('rearDelts', [[68, 78], [56, 82], [49, 98], [53, 113], [64, 102], [72, 88]]),
  blob('upperBack', [[84, 88], [72, 92], [69, 107], [82, 117], [94, 110]]),
  blob('lats', [[70, 112], [64, 128], [70, 152], [84, 172], [90, 168], [90, 140], [82, 120]]),
  blob('lowerBack', [[99, 124], [94, 128], [92, 168], [90, 194], [99, 198]]),
  blob('triceps', [[52, 114], [46, 130], [45, 150], [52, 161], [62, 150], [62, 122]]),
  FOREARM,
  blob('glutes', [[99, 200], [84, 196], [70, 204], [67, 226], [80, 241], [99, 237]]),
  blob('hamstrings', [[96, 244], [80, 242], [68, 248], [65, 272], [72, 293], [86, 295], [94, 276]]),
  blob('calves', [[70, 311], [63, 330], [67, 360], [76, 381], [84, 360], [86, 330], [84, 312]]),
];

/** Smooth closed SVG path through the midpoints, each point acting as the curve's control. */
export function smoothPath(pts) {
  const mid = (a, b) => [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2];
  const start = mid(pts[pts.length - 1], pts[0]);
  let d = `M${start[0]} ${start[1]}`;
  pts.forEach((p, i) => { const m = mid(p, pts[(i + 1) % pts.length]); d += `Q${p[0]} ${p[1]} ${m[0]} ${m[1]}`; });
  return `${d}Z`;
}

/** Every drawn shape of a side, mirrored halves included: { region, d } or { region, ellipse }. */
export function shapes(side) {
  const out = [];
  for (const part of side === 'front' ? FRONT : BACK) {
    if (part.oval) {
      const [x, y, w, h] = part.oval;
      out.push({ region: null, ellipse: [x + w / 2, y + h / 2, w / 2, h / 2] });
      if (part.mirrored) out.push({ region: null, ellipse: [W - x - w / 2, y + h / 2, w / 2, h / 2] });
    } else {
      out.push({ region: part.region, d: smoothPath(part.pts) });
      if (part.mirrored) out.push({ region: part.region, d: smoothPath(part.pts.map(([x, y]) => [W - x, y])) });
    }
  }
  return out;
}
