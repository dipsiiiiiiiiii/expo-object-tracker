// Reexport the native module. On web, it will be resolved to ExpoObjectTrackerModule.web.ts
// and on native platforms to ExpoObjectTrackerModule.ts
export { default } from './ExpoObjectTrackerModule';
export * from  './ExpoObjectTracker.types';
