// Mobile implementation using WebView for Stripe Checkout
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../firebase_options.dart';
import '../services/payment_service.dart';
import '../services/admin_settings_service.dart';
import '../theme/app_theme.dart';

// Export as PaymentPageImpl for conditional imports
class PaymentPageImpl extends StatefulWidget {
  final String type;
  final double amount;
  final String? auctionId;
  final String title;

  const PaymentPageImpl({
    super.key,
    required this.type,
    required this.amount,
    this.auctionId,
    required this.title,
  });

  @override
  State<PaymentPageImpl> createState() => _PaymentPageMobileState();
}

class _PaymentPageMobileState extends State<PaymentPageImpl> {
  final PaymentService _paymentService = PaymentService();
  late final WebViewController _controller;
  bool _isInitializing = true;
  bool _isLoading = false;
  String? _clientSecret;
  String? _paymentId;
  String? _error;
  String? _status = 'initializing';
  StreamSubscription<DocumentSnapshot>? _paymentSubscription;
  Timer? _longWaitTimer;
  bool _showLongWaitBanner = false;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
    _initializePayment();
  }

  @override
  void dispose() {
    _longWaitTimer?.cancel();
    _paymentSubscription?.cancel();
    super.dispose();
  }

  void _initializeWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..addJavaScriptChannel(
        'StripePayment',
        onMessageReceived: (JavaScriptMessage message) {
          if (mounted && message.message == 'success') {
            _longWaitTimer?.cancel();
            _handlePaymentSuccess();
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (mounted) {
              setState(() => _isLoading = true);
            }
          },
          onPageFinished: (String url) {
            if (mounted) {
              setState(() => _isLoading = false);
            }
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('WebView error: ${error.description}');
          },
        ),
      );
  }

  Future<void> _initializePayment() async {
    try {
      if (mounted) {
        setState(() {
          _isInitializing = true;
          _error = null;
          _status = 'initializing';
        });
      }

      // Ensure Stripe publishable key is set (from Firestore if not set at startup)
      if (PaymentService.publishableKey == null || PaymentService.publishableKey!.isEmpty) {
        try {
          final key = await AdminSettingsService().getStripePublishableKey();
          if (key != null && key.isNotEmpty) {
            PaymentService.setPublishableKey(key);
          }
        } catch (_) {}
      }

      // Create PaymentIntent
      final result = await _paymentService.createPaymentIntent(
        type: widget.type,
        amount: widget.amount,
        currency: 'aed',
        auctionId: widget.auctionId,
      );

      if (!mounted) return;

      setState(() {
        _clientSecret = result['clientSecret'] as String;
        _paymentId = result['paymentId'] as String;
        _isInitializing = false;
        _status = 'ready';
      });

      // Start listening to payment status
      _startPaymentStatusListener();

      // Load Stripe Checkout in WebView
      if (mounted) {
        _loadStripeCheckout();
      }
    } catch (e) {
      if (!mounted) return;
      
      final errorMessage = e.toString();
      setState(() {
        _error = 'Failed to initialize payment: $errorMessage';
        _isInitializing = false;
        _status = 'error';
      });
      debugPrint('Payment initialization error: $e');
    }
  }

  void _startPaymentStatusListener() {
    if (_paymentId == null) return;

    _paymentSubscription?.cancel();
    _paymentSubscription = _paymentService
        .streamPayment(_paymentId!)
        .listen((snapshot) {
      if (!mounted) return;

      final data = snapshot.data() as Map<String, dynamic>?;
      if (data == null) return;

      final status = data['status'] as String?;
      setState(() => _status = status);

      if (status == 'succeeded') {
        _handlePaymentSuccess();
      } else if (status == 'failed') {
        setState(() => _error = 'Payment failed');
      }
    });
  }

  void _loadStripeCheckout() {
    if (_clientSecret == null) return;

    final publishableKey = PaymentService.publishableKey;
    
    // Validate publishable key is available
    if (publishableKey == null || publishableKey.isEmpty) {
      if (mounted) {
        setState(() {
          _error = 'Stripe publishable key is not configured';
          _status = 'error';
        });
      }
      return;
    }
    
    // Properly encode values for safe JavaScript injection
    final safePublishableKey = jsonEncode(publishableKey);
    final safeClientSecret = jsonEncode(_clientSecret);
    // Stripe requires a valid HTTPS return_url. In WebView (loadHtmlString) window.location.href
    // is about:blank/data URL, which Stripe rejects. Use the app's web origin.
    final returnUrl = 'https://${DefaultFirebaseOptions.currentPlatform.projectId}.web.app/payment-success';
    final safeReturnUrl = jsonEncode(returnUrl);

    // Create HTML page with Stripe Checkout
    final html = '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: #f5f5f5;
      padding: 16px;
    }
    .container {
      max-width: 500px;
      margin: 0 auto;
      background: white;
      border-radius: 12px;
      padding: 24px;
      box-shadow: 0 2px 8px rgba(0,0,0,0.1);
    }
    .amount {
      text-align: center;
      margin-bottom: 24px;
      padding: 16px;
      background: #e3f2fd;
      border-radius: 8px;
    }
    .amount-label {
      font-size: 14px;
      color: #666;
      margin-bottom: 8px;
    }
    .amount-value {
      font-size: 28px;
      font-weight: bold;
      color: #1976d2;
    }
    #payment-element {
      margin-bottom: 24px;
    }
    #submit {
      width: 100%;
      padding: 16px;
      background: #1976d2;
      color: white;
      border: none;
      border-radius: 8px;
      font-size: 16px;
      font-weight: 600;
      cursor: pointer;
      transition: background 0.3s;
    }
    #submit:hover:not(:disabled) {
      background: #1565c0;
    }
    #submit:disabled {
      background: #ccc;
      cursor: not-allowed;
    }
    #error-message {
      color: #d32f2f;
      font-size: 14px;
      margin-top: 12px;
      text-align: center;
    }
    .spinner {
      display: inline-block;
      width: 16px;
      height: 16px;
      border: 2px solid rgba(255,255,255,.3);
      border-radius: 50%;
      border-top-color: white;
      animation: spin 1s ease-in-out infinite;
    }
    @keyframes spin {
      to { transform: rotate(360deg); }
    }
  </style>
  <script src="https://js.stripe.com/v3/"></script>
