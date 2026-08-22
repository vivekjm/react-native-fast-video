import type { RefObject } from 'react';
import { Pressable, StyleSheet, Text, View, type ViewStyle } from 'react-native';

import type { FastVideoRef } from '../FastVideo.types';

export interface FastVideoControlsProps {
  player: RefObject<FastVideoRef | null>;
  positionMs: number;
  durationMs: number;
  isPlaying: boolean;
  isLive?: boolean;
  style?: ViewStyle;
}

export function FastVideoControls({
  player,
  positionMs,
  durationMs,
  isPlaying,
  isLive,
  style,
}: FastVideoControlsProps) {
  return (
    <View style={[styles.root, style]}>
      <ControlButton
        label={isPlaying ? 'Pause' : 'Play'}
        onPress={() => void (isPlaying ? player.current?.pause() : player.current?.play())}
      />
      <ControlButton label="−10s" onPress={() => void player.current?.seekBy(-10_000)} />
      <Text style={styles.time}>
        {format(positionMs)} / {isLive ? 'LIVE' : format(durationMs)}
      </Text>
      <ControlButton label="+10s" onPress={() => void player.current?.seekBy(10_000)} />
      {isLive ? <ControlButton label="Live" onPress={() => void player.current?.goToLive()} /> : null}
      <ControlButton label="PiP" onPress={() => void player.current?.enterPictureInPicture()} />
    </View>
  );
}

function ControlButton({ label, onPress }: { label: string; onPress: () => void }) {
  return (
    <Pressable accessibilityRole="button" onPress={onPress} style={styles.button}>
      <Text style={styles.label}>{label}</Text>
    </Pressable>
  );
}

function format(milliseconds: number): string {
  const seconds = Math.max(0, Math.floor(milliseconds / 1_000));
  const minutes = Math.floor(seconds / 60);
  const remainder = seconds % 60;
  return `${minutes}:${remainder.toString().padStart(2, '0')}`;
}

const styles = StyleSheet.create({
  root: {
    alignItems: 'center',
    flexDirection: 'row',
    gap: 8,
    padding: 8,
  },
  button: {
    backgroundColor: 'rgba(0,0,0,0.72)',
    borderRadius: 6,
    paddingHorizontal: 10,
    paddingVertical: 8,
  },
  label: { color: 'white', fontWeight: '600' },
  time: { color: 'white', flex: 1, textAlign: 'center' },
});
