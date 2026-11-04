import 'product.dart';
import 'product_variant.dart';

class CartItem {
  final Product product;
  final ProductVariant variant;
  int quantity;

  CartItem({
    required this.product,
    required this.variant,
    this.quantity = 1,
  });

  double get unitPrice => product.precioEfectivo + variant.precioAdicional;
  double get totalPrice => unitPrice * quantity;
}
