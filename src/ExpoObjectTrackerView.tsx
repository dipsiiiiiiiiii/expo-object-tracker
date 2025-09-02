import { requireNativeView } from 'expo';
import * as React from 'react';

import { ExpoObjectTrackerViewProps } from './ExpoObjectTracker.types';

const NativeView: React.ComponentType<ExpoObjectTrackerViewProps> =
  requireNativeView('ExpoObjectTracker');

export default function ExpoObjectTrackerView(props: ExpoObjectTrackerViewProps) {
  return <NativeView {...props} />;
}
