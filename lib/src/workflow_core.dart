import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'native_device.dart';

const String premblyDefaultBaseUrl = 'https://backend.prembly.com';
const String premblyWorkflowSessionsPath = '/api/v1/compliance-workflow/sdk/v1/sessions/';

/// Creating a workflow session can take a while on a cold start; the web SDK uses the same floor.
const Duration premblyWorkflowTimeout = Duration(seconds: 15);

/// The person going through the workflow.
class WorkflowCustomer {
  const WorkflowCustomer({
    required this.firstName,
    required this.lastName,
    required this.email,
    this.phone,
    this.reference,
  });

  final String firstName;
  final String lastName;
  final String email;
  final String? phone;

  /// Your own reference to the person.
  final String? reference;
}

/// An event the hosted workflow reports. No personal data.
class WorkflowEvent {
  const WorkflowEvent({required this.type, required this.sessionId, this.nodeId});

  final String type;
  final String sessionId;
  final String? nodeId;
}

/// How the flow ended: `completed`, `failed`, `manual_review`, `expired` (from the hosted app),
/// `cancelled` (closed before an end state), or `failed` with [errorCode] if it could not start.
class WorkflowResult {
  const WorkflowResult({
    required this.status,
    this.sessionId,
    this.lastEvent,
    this.errorCode,
    this.errorMessage,
  });

  final String status;
  final String? sessionId;

  /// For `cancelled`: the last event seen before the close. `processing` means the person had
  /// finished their steps and the checks carry on in the background.
  final String? lastEvent;
  final String? errorCode;
  final String? errorMessage;

  @override
  String toString() => 'WorkflowResult($status, sessionId: $sessionId, lastEvent: $lastEvent, '
      'error: $errorCode)';
}

class WorkflowOptions {
  const WorkflowOptions({
    required this.publishableKey,
    required this.workflowId,
    required this.customer,
    required this.callback,
    this.metadata,
    this.redirectUrl,
    this.baseUrl,
    this.hostedUrl,
    this.collectDeviceData = true,
    this.onEvent,
  });

  /// Your public key: `live_pk_...` or `test_pk_...`. A secret key is refused.
  final String publishableKey;
  final String workflowId;
  final WorkflowCustomer customer;

  /// Your own data, stored with the run.
  final Map<String, dynamic>? metadata;
  final String? redirectUrl;

  /// Override the API base URL (for example for a staging server).
  final String? baseUrl;

  /// Open the workflow at this hosted app instead of the link the backend returns, as
  /// `<hostedUrl>?session=<id>`. For testing a local or staging build of the hosted app.
  final String? hostedUrl;

  /// Read the phone's own device ID and details and give them to the workflow, so its device
  /// checks see the real device. On by default. No permission is asked for.
  final bool collectDeviceData;

  /// Every event the workflow reports.
  final void Function(WorkflowEvent event)? onEvent;

  /// Called once when the flow ends.
  final void Function(WorkflowResult result) callback;
}

/// Why a workflow could not start.
class WorkflowError implements Exception {
  const WorkflowError(this.code, this.message);

  /// `invalid_key`, `invalid_request`, `unauthorised`, `not_found`, `rate_limited`,
  /// `server_error`, `network_error`, `timeout` or `not_available`.
  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

class WorkflowSessionInfo {
  const WorkflowSessionInfo({required this.sessionId, required this.link});

