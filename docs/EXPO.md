# Expo Integration

`react-native-fast-video` is an Expo Module and autolinks in Expo prebuild/bare projects.

## Managed workflow

```bash
npx expo install expo-modules-core
npm install react-native-fast-video
npx expo prebuild
npx expo run:android
# or
npx expo run:ios
```

Because this package adds Kotlin, Swift, Objective-C++ and C++, it requires a development build. Expo Go cannot load arbitrary native modules.

## Config plugin

```json
{
  "expo": {
    "plugins": [
      [
        "react-native-fast-video",
        {
          "supportsPictureInPicture": true,
          "backgroundPlayback": true
        }
      ]
    ]
  }
}
```

The plugin configures platform declarations. It does not by itself implement a complete Android background media service; that remains a tracked feature.
