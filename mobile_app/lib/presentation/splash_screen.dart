// lib/presentation/splash_screen.dart
import 'package:flutter/material.dart';

class SplashScreen extends StatelessWidget {
  final String message; // <-- إضافة المتغير

  // تعديل الكونستركتور ليقبل message (اجعله اختياريًا بقيمة افتراضية)
  const SplashScreen({
    Key? key,
    this.message = "جاري التحميل..." // <-- قيمة افتراضية
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator( // استخدام لون الثيم الأساسي
              valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: 20), // زيادة المسافة
            // استخدام المتغير message هنا
            Text(
              message,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey[700]), // استخدام نمط أوضح
            ),
          ],
        ),
      ),
    );
  }
}