  final String sessionId;
  final String link;
}

final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

bool _blank(String? value) => value == null || value.trim().isEmpty;

void _validate(WorkflowOptions options) {
  final key = options.publishableKey.trim();
  if (!key.startsWith('live_pk_') && !key.startsWith('test_pk_')) {
    throw const WorkflowError(
      'invalid_key',
      'publishableKey must be your public key (live_pk_... or test_pk_...). '
          'Never put a secret key (live_sk_ / test_sk_) in an app.',
    );
  }
  if (_blank(options.workflowId)) {
    throw const WorkflowError('invalid_request', 'workflowId is required.');
  }
  final c = options.customer;
  if (_blank(c.firstName) || _blank(c.lastName)) {
    throw const WorkflowError(
        'invalid_request', 'customer.firstName and customer.lastName are required.');
  }
  if (_blank(c.email) || !_emailPattern.hasMatch(c.email)) {
    throw const WorkflowError('invalid_request', 'customer.email must be a valid email.');
  }
}

String _codeForStatus(int status) {
  if (status == 401 || status == 403) return 'unauthorised';
  if (status == 404) return 'not_found';
  if (status == 429) return 'rate_limited';
  if (status >= 400 && status < 500) return 'invalid_request';
  return 'server_error';
}

/// Create a workflow session with the public key, the same call the web SDK makes. Throws a
/// [WorkflowError]; the caller turns it into a callback.
Future<WorkflowSessionInfo> createWorkflowSession(
  WorkflowOptions options, {
  http.Client? client,
  String platform = 'unknown',
}) async {
  _validate(options);
  final baseUrl = (options.baseUrl ?? premblyDefaultBaseUrl).replaceAll(RegExp(r'/+$'), '');
  final c = options.customer;
  final body = jsonEncode({
    'workflow_id': options.workflowId,
    'customer': {
      'first_name': c.firstName,
      'last_name': c.lastName,
      'email': c.email,
      if (c.phone != null) 'phone': c.phone,
      if (c.reference != null) 'reference': c.reference,
    },
    'metadata': options.metadata ?? <String, dynamic>{},
    if (options.redirectUrl != null) 'redirect_url': options.redirectUrl,
  });

  final httpClient = client ?? http.Client();
  try {
    final response = await httpClient
        .post(
          Uri.parse('$baseUrl$premblyWorkflowSessionsPath'),
          headers: {
            'Content-Type': 'application/json',
            'X-Publishable-Key': options.publishableKey.trim(),
            'X-SDK-Platform': platform,
            'X-SDK-Version': premblySdkVersion,
          },
          body: body,
        )
        .timeout(premblyWorkflowTimeout);

    Map<String, dynamic>? decoded;
    try {
      final parsed = jsonDecode(response.body);
      if (parsed is Map<String, dynamic>) decoded = parsed;
    } catch (_) {
      // not JSON: handled below
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded?['message'];
      throw WorkflowError(
        _codeForStatus(response.statusCode),
        message is String && message.isNotEmpty
            ? message
            : 'The workflow session could not be created (HTTP ${response.statusCode}).',
      );
    }
    final data = decoded?['data'];
    final sessionId = data is Map ? data['session_id'] : null;
    final link = data is Map ? data['link'] : null;
    if (sessionId is! String || sessionId.trim().isEmpty || link is! String || link.trim().isEmpty) {
      throw const WorkflowError('server_error', 'The workflow session response was incomplete.');
    }
    return WorkflowSessionInfo(sessionId: sessionId, link: link);
  } on WorkflowError {
    rethrow;
  } on TimeoutException {
    throw const WorkflowError('timeout', 'The workflow session request timed out.');
  } catch (e) {
    throw WorkflowError('network_error', e.toString());
  } finally {
    if (client == null) httpClient.close();
  }
}

const _endStates = ['completed', 'failed', 'manual_review', 'expired'];

bool isWorkflowEndState(String type) => _endStates.contains(type);

/// A message from the hosted workflow, as the envelope the web SDK documents
/// (`{source: 'prembly-sdk', product: 'workflow', type, session_id, node_id?}`), plus the legacy
/// `prembly-workflow-sdk` shape. Anything else (another product, another source, bad JSON) is null.
WorkflowEvent? parseWorkflowMessage(String raw) {
  final Object? data;
  try {
    data = jsonDecode(raw);
  } catch (_) {
    return null;
  }
  if (data is! Map) return null;
  final current = data['source'] == 'prembly-sdk' && data['product'] == 'workflow';
  final legacy = data['source'] == 'prembly-workflow-sdk';
  if (!current && !legacy) return null;
  final type = data['type'];
  final sessionId = data['session_id'];
  if (type is! String || sessionId is! String) return null;
  final nodeId = data['node_id'];
  return WorkflowEvent(type: type, sessionId: sessionId, nodeId: nodeId is String ? nodeId : null);
}

/// The origin of a link (scheme, host and port only), or '' when it is not an http(s) URL.
String originOf(String link) {
  final uri = Uri.tryParse(link);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) {
    return '';
  }
  // Like a browser's origin: the port is left out when it is the scheme's default.
  final defaultPort = uri.scheme == 'https' ? 443 : 80;
  final port = uri.hasPort && uri.port != defaultPort ? ':${uri.port}' : '';
  return '${uri.scheme}://${uri.host.toLowerCase()}$port';
}

/// `<hostedUrl>?session=<id>`, the same shape the web SDK builds.
String withSession(String hostedUrl, String sessionId) {
  final uri = Uri.parse(hostedUrl);
  final query = Map<String, String>.from(uri.queryParameters)..['session'] = sessionId;
  return uri.replace(queryParameters: query).toString();
}
