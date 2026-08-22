// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/injected_providers.dart';
import '../../../core/util/time_format.dart';
import '../../../theme/theme_context.dart';
import '../../accounts/active_client.dart';
import '../encryption/encryption_setup_dialog.dart';
import '../encryption/encryption_status.dart';
import '../sessions_provider.dart';
import '../verification/sas_display.dart';
import '../verification/verification_dialog.dart';
import '../verification/verification_session.dart';
import '../widgets/settings_layout.dart';
import '../widgets/text_prompt.dart';
import '../widgets/uia_password_prompt.dart';

/// Every session signed in to this account, and what can be done about them.
class SessionsPane extends ConsumerWidget {
  const SessionsPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionsProvider);
    final encryptionAvailable = ref.watch(encryptionAvailableProvider);

    return SettingsPane(
      title: 'Sessions',
      description:
          'Every device signed in to this account. Verify the ones you '
          'recognise and sign out the ones you do not.',
      children: [
        if (!encryptionAvailable)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _Banner(
              icon: Icons.lock_open,
              color: context.colors.warning,
              message:
                  'Encryption is unavailable in this build, so sessions cannot '
                  'be verified here.',
            ),
          )
        else ...[
          const _EncryptionCard(),
          const SizedBox(height: 32),
          const _SasDisplayCard(),
          const SizedBox(height: 32),
          const SettingsLabel('Sessions'),
        ],
        sessions.when(
          // Keep the list on screen while `/devices` is re-fetched; only a
          // first load has nothing to show.
          skipLoadingOnReload: true,
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => _Banner(
            icon: Icons.error_outline,
            color: context.colors.danger,
            message: 'Could not read the session list.\n$error',
          ),
          data: (items) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final session in items) ...[
                _SessionCard(session: session),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => ref.invalidate(deviceListProvider),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Refresh'),
          ),
        ),
      ],
    );
  }
}

/// The state that actually decides what other clients show against our
/// messages.
///
/// This card exists because the answer is deeply unobvious: a session can be
/// verified everywhere in *our* UI and still be flagged in Element, because
/// Element reads cross-signing signatures published to the homeserver and local
/// verification publishes none. Rather than explain that in a changelog, the
/// app says so where the question is asked.
class _EncryptionCard extends ConsumerWidget {
  const _EncryptionCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final status = ref.watch(encryptionStatusProvider);

