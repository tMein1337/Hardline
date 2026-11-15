// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Plays a known signal into a particular audio output, by name.
///
/// What makes a call test about *what the other side hears* possible on one
/// machine. VB-Audio's virtual cable is an output ("CABLE Input") whose
/// every sample comes back out of an input ("CABLE Output"). Point the app's
/// microphone at the second and play into the first, and the app is talking
/// with a voice the test wrote, sample by sample.
///
/// Over `winmm`'s `waveOut*` calls by hand: the device has to be chosen by
/// name — the system default is somebody's headphones — and nothing in the
/// dependency tree plays audio to a named device.
library;

import 'dart:ffi';
import 'dart:math' as math;
import 'dart:typed_data';

final _winmm = DynamicLibrary.open('winmm.dll');
final _kernel32 = DynamicLibrary.open('kernel32.dll');

final _localAlloc = _kernel32
    .lookupFunction<IntPtr Function(Uint32, IntPtr), int Function(int, int)>(
      'LocalAlloc',
    );
final _localFree = _kernel32
    .lookupFunction<IntPtr Function(IntPtr), int Function(int)>('LocalFree');

final _waveOutGetNumDevs = _winmm
    .lookupFunction<Uint32 Function(), int Function()>('waveOutGetNumDevs');

final _waveOutGetDevCaps = _winmm
    .lookupFunction<
      Uint32 Function(IntPtr, Pointer<Uint8>, Uint32),
      int Function(int, Pointer<Uint8>, int)
    >('waveOutGetDevCapsW');

final _waveOutOpen = _winmm
    .lookupFunction<
      Uint32 Function(
        Pointer<IntPtr>,
        Uint32,
        Pointer<Uint8>,
        IntPtr,
        IntPtr,
        Uint32,
      ),
      int Function(Pointer<IntPtr>, int, Pointer<Uint8>, int, int, int)
    >('waveOutOpen');

final _waveOutPrepareHeader = _winmm
    .lookupFunction<
      Uint32 Function(IntPtr, Pointer<Uint8>, Uint32),
      int Function(int, Pointer<Uint8>, int)
    >('waveOutPrepareHeader');

final _waveOutUnprepareHeader = _winmm
    .lookupFunction<
      Uint32 Function(IntPtr, Pointer<Uint8>, Uint32),
      int Function(int, Pointer<Uint8>, int)
    >('waveOutUnprepareHeader');

final _waveOutWrite = _winmm
    .lookupFunction<
      Uint32 Function(IntPtr, Pointer<Uint8>, Uint32),
      int Function(int, Pointer<Uint8>, int)
    >('waveOutWrite');

final _waveOutReset = _winmm
    .lookupFunction<Uint32 Function(IntPtr), int Function(int)>('waveOutReset');

final _waveOutClose = _winmm
    .lookupFunction<Uint32 Function(IntPtr), int Function(int)>('waveOutClose');

const sampleRate = 48000;

/// `WAVEHDR` on 64-bit Windows.
const _headerSize = 48;
const _whdrDone = 0x1;

/// The names of every output `waveOut` can open, in its own numbering.
///
/// A name is cut at 31 characters by the API itself, which is why
/// [AudioOut.open] matches on a prefix.
List<String> outputDevices() {
  final count = _waveOutGetNumDevs();
  final memory = Pointer<Uint8>.fromAddress(_localAlloc(0x40, 84));
  try {
    return [
      for (var id = 0; id < count; id++)
        if (_waveOutGetDevCaps(id, memory, 84) == 0)
          String.fromCharCodes(
            (memory + 8)
                .cast<Uint16>()
                .asTypedList(32)
                .takeWhile((c) => c != 0),
          ),
    ];
  } finally {
    _localFree(memory.address);
  }
}

/// One open output, playing 48 kHz mono 16-bit.
class AudioOut {
  AudioOut._(this._handle);

