import {
  withAndroidManifest,
  withInfoPlist,
  type ConfigPlugin,
} from '@expo/config-plugins';

export interface ReactNativeFastVideoPluginOptions {
  supportsPictureInPicture?: boolean;
  backgroundPlayback?: boolean;
}

const withReactNativeFastVideo: ConfigPlugin<ReactNativeFastVideoPluginOptions | void> = (
  config,
  rawOptions
) => {
  const options = (rawOptions ?? {}) as ReactNativeFastVideoPluginOptions;
  const supportsPictureInPicture = options.supportsPictureInPicture ?? true;
  const backgroundPlayback = options.backgroundPlayback ?? false;

  config = withAndroidManifest(config, (androidConfig) => {
    const manifest = androidConfig.modResults.manifest as any;
    manifest['uses-permission'] ??= [];
    addPermission(manifest['uses-permission'], 'android.permission.INTERNET');

    if (backgroundPlayback) {
      addPermission(manifest['uses-permission'], 'android.permission.FOREGROUND_SERVICE');
      addPermission(manifest['uses-permission'], 'android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK');
      addPermission(manifest['uses-permission'], 'android.permission.POST_NOTIFICATIONS');
    }

    const application = manifest.application?.[0];
    const mainActivity = application?.activity?.find((activity) =>
      activity['intent-filter']?.some((filter) =>
        filter.action?.some((action) => action.$?.['android:name'] === 'android.intent.action.MAIN')
      )
    );

    if (mainActivity?.$ && supportsPictureInPicture) {
      mainActivity.$['android:supportsPictureInPicture'] = 'true';
      mainActivity.$['android:resizeableActivity'] = 'true';
      mainActivity.$['android:configChanges'] = appendConfigChanges(
        mainActivity.$['android:configChanges'],
        ['screenSize', 'smallestScreenSize', 'screenLayout', 'orientation']
      );
    }

    return androidConfig;
  });

  config = withInfoPlist(config, (iosConfig) => {
    if (backgroundPlayback || supportsPictureInPicture) {
      const modes = new Set<string>((iosConfig.modResults.UIBackgroundModes as string[] | undefined) ?? []);
      modes.add('audio');
      iosConfig.modResults.UIBackgroundModes = [...modes];
    }
    return iosConfig;
  });

  return config;
};

function addPermission(
  permissions: Array<{ $?: Record<string, string> }>,
  name: string
): void {
  if (!permissions.some((permission) => permission.$?.['android:name'] === name)) {
    permissions.push({ $: { 'android:name': name } });
  }
}

function appendConfigChanges(current: string | undefined, required: string[]): string {
  const values = new Set((current ?? '').split('|').filter(Boolean));
  required.forEach((value) => values.add(value));
  return [...values].join('|');
}

export default withReactNativeFastVideo;
