import 'package:flutter/material.dart';
import 'package:prembly_identity_kyc/prembly_identity_kyc.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Identity KYC Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String _result = 'Waiting for verification...';

  void _startVerification() {
    PremblyIdentityKyc.verify(
      context: context,
      options: IdentityKycOptions(
        firstName: 'John',
        lastName: 'Doe',
        email: 'john@example.com',
        phone: '+2348012345678',
        widgetKey: 'wdgt_44dbb67791344ca7b30644787ada3f00',
        widgetId: 'ee7c80fb-c0cc-4762-b7a7-a4045d262e74',
        metadata: {
          'transaction_id': 'txn_123',
        },
        callback: (response) {
          setState(() {
            _result = 'Result: $response';
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Identity KYC SDK Demo'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                _result,
                textAlign: TextAlign.center,
              ),
            ),
            ElevatedButton(
              onPressed: _startVerification,
              child: const Text('Start KYC Verification'),
            ),
          ],
        ),
      ),
    );
  }
}
