import 'package:country_picker/country_picker.dart';
import 'package:darmaan/presentation/auth/repository/login/phone_auth_repository.dart';
import 'package:darmaan/presentation/auth/screens/login/otp_verification_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:darmaan/widgets/auth_customer_care_button.dart';

/// How a country's mobile numbers are typed locally, and how to turn that
/// into +E.164.
///
/// [minLength]/[maxLength]: national significant number length (digits
///   after the dial code, without any trunk prefix).
/// [trunkPrefix]: digits people type in front locally ("0" for Pakistan:
///   03XXXXXXXXX). Empty when the country doesn't use one.
/// [prefixOptional]: true if users may also skip the trunk prefix.
/// [addPrefix]: digits inserted after the dial code (Argentina mobile "9").
class _CountryRule {
  final int minLength;
  final int maxLength;
  final String trunkPrefix;
  final bool prefixOptional;
  final String addPrefix;

  /// Fixed-length rule.
  const _CountryRule({
    required int nsnLength,
    bool hasLeadingZero = false,
    String trunk = '',
    this.prefixOptional = false,
    this.addPrefix = '',
  })  : minLength = nsnLength,
        maxLength = nsnLength,
        trunkPrefix = hasLeadingZero ? '0' : trunk;

  /// Variable-length rule (some countries have several mobile lengths).
  const _CountryRule.range({
    required this.minLength,
    required this.maxLength,
    bool hasLeadingZero = false,
    String trunk = '',
    this.prefixOptional = false,
    this.addPrefix = '',
  }) : trunkPrefix = hasLeadingZero ? '0' : trunk;
}

