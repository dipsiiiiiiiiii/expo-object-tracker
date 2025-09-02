import { registerWebModule, NativeModule } from 'expo';

import { ExpoObjectTrackerModuleEvents } from './ExpoObjectTracker.types';

class ExpoObjectTrackerModule extends NativeModule<ExpoObjectTrackerModuleEvents> {
  PI = Math.PI;
  async setValueAsync(value: string): Promise<void> {
    this.emit('onChange', { value });
  }
  hello() {
    return 'Hello world! 👋';
  }
}

export default registerWebModule(ExpoObjectTrackerModule, 'ExpoObjectTrackerModule');
