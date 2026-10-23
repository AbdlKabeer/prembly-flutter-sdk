class IdentityKycOptions {
  final String firstName;
  final String lastName;
  final String email;
  final String? phone;
  final String widgetKey; // Previously merchantKey
  final String widgetId;  // Previously configId
  final String? userRef;
  final bool? isTest;
  final Map<String, dynamic>? metadata;

  /// Read the phone's own device ID and details and give them to the widget, so the check sees the
  /// real device and not a guess from the browser. On by default. If the phone cannot be read the
  /// widget carries on with what the web page can see. No permission is asked for, and location is
  /// never read. Mobile only; the web build always uses what the browser can see.
  final bool collectDeviceData;

  final void Function(Map<String, dynamic> response)? callback;

  IdentityKycOptions({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.widgetKey,
    required this.widgetId,
    this.callback,
    this.phone,
    this.userRef,
    this.isTest,
    this.metadata,
    this.collectDeviceData = true,
  });

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
      'widget_key': widgetKey,
      'widget_id': widgetId,
    };

    if (phone != null) data['phone'] = phone;
    if (userRef != null) data['user_ref'] = userRef;
    if (isTest != null) data['is_test'] = isTest;
    if (metadata != null) data['metadata'] = metadata;

    return data;
  }
}
