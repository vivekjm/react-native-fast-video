# DRM Integration

## Widevine (Android)

```tsx
source={{
  uri: 'https://cdn.example.com/manifest.mpd',
  type: 'dash',
  drm: {
    type: 'widevine',
    licenseUrl: 'https://license.example.com/widevine',
    headers: { Authorization: 'Bearer …' },
    multiSession: false,
  },
}}
```

Widevine security level, codec support and maximum protected resolution are device-dependent. Use `getFastVideoCapabilities()` and validate with the actual provider.

## FairPlay Streaming (Apple)

```tsx
source={{
  uri: 'https://cdn.example.com/master.m3u8',
  type: 'hls',
  drm: {
    type: 'fairplay',
    certificateUrl: 'https://license.example.com/fps.cer',
    licenseUrl: 'https://license.example.com/fps',
    headers: { Authorization: 'Bearer …' },
    contentId: 'asset-123',
    licenseResponseType: 'raw',
  },
}}
```

FairPlay providers differ in SPC request encoding and CKC response format. The foundation supports raw and base64 CKC responses. Provider adapters and fixtures belong in separate, testable integrations rather than hard-coded assumptions in the player.

Never place long-lived DRM secrets in JavaScript or the app bundle.