/// Rules for every country. The first 13 are the original hand-written
/// rules . The rest are generated from Google's
/// libphonenumber metadata, following how people in each country actually
/// write their mobile number (with or without the trunk "0").
///
/// A country missing from this map falls back to a generic E.164 check.
const Map<String, _CountryRule> _kCountryRules = {
  // ---- Original countries (unchanged) --------------------------------
  'PK': _CountryRule(nsnLength: 10, hasLeadingZero: true), // 03XXXXXXXXX
  'AE': _CountryRule(nsnLength: 9, hasLeadingZero: true), // 05XXXXXXXX
  'SA': _CountryRule(nsnLength: 9, hasLeadingZero: true), // 05XXXXXXXX
  'OM': _CountryRule(nsnLength: 8, hasLeadingZero: false),
  'BH': _CountryRule(nsnLength: 8, hasLeadingZero: false),
  'QA': _CountryRule(nsnLength: 8, hasLeadingZero: false),
  'IR': _CountryRule(nsnLength: 10, hasLeadingZero: true), // 09XXXXXXXXX
  'AF': _CountryRule(nsnLength: 9, hasLeadingZero: true), // 07XXXXXXXX
  'US': _CountryRule(nsnLength: 10, hasLeadingZero: false),
  'CA': _CountryRule(nsnLength: 10, hasLeadingZero: false),
  'DE': _CountryRule(nsnLength: 11, hasLeadingZero: true),
  'NL': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'IT': _CountryRule(nsnLength: 10, hasLeadingZero: false),

  // ---- All other countries (generated) -------------------------------
  'AC': _CountryRule(nsnLength: 5),
  'AD': _CountryRule.range(minLength: 6, maxLength: 9),
  'AG': _CountryRule(nsnLength: 10),
  'AI': _CountryRule(nsnLength: 10),
  'AL': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'AM': _CountryRule(nsnLength: 8, hasLeadingZero: true),
  'AO': _CountryRule(nsnLength: 9),
  'AR': _CountryRule(nsnLength: 10, addPrefix: '9'),
  'AS': _CountryRule(nsnLength: 10),
  'AT': _CountryRule.range(minLength: 7, maxLength: 13, hasLeadingZero: true),
  'AU': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'AW': _CountryRule(nsnLength: 7),
  'AX': _CountryRule.range(minLength: 6, maxLength: 10, hasLeadingZero: true),
  'AZ': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'BA': _CountryRule.range(minLength: 8, maxLength: 9, hasLeadingZero: true),
  'BB': _CountryRule(nsnLength: 10),
  'BD': _CountryRule(nsnLength: 10, hasLeadingZero: true),
  'BE': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'BF': _CountryRule(nsnLength: 8),
  'BG': _CountryRule.range(minLength: 8, maxLength: 9, hasLeadingZero: true),
  'BI': _CountryRule(nsnLength: 8),
  'BJ': _CountryRule(nsnLength: 10),
  'BL': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'BM': _CountryRule(nsnLength: 10),
  'BN': _CountryRule(nsnLength: 7),
  'BO': _CountryRule(nsnLength: 8),
  'BQ': _CountryRule(nsnLength: 7),
  'BR': _CountryRule.range(minLength: 10, maxLength: 11),
  'BS': _CountryRule(nsnLength: 10),
  'BT': _CountryRule(nsnLength: 8),
  'BW': _CountryRule(nsnLength: 8),
  'BY': _CountryRule(nsnLength: 9, trunk: '80', prefixOptional: true),
  'BZ': _CountryRule(nsnLength: 7),
  'CC': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'CD': _CountryRule.range(minLength: 7, maxLength: 9, hasLeadingZero: true),
  'CF': _CountryRule(nsnLength: 8),
  'CG': _CountryRule(nsnLength: 9),
  'CH': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'CI': _CountryRule(nsnLength: 10),
  'CK': _CountryRule(nsnLength: 5),
  'CL': _CountryRule(nsnLength: 9),
  'CM': _CountryRule(nsnLength: 9),
  'CN': _CountryRule(nsnLength: 11),
  'CO': _CountryRule(nsnLength: 10),
  'CR': _CountryRule(nsnLength: 8),
  'CU': _CountryRule(nsnLength: 8, hasLeadingZero: true),
  'CV': _CountryRule(nsnLength: 7),
  'CW': _CountryRule.range(minLength: 7, maxLength: 8),
  'CX': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'CY': _CountryRule(nsnLength: 8),
  'CZ': _CountryRule(nsnLength: 9),
  'DJ': _CountryRule(nsnLength: 8),
  'DK': _CountryRule(nsnLength: 8),
  'DM': _CountryRule(nsnLength: 10),
  'DO': _CountryRule(nsnLength: 10),
  'DZ': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'EC': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'EE': _CountryRule.range(minLength: 7, maxLength: 8),
  'EG': _CountryRule(nsnLength: 10, hasLeadingZero: true),
  'EH': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'ER': _CountryRule(nsnLength: 7, hasLeadingZero: true),
  'ES': _CountryRule(nsnLength: 9),
  'ET': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'FI': _CountryRule.range(minLength: 6, maxLength: 10, hasLeadingZero: true),
  'FJ': _CountryRule(nsnLength: 7),
  'FK': _CountryRule(nsnLength: 5),
  'FM': _CountryRule(nsnLength: 7),
  'FO': _CountryRule(nsnLength: 6),
  'FR': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'GA': _CountryRule.range(minLength: 7, maxLength: 8),
  'GB': _CountryRule(nsnLength: 10, hasLeadingZero: true),
  'GD': _CountryRule(nsnLength: 10),
  'GE': _CountryRule(nsnLength: 9),
  'GF': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'GG': _CountryRule(nsnLength: 10, hasLeadingZero: true),
  'GH': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'GI': _CountryRule(nsnLength: 8),
  'GL': _CountryRule(nsnLength: 6),
  'GM': _CountryRule.range(minLength: 7, maxLength: 9),
  'GN': _CountryRule(nsnLength: 9),
  'GP': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'GQ': _CountryRule(nsnLength: 9),
  'GR': _CountryRule(nsnLength: 10),
  'GT': _CountryRule(nsnLength: 8),
  'GU': _CountryRule(nsnLength: 10),
  'GW': _CountryRule(nsnLength: 9),
  'GY': _CountryRule(nsnLength: 7),
  'HK': _CountryRule(nsnLength: 8),
  'HN': _CountryRule(nsnLength: 8),
  'HR': _CountryRule.range(minLength: 8, maxLength: 9, hasLeadingZero: true),
  'HT': _CountryRule(nsnLength: 8),
  'HU': _CountryRule(nsnLength: 9, trunk: '06', prefixOptional: true),
  'ID': _CountryRule.range(minLength: 9, maxLength: 12, hasLeadingZero: true),
  'IE': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'IL': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'IM': _CountryRule(nsnLength: 10, hasLeadingZero: true),
  'IN': _CountryRule(nsnLength: 10, hasLeadingZero: true),
  'IO': _CountryRule(nsnLength: 7),
  'IQ': _CountryRule(nsnLength: 10, hasLeadingZero: true),
  'IS': _CountryRule.range(minLength: 7, maxLength: 9),
  'JE': _CountryRule(nsnLength: 10, hasLeadingZero: true),
  'JM': _CountryRule(nsnLength: 10),
  'JO': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'JP': _CountryRule(nsnLength: 10, hasLeadingZero: true),
  'KE': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'KG': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'KH': _CountryRule.range(minLength: 8, maxLength: 9, hasLeadingZero: true),
  'KI': _CountryRule(nsnLength: 8),
  'KM': _CountryRule(nsnLength: 7),
  'KN': _CountryRule(nsnLength: 10),
  'KP': _CountryRule(nsnLength: 10, hasLeadingZero: true),
  'KR': _CountryRule.range(minLength: 9, maxLength: 10, hasLeadingZero: true),
  'KW': _CountryRule(nsnLength: 8),
  'KY': _CountryRule(nsnLength: 10),
  'KZ': _CountryRule(nsnLength: 10, trunk: '8', prefixOptional: true),
  'LA': _CountryRule.range(minLength: 9, maxLength: 10, hasLeadingZero: true),
  'LB': _CountryRule.range(minLength: 7, maxLength: 8),
  'LC': _CountryRule(nsnLength: 10),
  'LI': _CountryRule.range(minLength: 7, maxLength: 9),
  'LK': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'LR': _CountryRule.range(minLength: 7, maxLength: 9, hasLeadingZero: true),
  'LS': _CountryRule(nsnLength: 8),
  'LT': _CountryRule(nsnLength: 8, hasLeadingZero: true),
  'LU': _CountryRule(nsnLength: 9),
  'LV': _CountryRule(nsnLength: 8),
  'LY': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'MA': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'MC': _CountryRule.range(minLength: 8, maxLength: 9, hasLeadingZero: true),
  'MD': _CountryRule(nsnLength: 8, hasLeadingZero: true),
  'ME': _CountryRule(nsnLength: 8, hasLeadingZero: true),
  'MF': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'MG': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'MH': _CountryRule(nsnLength: 7),
  'MK': _CountryRule(nsnLength: 8, hasLeadingZero: true),
  'ML': _CountryRule(nsnLength: 8),
  'MM': _CountryRule.range(minLength: 7, maxLength: 10, hasLeadingZero: true),
  'MN': _CountryRule(nsnLength: 8),
  'MO': _CountryRule(nsnLength: 8),
  'MP': _CountryRule(nsnLength: 10),
  'MQ': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'MR': _CountryRule(nsnLength: 8),
  'MS': _CountryRule(nsnLength: 10),
  'MT': _CountryRule(nsnLength: 8),
  'MU': _CountryRule(nsnLength: 8),
  'MV': _CountryRule(nsnLength: 7),
  'MW': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'MX': _CountryRule(nsnLength: 10),
  'MY': _CountryRule.range(minLength: 9, maxLength: 10, hasLeadingZero: true),
  'MZ': _CountryRule(nsnLength: 9),
  'NA': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'NC': _CountryRule(nsnLength: 6),
  'NE': _CountryRule(nsnLength: 8),
  'NF': _CountryRule(nsnLength: 6),
  'NG': _CountryRule(nsnLength: 10, hasLeadingZero: true),
  'NI': _CountryRule(nsnLength: 8),
  'NO': _CountryRule(nsnLength: 8),
  'NP': _CountryRule(nsnLength: 10),
  'NR': _CountryRule(nsnLength: 7),
  'NU': _CountryRule.range(minLength: 4, maxLength: 7),
  'NZ': _CountryRule.range(minLength: 8, maxLength: 10, hasLeadingZero: true),
  'PA': _CountryRule.range(minLength: 7, maxLength: 8),
  'PE': _CountryRule(nsnLength: 9),
  'PF': _CountryRule(nsnLength: 8),
  'PG': _CountryRule(nsnLength: 8),
  'PH': _CountryRule(nsnLength: 10, hasLeadingZero: true),
  'PL': _CountryRule(nsnLength: 9),
  'PM': _CountryRule.range(minLength: 6, maxLength: 9, hasLeadingZero: true),
  'PR': _CountryRule(nsnLength: 10),
  'PS': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'PT': _CountryRule(nsnLength: 9),
  'PW': _CountryRule(nsnLength: 7),
  'PY': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'RE': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'RO': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'RS': _CountryRule.range(minLength: 8, maxLength: 10, hasLeadingZero: true),
  'RU': _CountryRule(nsnLength: 10, trunk: '8', prefixOptional: true),
  'RW': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'SB': _CountryRule.range(minLength: 5, maxLength: 7),
  'SC': _CountryRule(nsnLength: 7),
  'SD': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'SE': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'SG': _CountryRule(nsnLength: 8),
  'SH': _CountryRule(nsnLength: 5),
  'SI': _CountryRule(nsnLength: 8, hasLeadingZero: true),
  'SJ': _CountryRule(nsnLength: 8),
  'SK': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'SL': _CountryRule(nsnLength: 8, hasLeadingZero: true),
  'SM': _CountryRule(nsnLength: 8),
  'SN': _CountryRule(nsnLength: 9),
  'SO': _CountryRule.range(minLength: 7, maxLength: 9),
  'SR': _CountryRule(nsnLength: 7),
  'SS': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'ST': _CountryRule(nsnLength: 7),
  'SV': _CountryRule(nsnLength: 8),
  'SX': _CountryRule(nsnLength: 10),
  'SY': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'SZ': _CountryRule(nsnLength: 8),
  'TA': _CountryRule(nsnLength: 4),
  'TC': _CountryRule(nsnLength: 10),
  'TD': _CountryRule(nsnLength: 8),
  'TG': _CountryRule(nsnLength: 8),
  'TH': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'TJ': _CountryRule(nsnLength: 9),
  'TK': _CountryRule.range(minLength: 4, maxLength: 7),
  'TL': _CountryRule(nsnLength: 8),
  'TM': _CountryRule(nsnLength: 8, trunk: '8', prefixOptional: true),
  'TN': _CountryRule(nsnLength: 8),
  'TO': _CountryRule(nsnLength: 7),
  'TR': _CountryRule(nsnLength: 10, hasLeadingZero: true),
  'TT': _CountryRule(nsnLength: 10),
  'TV': _CountryRule.range(minLength: 6, maxLength: 7),
  'TW': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'TZ': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'UA': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'UG': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'UY': _CountryRule(nsnLength: 8, hasLeadingZero: true),
  'UZ': _CountryRule(nsnLength: 9),
  'VA': _CountryRule.range(minLength: 9, maxLength: 10),
  'VC': _CountryRule(nsnLength: 10),
  'VE': _CountryRule(nsnLength: 10, hasLeadingZero: true),
  'VG': _CountryRule(nsnLength: 10),
  'VI': _CountryRule(nsnLength: 10),
  'VN': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'VU': _CountryRule(nsnLength: 7),
  'WF': _CountryRule(nsnLength: 6),
  'WS': _CountryRule.range(minLength: 7, maxLength: 10),
  'XK': _CountryRule(nsnLength: 8, hasLeadingZero: true),
  'YE': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'YT': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'ZA': _CountryRule.range(minLength: 5, maxLength: 9, hasLeadingZero: true),
  'ZM': _CountryRule(nsnLength: 9, hasLeadingZero: true),
  'ZW': _CountryRule(nsnLength: 9, hasLeadingZero: true),
};

