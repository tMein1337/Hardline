import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../../core/util/snapshot_list.dart';
import 'voice_prefs_state.dart';

/// The audio hardware currently available.
@immutable
class AudioDevices {
  const AudioDevices({required this.inputs, required this.outputs});

  const AudioDevices.empty()
    : inputs = const ListSnapshot.empty(),
      outputs = const ListSnapshot.empty();

  final ListSnapshot<AudioDeviceRef> inputs;
  final ListSnapshot<AudioDeviceRef> outputs;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioDevices &&
          inputs == other.inputs &&
          outputs == other.outputs;

  @override
  int get hashCode => Object.hash(inputs, outputs);
}

/// Enumerates microphones and outputs, and refreshes when hardware changes.
///
/// A `StreamProvider` rather than a one-shot future because plugging in a
/// headset mid-call is completely normal, and a stale list would offer devices
/// that no longer exist while hiding the one just connected.
final audioDevicesProvider = StreamProvider<AudioDevices>((ref) {
  final controller = StreamController<AudioDevices>();

  Future<void> emit() async {
    if (controller.isClosed) return;
    try {
      final inputs = await lk.Hardware.instance.audioInputs();
      final outputs = await lk.Hardware.instance.audioOutputs();
      if (controller.isClosed) return;
      controller.add(
        AudioDevices(
          inputs: ListSnapshot([for (final d in inputs) _toRef(d)]),
          outputs: ListSnapshot([for (final d in outputs) _toRef(d)]),
        ),
      );
    } catch (error, stack) {
      debugPrint('[voice] enumerating devices failed: $error\n$stack');
      if (!controller.isClosed) controller.add(const AudioDevices.empty());
    }
  }

  final subscription = lk.Hardware.instance.onDeviceChange.stream.listen(
    (_) => emit(),
  );
  unawaited(emit());

  ref.onDispose(() {
    unawaited(subscription.cancel());
    unawaited(controller.close());
  });

  return controller.stream;
});

AudioDeviceRef _toRef(lk.MediaDevice device) =>
    AudioDeviceRef(deviceId: device.deviceId, label: device.label);

/// Resolves a remembered device against what is actually plugged in.
///
/// Matches on id first, then on label. The label fallback is what makes a
/// remembered headset survive being moved to a different USB port, which
/// changes its id but not its name — without it the user would silently be
/// thrown back onto whatever device happens to enumerate first.
AudioDeviceRef? resolveDevice(
  AudioDeviceRef? remembered,
  List<AudioDeviceRef> available,
) {
  if (remembered == null || available.isEmpty) return null;
  for (final device in available) {
    if (device.deviceId == remembered.deviceId) return device;
  }
  if (remembered.label.isEmpty) return null;
  for (final device in available) {
    if (device.label == remembered.label) return device;
  }
  return null;
}

/// Same matching, but returning the LiveKit device object.
///
/// `Hardware.selectAudioInput/Output` need the concrete `MediaDevice`, while
/// the UI works in terms of the persisted [AudioDeviceRef]; this bridges them
/// without duplicating the id-then-label matching rule.
lk.MediaDevice? matchDevice(
  AudioDeviceRef? remembered,
  List<lk.MediaDevice> available,
) {
  if (remembered == null || available.isEmpty) return null;
  for (final device in available) {
    if (device.deviceId == remembered.deviceId) return device;
  }
  if (remembered.label.isEmpty) return null;
  for (final device in available) {
    if (device.label == remembered.label) return device;
  }
  return null;
}