  /// Opens the first output whose name starts with [namePrefix], or returns
  /// null when there is none.
  static AudioOut? open(String namePrefix) {
    final names = outputDevices();
    final id = names.indexWhere((name) => name.startsWith(namePrefix));
    if (id < 0) return null;

    // WAVEFORMATEX: PCM, 1 channel, 48000 Hz, 96000 B/s, align 2, 16 bit.
    final format = Pointer<Uint8>.fromAddress(_localAlloc(0x40, 18));
    final handle = Pointer<IntPtr>.fromAddress(_localAlloc(0x40, 8));
    try {
      final fields = format.cast<Uint16>();
      fields[0] = 1;
      fields[1] = 1;
      (format + 4).cast<Uint32>().value = sampleRate;
      (format + 8).cast<Uint32>().value = sampleRate * 2;
      fields[6] = 2;
      fields[7] = 16;
      if (_waveOutOpen(handle, id, format, 0, 0, 0) != 0) return null;
      return AudioOut._(handle.value);
    } finally {
      _localFree(format.address);
      _localFree(handle.address);
    }
  }

  final int _handle;
  bool _closed = false;

  /// Plays [samples] and completes when the device has finished with them.
  Future<void> play(Int16List samples) async {
    if (_closed) throw StateError('closed');
    final bytes = samples.lengthInBytes;
    final data = _localAlloc(0x40, bytes);
    final header = Pointer<Uint8>.fromAddress(_localAlloc(0x40, _headerSize));
    try {
      Pointer<Int16>.fromAddress(
        data,
      ).asTypedList(samples.length).setAll(0, samples);
      header.cast<IntPtr>().value = data; // lpData
      (header + 8).cast<Uint32>().value = bytes; // dwBufferLength
      _waveOutPrepareHeader(_handle, header, _headerSize);
      _waveOutWrite(_handle, header, _headerSize);
      final flags = (header + 24).cast<Uint32>();
      while (flags.value & _whdrDone == 0 && !_closed) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      _waveOutUnprepareHeader(_handle, header, _headerSize);
    } finally {
      _localFree(header.address);
      _localFree(data);
    }
  }

  /// Stops whatever is playing and releases the device.
  void close() {
    if (_closed) return;
    _closed = true;
    _waveOutReset(_handle);
    _waveOutClose(_handle);
  }
}

/// Builds signals out of pieces, in order.
///
/// Everything is speech-*like* rather than a pure tone, on purpose. The
/// capture path runs WebRTC's noise suppression, which is built to remove
/// exactly the kind of steady sound a sine wave is, and would slowly take a
/// test tone away. A few harmonics on a wavering pitch with a syllable-rate
/// envelope is treated as a voice.
class Signal {
  final _samples = <int>[];
  final _random = math.Random(1337);
  double _phase = 0;

  Duration get length =>
      Duration(microseconds: _samples.length * 1000000 ~/ sampleRate);

  /// Nothing at all.
  Signal silence(Duration duration) {
    _samples.addAll(List.filled(_count(duration), 0));
    return this;
  }

  /// Voice-like sound at [dbfs] below full scale.
  Signal voice(Duration duration, {double dbfs = -12}) {
    final peak = 32767 * math.pow(10, dbfs / 20);
    final count = _count(duration);
    for (var i = 0; i < count; i++) {
      final t = i / sampleRate;
      // A pitch that wanders between 120 and 180 Hz, and a 4 Hz envelope that
      // never quite closes — syllables, not separate beeps.
      final pitch = 150 + 30 * math.sin(2 * math.pi * 0.7 * t);
      _phase += 2 * math.pi * pitch / sampleRate;
      final envelope = 0.55 + 0.45 * math.sin(2 * math.pi * 4 * t);
      var sample = 0.0;
      for (var h = 1; h <= 6; h++) {
        sample += math.sin(_phase * h) / h;
      }
      // A ten millisecond fade at each end, so a burst does not start with a
      // click a gate could take for a transient.
      final edge = math.min(i, count - i) / (sampleRate * 0.01);
      _samples.add(
        (peak * envelope * sample / 2.45 * math.min(1.0, edge)).round(),
      );
    }
    return this;
  }

  /// Broadband hiss at [dbfs], the fan in the corner.
  Signal hiss(Duration duration, {double dbfs = -50}) {
    final peak = 32767 * math.pow(10, dbfs / 20);
    final count = _count(duration);
    for (var i = 0; i < count; i++) {
      _samples.add((peak * (_random.nextDouble() * 2 - 1)).round());
    }
    return this;
  }

  Int16List build() => Int16List.fromList(_samples);

  int _count(Duration duration) =>
      duration.inMicroseconds * sampleRate ~/ 1000000;
}
