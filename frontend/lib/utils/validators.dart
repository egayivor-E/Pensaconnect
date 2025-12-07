import 'dart:convert';

import 'package:pensaconnect/config/config.dart';

class Validators {
  // ================================
  // MESSAGE VALIDATION
  // ================================

  static ValidationResult validateMessage(String? message) {
    if (message == null || message.trim().isEmpty) {
      return ValidationResult(
        isValid: false,
        errorMessage: 'Message cannot be empty',
      );
    }

    final trimmedMessage = message.trim();

    // Length validation
    if (trimmedMessage.length > Config.maxMessageLength) {
      return ValidationResult(
        isValid: false,
        errorMessage:
            'Message too long (max ${Config.maxMessageLength} characters)',
      );
    }

    // Profanity filter
    final profanityCheck = _containsProfanity(trimmedMessage);
    if (profanityCheck.isValid == false) {
      return profanityCheck;
    }

    // Spam detection
    final spamCheck = _containsSpam(trimmedMessage);
    if (spamCheck.isValid == false) {
      return spamCheck;
    }

    // URL validation
    final urlCheck = _validateUrls(trimmedMessage);
    if (urlCheck.isValid == false) {
      return urlCheck;
    }

    return ValidationResult(isValid: true);
  }

  // ================================
  // RATE LIMITING
  // ================================

  static bool isWithinRateLimit(DateTime? lastMessageTime) {
    if (lastMessageTime == null) return true;

    return DateTime.now().difference(lastMessageTime) >=
        Config.messageRateLimit;
  }

  static bool isUserOverRateLimit(Map<String, int> userMessageCount) {
    final now = DateTime.now();
    final oneMinuteAgo = now.subtract(const Duration(minutes: 1));

    // Clean up old entries
    userMessageCount.removeWhere(
      (_, timestamp) =>
          DateTime.fromMillisecondsSinceEpoch(timestamp).isBefore(oneMinuteAgo),
    );

    return userMessageCount.length >= Config.maxMessagesPerMinute;
  }

  // ================================
  // EMAIL VALIDATION
  // ================================

  static ValidationResult validateEmail(String? email) {
    if (email == null || email.isEmpty) {
      return ValidationResult(
        isValid: false,
        errorMessage: 'Email is required',
      );
    }

    final emailRegex = RegExp(
      r'^[a-zA-Z0-9.]+@[a-zA-Z0-9]+\.[a-zA-Z]+',
      caseSensitive: false,
    );

    if (!emailRegex.hasMatch(email.trim())) {
      return ValidationResult(
        isValid: false,
        errorMessage: 'Please enter a valid email address',
      );
    }

    return ValidationResult(isValid: true);
  }

  // ================================
  // PASSWORD VALIDATION
  // ================================

  static ValidationResult validatePassword(String? password) {
    if (password == null || password.isEmpty) {
      return ValidationResult(
        isValid: false,
        errorMessage: 'Password is required',
      );
    }

    if (password.length < 8) {
      return ValidationResult(
        isValid: false,
        errorMessage: 'Password must be at least 8 characters long',
      );
    }

    // Check for at least one uppercase letter
    if (!password.contains(RegExp(r'[A-Z]'))) {
      return ValidationResult(
        isValid: false,
        errorMessage: 'Password must contain at least one uppercase letter',
      );
    }

    // Check for at least one lowercase letter
    if (!password.contains(RegExp(r'[a-z]'))) {
      return ValidationResult(
        isValid: false,
        errorMessage: 'Password must contain at least one lowercase letter',
      );
    }

    // Check for at least one number
    if (!password.contains(RegExp(r'[0-9]'))) {
      return ValidationResult(
        isValid: false,
        errorMessage: 'Password must contain at least one number',
      );
    }

    return ValidationResult(isValid: true);
  }

  // ================================
  // USERNAME VALIDATION
  // ================================

  static ValidationResult validateUsername(String? username) {
    if (username == null || username.isEmpty) {
      return ValidationResult(
        isValid: false,
        errorMessage: 'Username is required',
      );
    }

    final trimmedUsername = username.trim();

    if (trimmedUsername.length < 3) {
      return ValidationResult(
        isValid: false,
        errorMessage: 'Username must be at least 3 characters long',
      );
    }

    if (trimmedUsername.length > 30) {
      return ValidationResult(
        isValid: false,
        errorMessage: 'Username must be less than 30 characters',
      );
    }

    // Alphanumeric and underscore only
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(trimmedUsername)) {
      return ValidationResult(
        isValid: false,
        errorMessage:
            'Username can only contain letters, numbers, and underscores',
      );
    }

