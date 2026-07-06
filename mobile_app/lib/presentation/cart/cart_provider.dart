// lib/presentation/cart/cart_provider.dart

import 'package:flutter/material.dart';
import '../../models/product.dart'; // تأكد من المسار الصحيح

class CartProvider extends ChangeNotifier {
  /// product -> quantity
  final Map<Product, int> _items = {};
  int? _currentCartStoreId; // <-- المتغير الجديد لتتبع متجر السلة

  // --- Getters ---
  Map<Product, int> get items => Map.unmodifiable(_items); // إرجاع نسخة غير قابلة للتعديل
  int? get currentCartStoreId => _currentCartStoreId; // Getter للمتجر الحالي

  /// إجمالي السعر
  double get totalPrice {
    double total = 0.0;
    _items.forEach((product, quantity) {
      total += product.price * quantity;
    });
    return total;
  }

  /// إجمالي عدد العناصر (لو أردت عرضه)
  int get totalCount {
    int count = 0;
    _items.forEach((_, quantity) {
      count += quantity;
    });
    return count;
  }

  /// إضافة منتج إلى السلة
  /// [desiredQty] هي الكمية المطلوبة (افتراضيًا 1)
  /// Returns: `null` on success, or an error message `String` on failure.
  String? addToCart(Product product, {int desiredQty = 1}) {
    // 0. التحقق من الكمية المدخلة
    if (desiredQty <= 0) {
      return "لا يمكن إضافة كمية صفر أو أقل.";
    }
    // التحقق من المخزون مقارنة بالكمية *المطلوبة* فقط
    if (desiredQty > product.stock) {
      print('Add to cart failed: Desired quantity ($desiredQty) exceeds stock (${product.stock}) for ${product.productName}');
      return 'الكمية المطلوبة (${desiredQty}) تتجاوز المخزون المتوفر (${product.stock}).';
    }

    // 1. التحقق من توافق المتجر
    if (_items.isNotEmpty && product.storeId != _currentCartStoreId) {
      print('Add to cart failed: Cannot add item from store ${product.storeId} to a cart for store $_currentCartStoreId.');
      // **رسالة الخطأ للمستخدم**
      return "لا يمكنك إضافة منتجات من متاجر مختلفة في نفس السلة. يرجى إتمام الشراء الحالي أولاً أو إفراغ السلة.";
    }

    // 2. إذا كانت السلة فارغة، حدد متجر السلة الحالية
    if (_items.isEmpty) {
      _currentCartStoreId = product.storeId;
      print('Cart store set to: $_currentCartStoreId');
    }

    // 3. إضافة المنتج أو تحديث الكمية (مع التحقق مرة أخرى من المخزون الإجمالي في السلة)
    if (_items.containsKey(product)) {
      final newQty = _items[product]! + desiredQty;
      if (newQty > product.stock) {
        print('Add to cart failed: New total quantity ($newQty) would exceed stock (${product.stock}) for ${product.productName}');
        // هنا نعرض خطأ مختلف، الكمية *الإجمالية* في السلة ستتجاوز المخزون
        return 'إضافة هذه الكمية (${desiredQty}) ستجعل الإجمالي في السلة (${newQty}) يتجاوز المخزون المتوفر (${product.stock}).';
      }
      _items[product] = newQty;
    } else {
      // التحقق الأولي من desiredQty كافٍ هنا
      _items[product] = desiredQty;
    }

    notifyListeners();
    print('Product ${product.productName} (Qty: ${_items[product]}) added/updated successfully for store $_currentCartStoreId.');
    return null; // <-- إرجاع null يعني النجاح
  }

  /// زيادة الكمية لمنتج معيّن بواحد
  /// Returns: `true` on success, `false` if quantity exceeds stock.
  bool increaseQuantity(Product product) {
    if (!_items.containsKey(product)) return false; // المنتج غير موجود أصلاً
    final currentQty = _items[product]!;
    final newQty = currentQty + 1;
    if (newQty > product.stock) {
      print('Increase quantity failed: New quantity ($newQty) exceeds stock (${product.stock}) for ${product.productName}');
      return false; // أكبر من المتوفر
    }
    _items[product] = newQty;
    notifyListeners();
    return true;
  }

  /// إنقاص الكمية بمقدار 1
  /// Returns: `true` always (removes item if quantity reaches 0).
  bool decreaseQuantity(Product product) {
    if (!_items.containsKey(product)) return false; // المنتج غير موجود
    final currentQty = _items[product]!;
    if (currentQty <= 1) {
      // إذا وصلت الكمية إلى 0، نزيل المنتج
      _items.remove(product);
      // إذا كانت السلة فارغة بعد الإزالة، نعيد تعيين المتجر
      if (_items.isEmpty) {
        _currentCartStoreId = null;
        print('Cart is now empty, store ID reset.');
      }
    } else {
      _items[product] = currentQty - 1;
    }
    notifyListeners();
    return true;
  }

  /// إزالة المنتج بالكامل من السلة
  void removeFromCart(Product product) {
    _items.remove(product);
    // إذا كانت السلة فارغة بعد الإزالة، نعيد تعيين المتجر
    if (_items.isEmpty) {
      _currentCartStoreId = null;
      print('Cart is now empty, store ID reset.');
    }
    notifyListeners();
  }

  /// تفريغ السلة
  void clearCart() {
    _items.clear();
    _currentCartStoreId = null; // <-- إعادة تعيين متجر السلة عند تفريغها
    notifyListeners();
    print('Cart cleared and store ID reset.');
  }

  /// فحص هل المنتج موجود في السلة
  bool isInCart(Product product) => _items.containsKey(product);

  /// الحصول على الكمية الحالية لمنتج
  int getQuantity(Product product) => _items[product] ?? 0;
}