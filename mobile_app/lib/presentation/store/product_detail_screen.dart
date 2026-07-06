// lib/presentation/store/product_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // <-- من مكتبة provider
import 'package:badges/badges.dart' as badges;
// إخفاء Provider من supabase
import 'package:supabase_flutter/supabase_flutter.dart' hide Provider;

import '../../../models/product.dart';
import '../cart/cart_provider.dart';
import '../cart/cart_screen.dart';

class ProductDetailScreen extends StatefulWidget {
  final Product product;
  final bool isOwner;
  final bool isClient; // Kept for potential future use, but cart logic is now unified

  const ProductDetailScreen({
    Key? key,
    required this.product,
    this.isOwner = false,
    this.isClient = false, // You might simplify this if role check handles it
  }) : super(key: key);

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  int _desiredQty = 1;

  // لإدارة زر المفضلة:
  bool _isFav = false;

  @override
  void initState() {
    super.initState();
    _checkIfFavorite();
    // Ensure desiredQty doesn't start higher than stock
    if (_desiredQty > widget.product.stock) {
      _desiredQty = widget.product.stock > 0 ? 1 : 0; // Set to 1 if stock exists, else 0
    }
  }

  Future<void> _checkIfFavorite() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || !mounted) return;
    try {
      final res = await Supabase.instance.client
          .from('favorites')
          .select('product_id')
          .eq('user_id', user.id)
          .eq('product_id', widget.product.id)
          .maybeSingle(); // Use maybeSingle for efficiency

      if (mounted && res != null) {
        setState(() => _isFav = true);
      }
    } catch (e) {
      print("Error checking favorite: $e");
      // Handle error silently or show a message if needed
    }
  }


  Future<void> _toggleFavorite() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || !mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى تسجيل الدخول أولاً للمفضلة')),
      );
      return;
    }

    // Optimistic UI update
    final originalFavStatus = _isFav;
    setState(() => _isFav = !originalFavStatus);

    try {
      if (!originalFavStatus) { // If it wasn't favorite before, add it
        await Supabase.instance.client.from('favorites').insert({
          'user_id': user.id,
          'product_id': widget.product.id,
        });
        if(mounted) _showSuccessMessage('تمت الإضافة إلى المفضلة');
      } else { // If it was favorite, delete it
        await Supabase.instance.client
            .from('favorites')
            .delete()
            .eq('user_id', user.id)
            .eq('product_id', widget.product.id);
        if(mounted) _showSuccessMessage('تمت الإزالة من المفضلة');
      }
    } catch (e) {
      print("Error toggling favorite: $e");
      // Rollback UI on error
      if (mounted) {
        setState(() => _isFav = originalFavStatus);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحديث المفضلة: $e')),
        );
      }
    }
  }

  // Helper for success messages
  void _showSuccessMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 1),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    // Use watch here to rebuild when cart changes (e.g., totalCount)
    final cartProvider = context.watch<CartProvider>();
    final theme = Theme.of(context); // Get theme
    final colorScheme = theme.colorScheme;

    // Determine if the add to cart button should be enabled
    final bool canAddToCart = !widget.isOwner && widget.product.stock > 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.product.productName, overflow: TextOverflow.ellipsis),
        actions: [
          // أيقونة السلة
          // Use Consumer only for the part that needs cart data if performance is critical
          // Otherwise, context.watch is fine here.
          badges.Badge(
            position: badges.BadgePosition.topEnd(top: 0, end: 3),
            showBadge: cartProvider.totalCount > 0,
            badgeContent: Text(
              cartProvider.totalCount.toString(),
              style: const TextStyle(color: Colors.white, fontSize: 10),
            ),
            badgeAnimation: const badges.BadgeAnimation.scale(
              animationDuration: Duration(milliseconds: 200),
            ),
            child: IconButton(
              icon: const Icon(Icons.shopping_cart_outlined), // Use outlined icon
              tooltip: 'عرض السلة', // Add tooltip
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CartScreen()),
                );
              },
            ),
          ),
          // زر المفضلة (لا يعرض للمالك)
          if (!widget.isOwner)
            IconButton(
              icon: Icon(
                  _isFav ? Icons.favorite : Icons.favorite_border,
                  color: _isFav ? Colors.redAccent : null // Highlight if favorite
              ),
              tooltip: _isFav ? 'إزالة من المفضلة' : 'إضافة للمفضلة',
              onPressed: _toggleFavorite,
            ),
          const SizedBox(width: 4), // Spacing
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Product Image ---
            SizedBox( // Use SizedBox to constrain the image height
              height: MediaQuery.of(context).size.height * 0.4, // Example: 40% of screen height
              width: double.infinity,
              child: ClipRRect( // Keep the rounding
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
                child: (widget.product.imageUrl != null && widget.product.imageUrl!.isNotEmpty)
                    ? Image.network(
                  widget.product.imageUrl!,
                  fit: BoxFit.cover, // Cover ensures the image fills the box
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const Center(child: CircularProgressIndicator());
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Container( // Improved placeholder
                      color: Colors.grey[200],
                      child: Icon(Icons.broken_image_outlined, size: 60, color: Colors.grey[400]),
                    );
                  },
                )
                    : Container( // Placeholder if no image URL
                  color: Colors.grey[200],
                  child: Icon(Icons.image_not_supported_outlined, size: 60, color: Colors.grey[400]),
                ),
              ),
            ),
            // --- Product Details ---
            Padding(
              padding: const EdgeInsets.all(20.0), // Increase padding
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.product.productName,
                    style: theme.textTheme.headlineSmall?.copyWith( // Use theme style
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${widget.product.price.toStringAsFixed(2)} ر.ي',
                    style: theme.textTheme.titleLarge?.copyWith( // Use theme style
                      color: colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.product.product_description,
                    style: theme.textTheme.bodyLarge?.copyWith( // Use theme style
                      height: 1.5, // Improve line spacing
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    // More informative stock text
                    widget.product.stock > 0
                        ? 'الكمية المتوفرة: ${widget.product.stock}'
                        : 'نفدت الكمية',
                    style: theme.textTheme.bodyMedium?.copyWith( // Use theme style
                      color: widget.product.stock > 0 ? Colors.grey[700] : Colors.red,
                      fontWeight: widget.product.stock <= 0 ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // --- Quantity Selector and Add to Cart Button (Only if not owner and in stock) ---
                  if (canAddToCart) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Decrease Quantity Button
                        OutlinedButton(
                          onPressed: () {
                            if (_desiredQty > 1) {
                              setState(() => _desiredQty--);
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            shape: const CircleBorder(),
                            padding: const EdgeInsets.all(10),
                            side: BorderSide(color: Colors.grey[400]!), // Softer border
                          ),
                          child: const Icon(Icons.remove, size: 20),
                        ),
                        // Quantity Display
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0), // Increased spacing
                          child: Text(
                            '$_desiredQty',
                            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        // Increase Quantity Button
                        OutlinedButton(
                          onPressed: () {
                            if (_desiredQty < widget.product.stock) {
                              setState(() => _desiredQty++);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('وصلت إلى أقصى كمية متوفرة'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            shape: const CircleBorder(),
                            padding: const EdgeInsets.all(10),
                            side: BorderSide(color: Colors.grey[400]!),
                          ),
                          child: const Icon(Icons.add, size: 20),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24), // Increased spacing
                    // Add to Cart Button
                    Center(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          // Disable button visually if quantity is 0 or exceeds stock (shouldn't happen with checks)
                          // backgroundColor: _desiredQty <= 0 || _desiredQty > widget.product.stock ? Colors.grey : null,
                        ),
                        // Disable button logically if needed
                        onPressed: (_desiredQty <= 0) ? null : () {
                          // *** --- Logic from previous answer --- ***
                          final String? errorMessage = cartProvider.addToCart(
                            widget.product,
                            desiredQty: _desiredQty,
                          );

                          if (errorMessage != null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(errorMessage),
                                backgroundColor: Theme.of(context).colorScheme.error,
                                duration: const Duration(seconds: 3),
                              ),
                            );
                          } else {
                            _showSuccessMessage('تمت الإضافة إلى السلة');
                            // Option: Reset quantity after adding
                            setState(() {
                              _desiredQty = (widget.product.stock > 0) ? 1 : 0;
                            });
                          }
                          // *** --- End Logic --- ***
                        },
                        icon: const Icon(Icons.add_shopping_cart_outlined), // Use outlined icon
                        label: const Text('إضافة إلى السلة'),
                      ),
                    ),
                  ]
                  // Show message if owner or out of stock
                  else if (widget.isOwner)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20.0),
                        child: Text('أنت مالك هذا المنتج.', style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[700])),
                      ),
                    )
                  else if (widget.product.stock <= 0)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20.0),
                          child: Text('هذا المنتج غير متوفر حالياً.', style: theme.textTheme.bodyMedium?.copyWith(color: Colors.red[700])),
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
}