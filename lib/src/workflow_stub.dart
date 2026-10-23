import 'package:flutter/material.dart';

import 'workflow_core.dart';

/// The workflow screen is only available inside an iOS or Android app. Anywhere else it reports
/// `not_available` and closes.
class WorkflowWebView extends StatefulWidget {
  final WorkflowOptions options;
  const WorkflowWebView({Key? key, required this.options}) : super(key: key);

  @override
  State<WorkflowWebView> createState() => _WorkflowWebViewState();
}

class _WorkflowWebViewState extends State<WorkflowWebView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.options.callback(const WorkflowResult(
        status: 'failed',
        errorCode: 'not_available',
        errorMessage: 'The workflow is only available in iOS and Android apps.',
      ));
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
