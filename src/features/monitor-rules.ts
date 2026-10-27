/** A bounded, conservative guard against common catastrophic-backtracking patterns.
 * This is not a substitute for a time-limited regex engine; RSS titles are
 * additionally capped to bound the typical input size.
 */
const MAX_RULES = 64;
const MAX_PATTERN = 240;
const MAX_TITLE = 300;
export function safeMonitorPattern(pattern: string): boolean {
  if (!pattern || pattern.length > MAX_PATTERN) return false;
  // Nested repetitions, such as (a+)+, ([a-z]*){2,} or (.*)+.
  if (/\((?:\\.|\[[^\]]*\]|[^()])*[+*?](?:\\.|\[[^\]]*\]|[^()])*\)\s*(?:[+*?]|\{\d+,?\d*\})/.test(pattern)) return false;
  // Backreferences with repetitions and nested regex lookarounds are
  // particularly hard to predict: reject them for monitoring rules.
  if (/\\[1-9]/.test(pattern) || /\(\?(?:<=|<!)/.test(pattern)) return false;
  // Bound quantifiers as well; enormous repeats waste compilation and match time.
  for (const match of pattern.matchAll(/\{(\d+)(?:,(\d*))?\}/g)) {
    if (Number(match[1]) > 1000 || (match[2] && Number(match[2]) > 1000)) return false;
  }
  // Typical ambiguous alternations, such as (a|aa)+ or (foo|foobar)*.
  const alternatives = pattern.matchAll(/\(([^()[\]]+\|[^()[\]]+)\)\s*(?:[+*?]|\{\d+,?\d*\})/g);
  for (const [, alternativesText] of alternatives) {
    const branches = alternativesText.split('|');
    if (branches.some((branch, i) => branches.some((other, j) => i !== j && (!branch || !other || branch.startsWith(other) || other.startsWith(branch))))) return false;
  }
  return true;
}

export function compileMonitorRules(value: string) {
  const errors: string[] = [];
  const lines = value.split('\n').map(label => label.trim()).filter(Boolean);
  const rules = lines.slice(0, MAX_RULES).map((label, index) => {
    try {
      let source = label, flags = 'i';
      if (label.startsWith('/')) {
        const end = label.lastIndexOf('/');
        if (end < 1) throw new Error('invalid delimiter');
        source = label.slice(1, end);
        flags = label.slice(end + 1);
      }
      if (!safeMonitorPattern(source)) throw new Error('unsafe rule');
      const pattern = new RegExp(source, flags);
      return { label, color: String(index % 4), matches: (text: string) => { pattern.lastIndex = 0; return pattern.test(text.slice(0, MAX_TITLE)); } };
    } catch { errors.push(label); return null; }
  }).filter((rule): rule is NonNullable<typeof rule> => rule !== null);
  errors.push(...lines.slice(MAX_RULES));
  return { rules, errors };
}