/// Example mobile number in LOCAL format (as a user would type it), used as
/// the input hint. Generated from libphonenumber.
const Map<String, String> _kLocalExamples = {
  'AC': '40123',
  'AD': '312345',
  'AE': '0501234567',
  'AF': '0701234567',
  'AG': '2684641234',
  'AI': '2642351234',
  'AL': '0672123456',
  'AM': '077123456',
  'AO': '923123456',
  'AR': '1123456789',
  'AS': '6847331234',
  'AT': '0664123456',
  'AU': '0412345678',
  'AW': '5601234',
  'AX': '0412345678',
  'AZ': '0401234567',
  'BA': '061123456',
  'BB': '2462501234',
  'BD': '01812345678',
  'BE': '0450001234',
  'BF': '70123456',
  'BG': '043012345',
  'BH': '36001234',
  'BI': '79561234',
  'BJ': '0195123456',
  'BL': '0690001234',
  'BM': '4413701234',
  'BN': '7123456',
  'BO': '71234567',
  'BQ': '3181234',
  'BR': '11961234567',
  'BS': '2423591234',
  'BT': '17123456',
  'BW': '71123456',
  'BY': '80294911911',
  'BZ': '6221234',
  'CA': '5062345678',
  'CC': '0412345678',
  'CD': '0991234567',
  'CF': '70012345',
  'CG': '061234567',
  'CH': '0781234567',
  'CI': '0123456789',
  'CK': '71234',
  'CL': '221234567',
  'CM': '671234567',
  'CN': '13123456789',
  'CO': '3211234567',
  'CR': '83123456',
  'CU': '051234567',
  'CV': '9911234',
  'CW': '95181234',
  'CX': '0412345678',
  'CY': '96123456',
  'CZ': '601123456',
  'DE': '015123456789',
  'DJ': '77831001',
  'DK': '34412345',
  'DM': '7672251234',
  'DO': '8092345678',
  'DZ': '0551234567',
  'EC': '0991234567',
  'EE': '51234567',
  'EG': '01001234567',
  'EH': '0650123456',
  'ER': '07123456',
  'ES': '612345678',
  'ET': '0911234567',
  'FI': '0412345678',
  'FJ': '7012345',
  'FK': '51234',
  'FM': '3501234',
  'FO': '211234',
  'FR': '0612345678',
  'GA': '06031234',
  'GB': '07400123456',
  'GD': '4734031234',
  'GE': '555123456',
  'GF': '0694201234',
  'GG': '07781123456',
  'GH': '0231234567',
  'GI': '57123456',
  'GL': '221234',
  'GM': '3012345',
  'GN': '601123456',
  'GP': '0690001234',
  'GQ': '222123456',
  'GR': '6912345678',
  'GT': '51234567',
  'GU': '6713001234',
  'GW': '955012345',
  'GY': '6091234',
  'HK': '51234567',
  'HN': '91234567',
  'HR': '0921234567',
  'HT': '34101234',
  'HU': '06201234567',
  'ID': '0812345678',
  'IE': '0850123456',
  'IL': '0502345678',
  'IM': '07924123456',
  'IN': '08123456789',
  'IO': '3801234',
  'IQ': '07912345678',
  'IR': '09123456789',
  'IS': '6111234',
  'IT': '3123456789',
  'JE': '07797712345',
  'JM': '8762101234',
  'JO': '0790123456',
  'JP': '09012345678',
  'KE': '0712123456',
  'KG': '0700123456',
  'KH': '091234567',
  'KI': '72001234',
  'KM': '3212345',
  'KN': '8697652917',
  'KP': '01921234567',
  'KR': '01020000000',
  'KW': '50012345',
  'KY': '3453231234',
  'KZ': '87710009998',
  'LA': '02023123456',
  'LB': '71123456',
  'LC': '7582845678',
  'LI': '660234567',
  'LK': '0712345678',
  'LR': '0770123456',
  'LS': '50123456',
  'LT': '061234567',
  'LU': '628123456',
  'LV': '21234567',
  'LY': '0912345678',
  'MA': '0650123456',
  'MC': '0612345678',
  'MD': '062112345',
  'ME': '060123456',
  'MF': '0690001234',
  'MG': '0321234567',
  'MH': '2351234',
  'MK': '072345678',
  'ML': '65012345',
  'MM': '092123456',
  'MN': '88123456',
  'MO': '66123456',
  'MP': '6702345678',
  'MQ': '0696201234',
  'MR': '22123456',
  'MS': '6644923456',
  'MT': '96961234',
  'MU': '52512345',
  'MV': '7712345',
  'MW': '0991234567',
  'MX': '2221234567',
  'MY': '0123456789',
  'MZ': '821234567',
  'NA': '0811234567',
  'NC': '751234',
  'NE': '93123456',
  'NF': '381234',
  'NG': '08021234567',
  'NI': '81234567',
  'NL': '0612345678',
  'NO': '40612345',
  'NP': '9841234567',
  'NR': '5551234',
  'NU': '8884012',
  'NZ': '0211234567',
  'OM': '92123456',
  'PA': '61234567',
  'PE': '912345678',
  'PF': '87123456',
  'PG': '70123456',
  'PH': '09051234567',
  'PK': '03012345678',
  'PL': '512345678',
  'PM': '0551234',
  'PR': '7872345678',
  'PS': '0599123456',
  'PT': '912345678',
  'PW': '6201234',
  'PY': '0961456789',
  'QA': '33123456',
  'RE': '0692123456',
  'RO': '0712034567',
  'RS': '0601234567',
  'RU': '89123456789',
  'RW': '0720123456',
  'SA': '0512345678',
  'SB': '7421234',
  'SC': '2510123',
  'SD': '0911231234',
  'SE': '0701234567',
  'SG': '81234567',
  'SH': '51234',
  'SI': '031234567',
  'SJ': '41234567',
  'SK': '0912123456',
  'SL': '025123456',
  'SM': '66661212',
  'SN': '701234567',
  'SO': '71123456',
  'SR': '7412345',
  'SS': '0977123456',
  'ST': '9812345',
  'SV': '70123456',
  'SX': '7215205678',
  'SY': '0944567890',
  'SZ': '76123456',
  'TC': '6492311234',
  'TD': '63012345',
  'TG': '90112345',
  'TH': '0812345678',
  'TJ': '917123456',
  'TK': '7290',
  'TL': '77212345',
  'TM': '866123456',
  'TN': '20123456',
  'TO': '7715123',
  'TR': '05012345678',
  'TT': '8682911234',
  'TV': '901234',
  'TW': '0912345678',
  'TZ': '0621234567',
  'UA': '0501234567',
  'UG': '0712345678',
  'US': '2015550123',
  'UY': '094231234',
  'UZ': '912345678',
  'VA': '3123456789',
  'VC': '7844301234',
  'VE': '04121234567',
  'VG': '2843001234',
  'VI': '3406421234',
  'VN': '0912345678',
  'VU': '5912345',
  'WF': '821234',
  'WS': '7212345',
  'XK': '043201234',
  'YE': '0712345678',
  'YT': '0639012345',
  'ZA': '0711234567',
  'ZM': '0955123456',
  'ZW': '0712345678',
};

