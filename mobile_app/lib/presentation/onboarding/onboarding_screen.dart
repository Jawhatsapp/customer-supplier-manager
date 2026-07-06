// lib/presentation/onboarding/onboarding_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart'; // استيراد مكتبة flutter_svg

import '../../providers/auth_provider.dart';
import '../auth/login_screen.dart';
import '../home/customer_home_screen.dart';
import '../home/retailer_home_screen.dart';
import '../home/supplier_home_screen.dart';

class OnboardingPageData {
  final String imagePath;
  final String title;
  final String description;

  OnboardingPageData({
    required this.imagePath,
    required this.title,
    required this.description,
  });
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({Key? key}) : super(key: key);

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPageIndex = 0;

  final List<OnboardingPageData> _pages = [
    OnboardingPageData(
      imagePath: 'assets/illustrations/onboarding1.svg',
      title: 'مرحبًا بك في منصتك المتكاملة!',
      description: 'تواصل بسهولة بين الموردين والتجار والعملاء لإدارة أعمالك بكفاءة.',
    ),
    OnboardingPageData(
      imagePath: 'assets/illustrations/onboarding2.svg',
      title: 'إدارة المنتجات والمخزون بسهولة',
      description: 'أضف منتجاتك، حدد الأسعار، وتتبع المخزون بدقة من مكان واحد.',
    ),
    OnboardingPageData(
      imagePath: 'assets/illustrations/onboarding3.svg',
      title: 'تتبع الطلبات والماليات بوضوح',
      description: 'تابع طلباتك، راجع حساباتك المالية، وقم بإدارة المرتجعات والمدفوعات بكل سهولة.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenOnboarding', true);

    if (!mounted) return;

    // إعادة التوجيه لمسار '/initial' لإعادة تقييم الحالة
    Navigator.pushReplacementNamed(context, '/initial');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLastPage = _currentPageIndex == _pages.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: AlignmentDirectional.topEnd,
              child: TextButton(
                onPressed: _completeOnboarding,
                child: const Text('تخطي'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (index) {
                  setState(() {
                    _currentPageIndex = index;
                  });
                },
                itemBuilder: (context, index) {
                  return _buildPageLayout(_pages[index], theme);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 25.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SmoothPageIndicator(
                    controller: _pageController,
                    count: _pages.length,
                    effect: WormEffect(
                      dotHeight: 10,
                      dotWidth: 10,
                      activeDotColor: theme.colorScheme.primary,
                      dotColor: Colors.grey.shade300,
                    ),
                    onDotClicked: (index) {
                      _pageController.animateToPage(
                        index,
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeInOut,
                      );
                    },
                  ),
                  ElevatedButton(
                    onPressed: () {
                      if (isLastPage) {
                        _completeOnboarding();
                      } else {
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeInOut,
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(15),
                      minimumSize: Size.zero,
                    ),
                    child: Icon(
                      isLastPage ? Icons.check : Icons.arrow_forward_ios,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageLayout(OnboardingPageData pageData, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            flex: 5,
            // استخدام SvgPicture.asset لعرض الصور بصيغة SVG
            child: SvgPicture.asset(
              pageData.imagePath,
              fit: BoxFit.contain,
              // في حالة حدوث خطأ يتم عرض أيقونة الخطأ
              placeholderBuilder: (context) => const Center(child: CircularProgressIndicator()),
            ),
          ),
          const Spacer(flex: 1),
          Expanded(
            flex: 3,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Text(
                  pageData.title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 15),
                Text(
                  pageData.description,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: Colors.grey[700],
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
