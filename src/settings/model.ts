import type { Feature, Settings } from '../core/types';

/** Compare declared primitive settings without depending on object key order. */
export function changedFeatures(features: Feature[], baseline: Settings, draft: Settings): Set<string> {
  return new Set(features.filter(feature => Object.keys(feature.defaults).some(key =>
    baseline[feature.id]?.[key] !== draft[feature.id]?.[key],
  )).map(feature => feature.id));
}

/** Keep settings changed by other panels/tabs while this draft was being edited. */
export function mergeSettings(features: Feature[], baseline: Settings, draft: Settings, latest: Settings): Settings {
  const merged = structuredClone(latest);
  for (const feature of features) {
    for (const key of Object.keys(feature.defaults)) {
      if (draft[feature.id]?.[key] !== baseline[feature.id]?.[key]) {
        merged[feature.id][key] = draft[feature.id][key];
      }
    }
  }
  return merged;
}

export function matchesSearch(text: string, query: string): boolean {
  return query.toLocaleLowerCase().trim().split(/\s+/).every(word => text.includes(word));
}
