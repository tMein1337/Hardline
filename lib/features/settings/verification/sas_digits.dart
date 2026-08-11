/// How many digits the Matrix decimal SAS carries in total.
///
/// Three numbers of four digits each. Fixed by the protocol, not a choice:
/// `KeyVerification.sasNumbers` splits five shared bytes into three 13-bit
/// values and adds 1000, so every value is in 1000–9191.
const kSasDigitCount = 12;

/// Digits per displayed group.
const kSasGroupSize = 3;

/// The lowest and highest value a decimal SAS number can take.
const kSasMin = 1000;
const kSasMax = 9191;

/// Regroups the decimal SAS into four groups of three digits.
///
/// Every digit is shown. That is not a stylistic decision — the comparison is
/// only as strong as the part of the code the user actually checks, and the
/// protocol puts ~39 bits into these twelve digits. Dropping half of them would
/// halve the security of the check while looking identical.
///
/// The *grouping* is ours; the digit stream is not. Element renders the same
/// twelve digits as three groups of four, so the two read the same left to
/// right and can be compared straight across. The verification dialog says so,
/// because otherwise a different-looking layout reads as a mismatch.
List<String> sasDigitGroups(List<int> sasNumbers) {
  assert(
    sasNumbers.length == 3 &&
        sasNumbers.every((n) => n >= kSasMin && n <= kSasMax),
    'Expected three decimal SAS numbers in $kSasMin–$kSasMax, got $sasNumbers. '
    'Anything else means the SDK changed shape, and regrouping it blindly '
    'would show a short or malformed code that still looks checkable.',
  );

  final digits = sasNumbers.join();
  if (digits.length != kSasDigitCount) return const [];

  return [
    for (var i = 0; i < digits.length; i += kSasGroupSize)
      digits.substring(i, i + kSasGroupSize),
  ];
}