    return ValidationResult(isValid: true);
  }

  // ================================
  // NAME VALIDATION
  // ================================

  static ValidationResult validateName(
    String? name, {
    String fieldName = 'Name',
  }) {
    if (name == null || name.trim().isEmpty) {
      return ValidationResult(
        isValid: false,
        errorMessage: '$fieldName is required',
      );
    }

    final trimmedName = name.trim();

    if (trimmedName.length < 2) {
      return ValidationResult(
        isValid: false,
        errorMessage: '$fieldName must be at least 2 characters long',
      );
    }

    if (trimmedName.length > 50) {
      return ValidationResult(
        isValid: false,
        errorMessage: '$fieldName must be less than 50 characters',
      );
    }

    // Only letters, spaces, hyphens, and apostrophes
    if (!RegExp(r"^[a-zA-Zà-ÿÀ-Ÿ '\-]+$").hasMatch(trimmedName)) {
      return ValidationResult(
        isValid: false,
        errorMessage:
            '$fieldName can only contain letters, spaces, hyphens, and apostrophes',
      );
    }

    return ValidationResult(isValid: true);
  }

  // ================================
  // PHONE NUMBER VALIDATION
  // ================================

  static ValidationResult validatePhoneNumber(String? phone) {
    if (phone == null || phone.isEmpty) {
      return ValidationResult(isValid: true); // Phone is optional
    }

    final cleanedPhone = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');

    // Basic international phone validation
    if (!RegExp(r'^\+?[0-9]{10,15}$').hasMatch(cleanedPhone)) {
      return ValidationResult(
        isValid: false,
        errorMessage: 'Please enter a valid phone number',
      );
    }

    return ValidationResult(isValid: true);
  }

  // ================================
  // PRIVATE VALIDATION METHODS
  // ================================

  static ValidationResult _containsProfanity(String text) {
    if (!Config.enableMessageModeration) {
      return ValidationResult(isValid: true);
    }

    final profanityPatterns = [
      // Basic profanity patterns - expand this list
      r'\b(asshole|fuck|shit|bitch|damn|hell)\b',
      r'\b(cunt|piss|dick|pussy|whore|slut)\b',
      r'\b(retard|fag|nigger|chink|spic)\b',
    ];

    for (final pattern in profanityPatterns) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(text)) {
        return ValidationResult(
          isValid: false,
          errorMessage: 'Message contains inappropriate content',
        );
      }
    }

    return ValidationResult(isValid: true);
  }

  static ValidationResult _containsSpam(String text) {
    final spamPatterns = [
      // Repeated characters
      r'(.)\1{5,}',
      // Excessive punctuation
      r'[!?\.]{4,}',
      // ALL CAPS
      r'^[A-Z\s]{20,}$',
      // Common spam phrases
      r'\b(free money|make money fast|click here|buy now|limited time)\b',
    ];

    for (final pattern in spamPatterns) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(text)) {
        return ValidationResult(
          isValid: false,
          errorMessage: 'Message appears to be spam',
        );
      }
    }

    return ValidationResult(isValid: true);
  }

  static ValidationResult _validateUrls(String text) {
    final urlRegex = RegExp(
      r'https?://[^\s/$.?#].[^\s]*',
      caseSensitive: false,
    );

    final matches = urlRegex.allMatches(text);

    if (matches.length > 3) {
      return ValidationResult(
        isValid: false,
        errorMessage: 'Too many URLs in message',
      );
    }

    // Check for suspicious domains
    for (final match in matches) {
      final url = match.group(0)!;
      try {
        final uri = Uri.parse(url);
        final domain = uri.host.toLowerCase();

        final suspiciousDomains = [
          'bit.ly', 'tinyurl.com', 'goo.gl', 't.co', // URL shorteners
          '.ru', '.cn', '.tk', // Suspicious TLDs
        ];

        for (final suspicious in suspiciousDomains) {
          if (domain.contains(suspicious)) {
            return ValidationResult(
              isValid: false,
              errorMessage: 'Suspicious URL detected',
            );
          }
        }
      } catch (e) {
        return ValidationResult(
          isValid: false,
          errorMessage: 'Invalid URL in message',
        );
      }
    }

    return ValidationResult(isValid: true);
  }

  // ================================
  // BATCH VALIDATION
  // ================================

  static Map<String, ValidationResult> validateForm(
    Map<String, String> fields,
  ) {
    final results = <String, ValidationResult>{};

    for (final entry in fields.entries) {
      switch (entry.key) {
        case 'email':
          results[entry.key] = validateEmail(entry.value);
          break;
        case 'password':
          results[entry.key] = validatePassword(entry.value);
          break;
        case 'username':
          results[entry.key] = validateUsername(entry.value);
          break;
        case 'firstName':
        case 'first_name':
          results[entry.key] = validateName(
            entry.value,
            fieldName: 'First name',
          );
          break;
        case 'lastName':
        case 'last_name':
          results[entry.key] = validateName(
            entry.value,
            fieldName: 'Last name',
          );
          break;
        case 'phone':
        case 'phoneNumber':
          results[entry.key] = validatePhoneNumber(entry.value);
          break;
        case 'message':
        case 'content':
          results[entry.key] = validateMessage(entry.value);
          break;
        default:
          results[entry.key] = ValidationResult(isValid: true);
      }
    }

    return results;
  }

  // ================================
  // UTILITY METHODS
  // ================================

  static bool isFormValid(Map<String, ValidationResult> results) {
    return results.values.every((result) => result.isValid);
  }

  static List<String> getErrorMessages(Map<String, ValidationResult> results) {
    return results.values
        .where((result) => !result.isValid && result.errorMessage != null)
        .map((result) => result.errorMessage!)
        .toList();
  }
}

// ================================
// VALIDATION RESULT CLASS
// ================================

class ValidationResult {
  final bool isValid;
  final String? errorMessage;

  const ValidationResult({required this.isValid, this.errorMessage});

  @override
  String toString() =>
      'ValidationResult(isValid: $isValid, errorMessage: $errorMessage)';
}
