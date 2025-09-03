// Reexport the native module. On web, it will be resolved to ExpoObjectTrackerModule.web.ts
// and on native platforms to ExpoObjectTrackerModule.ts
export { default } from './ExpoObjectTrackerModule';
export { default as VideoObjectTracker } from './VideoObjectTracker';
export { VideoObjectTracker as VideoObjectTrackerClass } from './VideoObjectTracker';
export * from './ExpoObjectTracker.types';