/// Shown at the top of the picker. Every other country is still
/// available in the alphabetical list below and via search.
const List<String> _kFavoriteCountries = [
  'PK',
  'AE',
  'SA',
  'BH',
  'QA',
  'OM',
  'IR',
  'AF',
  'US',
  'CA',
  'DE',
  'NL',
  'IT',
];

/// E.164 allows at most 15 digits total (country code + national number).
const int _kMaxE164Digits = 15;

/// Shortest national number accepted for countries missing from the table.
const int _kMinGenericNationalDigits = 6;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final PhoneAuthRepository _phoneAuthRepository = PhoneAuthRepository();

  final TextEditingController _phoneController = TextEditingController();
  final FocusNode _phoneFocusNode = FocusNode();

  bool isLoading = false;
  bool _isPhoneValid = false;
  String? _errorText;

  // Default to Pakistan.
  Country _selectedCountry = Country.parse('PK');

  late final AnimationController _entranceController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  // ---- Palette (blue) --------------------------------------------------
  static const Color _primaryColor = Color(0xFF2F80ED);
  static const Color _primaryDark = Color(0xFF1560C9);
  static const Color _backgroundColor = Color(0xFFFFFFFF);
  static const Color _surfaceColor = Colors.white;
  static const Color _pillColor = Color(0xFFF0F4FA);
  static const Color _textColor = Color(0xFF13161A);
  static const Color _errorColor = Color(0xFFDC3545);
  static const Color _hintTextColor = Color(0xFF9AA9B5);
  static const Color _subTextColor = Color(0xFF667180);

  /// Rule for the selected country, or null if it isn't in the table.
  _CountryRule? get _rule => _kCountryRules[_selectedCountry.countryCode];

  /// Max digits the user can type in the field (number + local trunk prefix).
  int get _maxInputLength {
    final rule = _rule;
    if (rule != null) {
      return rule.maxLength + rule.trunkPrefix.length;
    }
    // Unknown country: room for the national number plus one optional "0".
    final maxNational = _kMaxE164Digits - _selectedCountry.phoneCode.length;
    return maxNational + 1;
  }

  @override
  void initState() {
    super.initState();

    // Defensive: make sure the field starts empty.
    _phoneController.clear();

    _phoneFocusNode.addListener(() {
      if (mounted) setState(() {});
    });

    _phoneController.addListener(_validatePhone);

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOut,
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: Curves.easeOutCubic,
          ),
        );

    _entranceController.forward();
  }

  // ---------------------------------------------------------------------
  // Validation / formatting
  // ---------------------------------------------------------------------

  void _validatePhone() {
    final valid = _isValidForCountry(_phoneController.text.trim());
    if (valid != _isPhoneValid || _errorText != null) {
      setState(() {
        _isPhoneValid = valid;
        _errorText = null;
      });
    }
  }

  /// Removes leading zeros (only used for countries missing from the table).
  String _stripLeadingZeros(String digits) =>
      digits.replaceFirst(RegExp(r'^0+'), '');

  /// Converts what the user typed in LOCAL format (e.g. 03430203449) into
  /// the national significant number (e.g. 3430203449). Returns null when
  /// the input doesn't match the country's local format.
  String? _nationalFromInput(String digits) {
    if (digits.isEmpty) return null;

    final rule = _rule;
    if (rule == null) {
      final national = _stripLeadingZeros(digits);
      final maxNational = _kMaxE164Digits - _selectedCountry.phoneCode.length;
      final ok = national.length >= _kMinGenericNationalDigits &&
          national.length <= maxNational;
      return ok ? national : null;
    }

    bool lengthOk(String s) =>
        s.length >= rule.minLength && s.length <= rule.maxLength;

    final trunk = rule.trunkPrefix;

    // Typed with the local trunk prefix, e.g. 0343... -> 343...
    if (trunk.isNotEmpty && digits.startsWith(trunk)) {
      final national = digits.substring(trunk.length);
      if (lengthOk(national)) return national;
    }

    // Typed without a prefix: allowed when the country has none, or when
    // the prefix is optional there.
    if (trunk.isEmpty || rule.prefixOptional) {
      if (lengthOk(digits)) return digits;
    }

    return null;
  }

  bool _isValidForCountry(String digits) => _nationalFromInput(digits) != null;

  /// Builds the full E.164 number, e.g. 03430203449 -> +923430203449.
  String _buildFullPhoneNumber() {
    final national = _nationalFromInput(_phoneController.text.trim()) ?? '';
    final add = _rule?.addPrefix ?? '';
    return '+${_selectedCountry.phoneCode}$add$national';
  }

  /// Hint shown in the field: an example in local format.
  String get _hintText {
    final example = _kLocalExamples[_selectedCountry.countryCode];
    if (example != null && example.isNotEmpty) return example;

    final rule = _rule;
    if (rule != null) return '${rule.trunkPrefix}${'X' * rule.maxLength}';

    final fallback = _selectedCountry.example;
    return fallback.isNotEmpty ? fallback : 'Phone number';
  }

  // ---------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------

  Future<void> _continueWithPhone() async {
    if (isLoading || !_isPhoneValid) return;

    FocusScope.of(context).unfocus();
    HapticFeedback.selectionClick();

    final phone = _buildFullPhoneNumber();

    setState(() {
      isLoading = true;
      _errorText = null;
    });

    try {
      await _phoneAuthRepository.sendOtp(phoneNumber: phone);

      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtpVerificationScreen(phoneNumber: phone),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorText = _messageForError(e));
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  String _messageForError(Object error) {
    final code = error.toString().replaceFirst('Exception: ', '');

    switch (code) {
      case 'phone_not_registered_whatsapp':
        return 'This number is not available on WhatsApp.';
      case 'max_attempts_reached':
        return 'Too many attempts. Please try again later.';
      case 'resend_too_soon':
        return 'Please wait a minute before requesting another code.';
      case 'invalid_phone':
      case 'invalid_phone_format':
        return 'Please enter a valid mobile number.';
      default:
        return 'We could not send the code. Please try again.';
    }
  }

  void _openCountryPicker() {
    FocusScope.of(context).unfocus();
    showCountryPicker(
      context: context,
      // Favorites are pinned to the top; ALL countries are listed below.
      favorite: _kFavoriteCountries,
      showPhoneCode: true,
      countryListTheme: CountryListThemeData(
        bottomSheetHeight: MediaQuery.of(context).size.height * 0.65,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        inputDecoration: InputDecoration(
          labelText: 'Search country or code',
          prefixIcon: const Icon(Icons.search, size: 20),
          filled: true,
          fillColor: const Color(0xFFF2F4F7),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      onSelect: (Country country) {
        setState(() {
          _selectedCountry = country;
          _phoneController.clear();
          _errorText = null;
          _isPhoneValid = false;
        });
      },
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _phoneFocusNode.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: _backgroundColor,
        floatingActionButton: const AuthCustomerCareButton(),
        floatingActionButtonLocation: FloatingActionButtonLocation.endTop,
        body: SafeArea(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.only(bottom: 24.h + bottomInset * 0.1),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 60.h),

                    // ---- Hero image ------------------------------
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 40.w),
                      child: SizedBox(
                        width: double.infinity,
                        height: 220.h,
                        child: Center(
                          child: Container(
                            color: Colors.white,
                            child: Image.asset(
                              'assets/images/branding/hero_img.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                    ),

                    SizedBox(height: 28.h),

                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24.w),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Connect with trusted doctors for expert '
                              'advice, consultation and care — anytime, anywhere.',
                              style: TextStyle(
                                fontSize: 14.5.sp,
                                fontWeight: FontWeight.w400,
                                color: _subTextColor,
                                height: 1.5,
                              ),
                            ),

                            SizedBox(height: 28.h),

                            _buildPhoneCard(),

                            SizedBox(height: 22.h),

                            _buildContinueButton(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneCard() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPhonePill(),

          SizedBox(height: 12.h),

          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: _errorText != null
                ? Padding(
                    key: ValueKey(_errorText),
                    padding: EdgeInsets.only(left: 4.w),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          size: 15,
                          color: _errorColor,
                        ),
                        SizedBox(width: 6.w),
                        Expanded(
                          child: Text(
                            _errorText!,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: _errorColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : Padding(
                    key: const ValueKey('helper'),
                    padding: EdgeInsets.only(left: 4.w),
                    child: Text(
                      'Enter your WhatsApp number to continue',
                      style: TextStyle(
                        fontSize: 12.5.sp,
                        fontWeight: FontWeight.w400,
                        color: _hintTextColor,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhonePill() {
    return Container(
      height: 54.h,
      decoration: BoxDecoration(
        color: _pillColor,
        borderRadius: BorderRadius.circular(27.r),
      ),
      child: Row(
        children: [
          SizedBox(width: 6.w),

          // ---- Country code selector (country_picker package) -------
          InkWell(
            borderRadius: BorderRadius.circular(20.r),
            onTap: _openCountryPicker,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _selectedCountry.flagEmoji,
                    style: TextStyle(fontSize: 18.sp),
                  ),
                  SizedBox(width: 6.w),
                  Text(
                    '+${_selectedCountry.phoneCode}',
                    style: TextStyle(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w500,
                      color: _textColor,
                    ),
                  ),
                  SizedBox(width: 2.w),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18.sp,
                    color: Colors.grey.shade500,
                  ),
                ],
              ),
            ),
          ),

          // Divider between code and number
          Container(height: 22.h, width: 1, color: Colors.grey.shade300),
          SizedBox(width: 14.w),

          Expanded(
            child: TextField(
              controller: _phoneController,
              focusNode: _phoneFocusNode,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              // autofillHints intentionally omitted: platform autofill was
              // pre-filling saved numbers and eating the max-length budget.
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(_maxInputLength),
              ],
              cursorColor: _primaryColor,
              style: TextStyle(
                fontSize: 15.5.sp,
                fontWeight: FontWeight.w500,
                color: _textColor,
                letterSpacing: 0.3,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                isCollapsed: true,
                hintText: _hintText,
                hintStyle: TextStyle(
                  fontSize: 15.5.sp,
                  fontWeight: FontWeight.w400,
                  color: Colors.grey.shade400,
                ),
              ),
              onSubmitted: (_) => _continueWithPhone(),
            ),
          ),

          SizedBox(width: 14.w),
        ],
      ),
    );
  }

  Widget _buildContinueButton() {
    final enabled = _isPhoneValid && !isLoading;

    return SizedBox(
      width: double.infinity,
      height: 52.h,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(27.r),
          gradient: LinearGradient(
            colors: !enabled
                ? [
                    _primaryColor.withOpacity(0.35),
                    _primaryColor.withOpacity(0.35),
                  ]
                : [_primaryColor, _primaryDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: !enabled
              ? []
              : [
                  BoxShadow(
                    color: _primaryColor.withOpacity(0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(27.r),
            onTap: enabled ? _continueWithPhone : null,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: isLoading
                    ? const SizedBox(
                        key: ValueKey('loading'),
                        width: 21,
                        height: 21,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Continue',
                        key: ValueKey('label'),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}