</head>
<body>
  <div class="container">
    <div class="amount">
      <div class="amount-label">Amount Due</div>
      <div class="amount-value">AED ${widget.amount.toStringAsFixed(2)}</div>
    </div>
    <form id="payment-form">
      <div id="payment-element"></div>
      <button id="submit">
        <span id="button-text">Pay Now</span>
      </button>
      <div id="error-message"></div>
    </form>
  </div>

  <script>
    const stripe = Stripe($safePublishableKey);
    const elements = stripe.elements({
      clientSecret: $safeClientSecret,
      appearance: {
        theme: 'stripe',
        variables: {
          colorPrimary: '#1976d2',
          borderRadius: '8px',
        },
      },
    });

    const paymentElement = elements.create('payment');
    paymentElement.mount('#payment-element');

    const form = document.getElementById('payment-form');
    const submitBtn = document.getElementById('submit');
    const buttonText = document.getElementById('button-text');
    const errorDiv = document.getElementById('error-message');

    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      submitBtn.disabled = true;
      buttonText.innerHTML = '<span class="spinner"></span> Processing...';
      errorDiv.textContent = '';

      const {error} = await stripe.confirmPayment({
        elements,
        confirmParams: {
          return_url: $safeReturnUrl,
        },
        redirect: 'if_required',
      });

      if (error) {
        errorDiv.textContent = error.message;
        submitBtn.disabled = false;
        buttonText.textContent = 'Pay Now';
      } else {
        buttonText.textContent = 'Payment successful!';
        if (window.StripePayment) window.StripePayment.postMessage('success');
      }
    });
  </script>
</body>
</html>
    ''';

    _controller.loadHtmlString(html);

    // If payment is still not succeeded after 90s, show "taking longer" banner
    _longWaitTimer?.cancel();
    _longWaitTimer = Timer(const Duration(seconds: 90), () {
      if (mounted && _status != 'succeeded' && _error == null) {
        setState(() => _showLongWaitBanner = true);
      }
    });
  }

  void _handlePaymentSuccess() {
    _longWaitTimer?.cancel();
    Navigator.of(context).pop(true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Payment successful!'),
        backgroundColor: AppTheme.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: AppTheme.error,
              ),
              const SizedBox(height: 24),
              Text(
                'Payment Error',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() => _error = null);
                  _initializePayment();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    if (_isInitializing) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 24),
            Text('Initializing payment...'),
          ],
        ),
      );
    }

    if (_status == 'succeeded') {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 64,
              color: AppTheme.success,
            ),
            const SizedBox(height: 24),
            Text(
              'Payment Successful!',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            Text(
              'Your payment has been processed successfully.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_isLoading)
          const Center(
            child: CircularProgressIndicator(),
          ),
        if (_showLongWaitBanner)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Material(
              elevation: 8,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Payment is taking longer than usual.',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'If you completed payment, check your wallet or auction status. You can go back and try again if needed.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade600,
                            ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                setState(() => _showLongWaitBanner = false);
                              },
                              child: const Text('Keep waiting'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                _longWaitTimer?.cancel();
                                Navigator.of(context).pop(false);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryBlue,
                              ),
                              child: const Text('Go back'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
