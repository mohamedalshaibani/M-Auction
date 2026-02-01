// Web-only implementation using Stripe Payment Element
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:ui_web' as ui_web;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/payment_service.dart';
import '../services/admin_settings_service.dart';

// Export as PaymentPageImpl for conditional imports
class PaymentPageImpl extends StatefulWidget {
  final String type; // 'deposit', 'listing_fee', or 'buyer_commission'
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
  State<PaymentPageImpl> createState() => _PaymentPageWebState();
}

class _PaymentPageWebState extends State<PaymentPageImpl> {
  final PaymentService _paymentService = PaymentService();
  bool _isInitializing = true;
  bool _isProcessing = false;
  String? _clientSecret;
  String? _paymentId;
  String? _error;
  String? _status = 'initializing';
  StreamSubscription<DocumentSnapshot>? _paymentSubscription;
  String? _containerId;

  @override
  void initState() {
    super.initState();
    _initializePayment();
  }

  @override
  void dispose() {
    _paymentSubscription?.cancel();
    _cleanupStripe();
    super.dispose();
  }

  void _cleanupStripe() {
    try {
      if (_containerId != null) {
        final container = html.document.getElementById(_containerId!);
        container?.remove();
      }
      js.context.callMethod('eval', ['''
        if (window.paymentElement) {
          try {
            window.paymentElement.unmount();
          } catch(e) {}
          window.paymentElement = null;
        }
        if (window.stripeElements) {
          window.stripeElements = null;
        }
        if (window.stripeInstance) {
          window.stripeInstance = null;
        }
      ''']);
    } catch (e) {
      // Ignore cleanup errors
    }
  }

  Future<void> _initializePayment() async {
    try {
      setState(() {
        _isInitializing = true;
        _error = null;
        _status = 'initializing';
      });

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

      setState(() {
        _clientSecret = result['clientSecret'] as String;
        _paymentId = result['paymentId'] as String;
        _isInitializing = false;
        _status = 'ready';
      });

      // Start listening to payment status
      _startPaymentStatusListener();

      // Create container ID and register view factory
      _containerId = 'stripe-payment-element-${DateTime.now().millisecondsSinceEpoch}';
      
      // Register platform view for Stripe container
      ui_web.platformViewRegistry.registerViewFactory(
        _containerId!,
        (int viewId) {
          final div = html.DivElement()
            ..id = _containerId!
            ..style.width = '100%'
            ..style.height = '400px'
            ..style.padding = '16px'
            ..style.border = '1px solid #ddd'
            ..style.borderRadius = '8px'
            ..style.backgroundColor = '#ffffff';

          // Initialize Stripe after container is created
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted && _clientSecret != null && _containerId != null) {
              _initStripePaymentElement(_clientSecret!);
            }
          });

          return div;
        },
      );
    } catch (e) {
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
      if (status != null && status != _status) {
        setState(() {
          _status = status;
          if (status == 'succeeded') {
            _isProcessing = false;
          } else if (status == 'failed' || status == 'canceled') {
            _isProcessing = false;
            _error = data['error'] as String? ?? 'Payment failed';
          }
        });

        if (status == 'succeeded') {
          // Payment successful - navigate back or show success
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              Navigator.of(context).pop(true);
            }
          });
        }
      }
    });
  }

  void _initStripePaymentElement(String clientSecret) {
    final publishableKey = PaymentService.publishableKey;
    if (publishableKey == null || publishableKey.isEmpty) {
      setState(() {
        _error = 'Stripe publishable key not configured';
        _status = 'error';
      });
      return;
    }

    if (_containerId == null) return;

    try {
      // Initialize Stripe.js and Payment Element after container is mounted
      Future.delayed(const Duration(milliseconds: 300), () {
        js.context.callMethod('eval', ['''
          (function() {
            if (typeof Stripe === 'undefined') {
              console.error('Stripe.js not loaded');
              return;
          }
          
          const publishableKey = '$publishableKey';
          const clientSecret = '$clientSecret';
          const containerId = '$_containerId';
          
          if (!window.stripeInstance) {
            window.stripeInstance = Stripe(publishableKey);
          }
          
          if (!window.stripeElements) {
            window.stripeElements = window.stripeInstance.elements({
              clientSecret: clientSecret
            });
          }
          
          if (!window.paymentElement) {
            window.paymentElement = window.stripeElements.create('payment');
            window.paymentElement.mount('#' + containerId);
          }
          
          // Handle form submission
          const form = document.getElementById('payment-form');
          if (form) {
            form.addEventListener('submit', async function(e) {
              e.preventDefault();
              
              const {error} = await window.stripeInstance.confirmPayment({
                elements: window.stripeElements,
                confirmParams: {
                  return_url: window.location.origin + '/payment-success',
                },
                redirect: 'if_required'
              });
              
              if (error) {
                console.error('Payment error:', error);
              }
            });
          }
        })();
        ''']);
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to initialize Stripe: $e';
        _status = 'error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade300),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: Colors.red.shade900),
                ),
              ),
            if (_isInitializing)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_status == 'ready' && _containerId != null)
              SizedBox(
                height: 400,
                child: HtmlElementView(viewType: _containerId!),
              )
            else if (_status == 'succeeded')
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Icon(Icons.check_circle, color: Colors.green, size: 64),
                ),
              ),
            if (_status == 'ready' && _containerId != null)
              ElevatedButton(
                onPressed: _isProcessing ? null : () {
                  setState(() => _isProcessing = true);
                  js.context.callMethod('eval', ['''
                    if (window.stripeInstance && window.stripeElements) {
                      window.stripeInstance.confirmPayment({
                        elements: window.stripeElements,
                        confirmParams: {
                          return_url: window.location.origin + '/payment-success',
                        },
                        redirect: 'if_required'
                      }).then(function(result) {
                        if (result.error) {
                          console.error('Payment error:', result.error);
                        }
                      });
                    }
                  ''']);
                },
                child: _isProcessing
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Pay Now'),
              ),
          ],
        ),
      ),
    );
  }
}