    return status.when(
      // The status is recomputed on every sync tick, and a tick arrives every
      // few hundred milliseconds. Without this the card would spend most of its
      // life as a spinner, hiding the one control that explains why Element is
      // flagging your messages.
      skipLoadingOnReload: true,
      loading: () => const SettingsCard(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(8),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ),
      error: (error, _) => _Banner(
        icon: Icons.error_outline,
        color: colors.danger,
        message: 'Could not read the encryption state.\n$error',
      ),
      data: (data) {
        if (data.isComplete) {
          return SettingsCard(
            child: SettingsRow(
              leading: Icon(Icons.verified_user, color: colors.success),
              title: 'This session is verified',
              subtitle: data.keyBackupEnabled
                  ? 'Signed by your account and backing up message keys.'
                  : 'Signed by your account. Message key backup is off.',
            ),
          );
        }

        final needsSetup = data.needsSetup;
        // Signed but without the private keys cached. Other clients are already
        // happy — saying they flag us here would simply be untrue — but we hold
        // nothing to sign anyone else with.
        final signedButKeyless = data.ownDeviceSigned && !data.secretsCached;

        return SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsRow(
                leading: Icon(
                  Icons.gpp_maybe,
                  color: signedButKeyless ? colors.textMuted : colors.warning,
                ),
                title: switch ((needsSetup, signedButKeyless)) {
                  (true, _) => 'Encryption is not set up on this account',
                  (_, true) => 'This session cannot verify others',
                  _ => 'This session is not verified by your account',
                },
                subtitle: switch ((needsSetup, signedButKeyless)) {
                  (true, _) =>
                    'Nothing has signed your sessions, so other clients show '
                        'your messages as coming from an unverified device.',
                  (_, true) =>
                    'Other clients trust this session, but it does not hold '
                        'your account keys, so it cannot verify your other '
                        'sessions.',
                  _ =>
                    'Other clients show your messages as coming from an '
                        'unverified device until this session is signed.',
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (needsSetup)
                    FilledButton(
                      onPressed: () => EncryptionSetupDialog.show(context),
                      child: const Text('Set up encryption'),
                    )
                  else
                    FilledButton(
                      onPressed: () => unlockWithRecoveryKey(context, ref),
                      child: const Text('Use recovery key'),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      needsSetup
                          ? 'Creates a signing identity and a recovery key.'
                          : 'Or verify from another signed-in session below.',
                      style: context.text.timestamp,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Which of the two equivalent codes the verification dialog leads with.
class _SasDisplayCard extends ConsumerWidget {
  const _SasDisplayCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(sasDisplayProvider);

    return SettingsCard(
      child: SettingsRow(
        title: 'Verification code',
        subtitle: selected.description,
        trailing: SettingsChoice<SasDisplay>(
          values: SasDisplay.values,
          selected: selected,
          labelOf: (value) => value.label,
          onChanged: ref.read(sasDisplayProvider.notifier).set,
        ),
      ),
    );
  }
}

class _SessionCard extends ConsumerWidget {
  const _SessionCard({required this.session});

  final SessionInfo session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final verified = session.verified;

    return SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Tooltip(
                message: verified
                    ? 'This session has been verified'
                    : 'Nobody has confirmed this session belongs to you',
                child: Icon(
                  verified ? Icons.verified_user : Icons.gpp_maybe,
                  color: verified ? colors.success : colors.warning,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            session.label,
                            style: context.text.username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (session.isCurrent) ...[
                          const SizedBox(width: 8),
                          _Chip(label: 'This session'),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      verified
                          ? 'Verified · ${session.deviceId}'
                          : 'Not verified · ${session.deviceId}',
                      style: context.text.subtitle.copyWith(
                        color: verified ? colors.textMuted : colors.warning,
                      ),
                    ),
                    if (_lastSeen case final text?)
                      Text(text, style: context.text.timestamp),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (session.canVerify)
                FilledButton(
                  onPressed: () => _verify(context, ref),
                  child: Text(verified ? 'Verify again' : 'Verify'),
                ),
              if (session.canVerify) const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => _rename(context, ref),
                child: const Text('Rename'),
              ),
              const Spacer(),
              if (!session.isCurrent)
                TextButton(
                  onPressed: () => _signOut(context, ref),
                  child: Text(
                    'Sign out',
                    style: TextStyle(color: colors.danger),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String? get _lastSeen {
    final at = session.lastSeenAt;
    final ip = session.lastSeenIp;
    if (at == null && ip == null) return null;
    if (at == null) return 'Last seen from $ip';
    final when = formatMessageTimestamp(at);
    return ip == null ? 'Last seen $when' : 'Last seen $when from $ip';
  }

  Future<void> _verify(BuildContext context, WidgetRef ref) async {
    final client = ref.read(clientProvider);
    final keys = client.userDeviceKeys[client.userID]?.deviceKeys;
    final device = keys?[session.deviceId];
    if (device == null) return;

    final request = await device.startVerification();
    if (!context.mounted) return;
    await VerificationDialog.show(context, VerificationSession(request));
    // The badge is driven by the key store, which the sync tick already
    // refreshes — but the device list itself may now name a session differently.
    ref.invalidate(deviceListProvider);
    // A verification against a session that holds the cross-signing keys can
    // leave *this* one signed, which is what the encryption card reports.
    ref.invalidate(encryptionStatusProvider);
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final name = await promptForText(
      context,
      title: 'Rename session',
      description:
          'The name other people see next to this session in their client.',
      hint: 'e.g. Work laptop',
      initial: session.displayName ?? '',
    );
    if (name == null) return;

    await ref
        .read(clientProvider)
        .updateDevice(session.deviceId, displayName: name);
    ref.invalidate(deviceListProvider);
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final client = ref.read(clientProvider);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final done = await runWithPasswordAuth(
        context,
        client: client,
        purpose: 'Signing "${session.label}" out needs your password.',
        request: (auth) => client.deleteDevice(session.deviceId, auth: auth),
      );
      if (done) ref.invalidate(deviceListProvider);
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not sign that session out: $error')),
      );
    }
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.accent,
        borderRadius: BorderRadius.circular(context.metrics.rowRadius),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Text(
        label,
        style: context.text.timestamp.copyWith(color: colors.textOnAccent),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.color,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: context.text.subtitle.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
