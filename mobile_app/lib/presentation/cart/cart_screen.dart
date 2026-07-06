import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/product.dart';
import 'cart_provider.dart';
import 'checkout_screen.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final cartProvider = Provider.of<CartProvider>(context);
    final itemsMap = cartProvider.items;
    final theme = Theme.of(context); // Use theme object
    final colorScheme =
        theme.colorScheme; // Keep for convenience if needed often

    return Scaffold(
      appBar: AppBar(
        // Uses theme styles
        title: const Text('🛒 سلة التسوق'),
        // backgroundColor is handled by theme
        actions: [
          if (itemsMap.isNotEmpty)
            IconButton(
              // Icon uses theme color
              icon: const Icon(
                  Icons.delete_sweep_outlined), // Changed icon slightly
              tooltip: 'تفريغ السلة', // Add tooltip
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    // Use themed text styles
                    title:
                        Text('تأكيد الحذف', style: theme.textTheme.titleLarge),
                    content: Text('هل تريد تفريغ السلة بالكامل؟',
                        style: theme.textTheme.bodyMedium),
                    actions: [
                      TextButton(
                        // Uses theme style
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('إلغاء'),
                      ),
                      TextButton(
                        // Uses theme style
                        onPressed: () {
                          cartProvider.clearCart();
                          Navigator.pop(ctx);
                        },
                        child: Text('نعم، تفريغ',
                            style: TextStyle(
                                color: theme.colorScheme
                                    .error)), // Error color for confirmation
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
      body: itemsMap.isEmpty
          ? Center(
              // Use themed text style for empty state
              child: Column(
                // Optional: Add an icon
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.remove_shopping_cart_outlined,
                      size: 60,
                      color:
                          theme.colorScheme.onSurfaceVariant.withOpacity(0.6)),
                  const SizedBox(height: 16),
                  Text(
                    'السلة فارغة حالياً',
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(
                  vertical: 8.0, horizontal: 4.0), // Consistent padding
              itemCount: itemsMap.length,
              itemBuilder: (context, index) {
                final product = itemsMap.keys.elementAt(index);
                final qty = itemsMap[product]!;

                // Use themed Card
                return Card(
                  // shape, elevation, margin handled by theme
                  child: Padding(
                    padding:
                        const EdgeInsets.all(12.0), // Keep padding inside card
                    child: Row(
                      crossAxisAlignment:
                          CrossAxisAlignment.center, // Center items vertically
                      children: [
                        // Product Image
                        ClipRRect(
                          borderRadius:
                              BorderRadius.circular(8), // Use theme radius?
                          child: product.imageUrl != null
                              ? Image.network(
                                  product.imageUrl!,
                                  width: 70, // Slightly smaller image
                                  height: 70,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    // Themed placeholder
                                    return Container(
                                      width: 70,
                                      height: 70,
                                      color: theme.colorScheme.surfaceVariant,
                                      child: Icon(
                                        Icons.broken_image_outlined,
                                        size: 30,
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    );
                                  },
                                )
                              : Container(
                                  // Themed placeholder
                                  width: 70,
                                  height: 70,
                                  color: theme.colorScheme.surfaceVariant,
                                  child: Icon(
                                      Icons.image_not_supported_outlined,
                                      size: 30,
                                      color:
                                          theme.colorScheme.onSurfaceVariant),
                                ),
                        ),
                        const SizedBox(width: 16), // Increased spacing
                        // Product Details
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                // Use theme style
                                product.productName,
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                // Use theme style
                                '${product.price.toStringAsFixed(2)} ر.ي', // Show unit price
                                style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.primary),
                              ),
                              const SizedBox(height: 8),
                              // Quantity Controls Row
                              Row(
                                mainAxisAlignment: MainAxisAlignment
                                    .spaceBetween, // Space out controls
                                children: [
                                  // Quantity Adjuster
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(Icons.remove_circle_outline,
                                            color: theme.colorScheme.secondary),
                                        padding:
                                            EdgeInsets.zero, // Remove padding
                                        constraints:
                                            const BoxConstraints(), // Remove constraints
                                        onPressed: () {
                                          cartProvider
                                              .decreaseQuantity(product);
                                        },
                                      ),
                                      Padding(
                                        // Add padding around quantity text
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8.0),
                                        child: Text('$qty',
                                            style: theme.textTheme.titleMedium),
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.add_circle_outline,
                                            color: theme.colorScheme.secondary),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        onPressed: () {
                                          final success = cartProvider
                                              .increaseQuantity(product);
                                          if (!success && context.mounted) {
                                            // Check mounted
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                    'لا يمكن تجاوز الكمية المتوفرة في المخزون'),
                                                duration: Duration(seconds: 2),
                                              ),
                                            );
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                  // Remove Button
                                  IconButton(
                                    onPressed: () {
                                      cartProvider.removeFromCart(product);
                                    },
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    icon: Icon(Icons.delete_outline,
                                        color: theme.colorScheme.error),
                                    tooltip: 'إزالة من السلة',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      bottomNavigationBar: itemsMap.isEmpty
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              // Use Material for elevation and theme color
              child: Material(
                elevation: 8.0, // Standard elevation
                color: theme.bottomAppBarTheme.color ??
                    theme.colorScheme.surface, // Use theme color
                child: Padding(
                  // Add padding inside Material
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Total Price Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            // Use theme style
                            'الإجمالي:',
                            style: theme.textTheme.titleLarge,
                          ),
                          Text(
                            // Use theme style
                            '${cartProvider.totalPrice.toStringAsFixed(2)} ر.ي',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme
                                  .primary, // Use primary color for total
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16), // Increased spacing
                      // Checkout Button
                      ElevatedButton.icon(
                        // Uses theme style
                        onPressed: () {
                          // Ensure cart is not empty before proceeding
                          if (itemsMap.isEmpty) return;
                          // Get storeId safely
                          final firstProduct = itemsMap.keys.first;
                          final storeId = firstProduct.storeId;

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CheckoutScreen(storeId: storeId),
                            ),
                          );
                        },
                        icon:
                            const Icon(Icons.payment_outlined), // Changed icon
                        label: const Text('الانتقال للدفع'),
                        // Style is inherited from theme
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
