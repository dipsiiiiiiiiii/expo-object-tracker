import * as React from 'react';

import { ExpoObjectTrackerViewProps } from './ExpoObjectTracker.types';

export default function ExpoObjectTrackerView(props: ExpoObjectTrackerViewProps) {
  return (
    <div>
      <iframe
        style={{ flex: 1 }}
        src={props.url}
        onLoad={() => props.onLoad({ nativeEvent: { url: props.url } })}
      />
    </div>
  );
}
