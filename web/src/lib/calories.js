/**
 * Calories for a workout, best source first:
 * 1. Active calories typed in from the Apple Watch workout summary.
 * 2. Average heart rate (typed in from the Watch) with Keytel et al. (2005).
 * 3. A 5-MET strength-training estimate from duration and body weight.
 */
export function estimateCalories({ minutes, weightKg, age, sex, watchCalories, avgHeartRate }) {
  minutes = Math.max(minutes, 1);
  if (watchCalories > 0) return { kcal: watchCalories, source: 'watch' };
  if (avgHeartRate > 0) {
    const perMin = sex === 'female'
      ? (-20.4022 + 0.4472 * avgHeartRate - 0.1263 * weightKg + 0.074 * age) / 4.184
      : (-55.0969 + 0.6309 * avgHeartRate + 0.1988 * weightKg + 0.2017 * age) / 4.184;
    return { kcal: Math.max(perMin, 0) * minutes, source: 'heartRate' };
  }
  return { kcal: (5 * 3.5 * weightKg) / 200 * minutes, source: 'estimate' };
}

export const SOURCE_LABEL = {
  watch: 'From your Apple Watch',
  heartRate: 'From your average heart rate',
  estimate: 'Estimated from time and body weight',
};
