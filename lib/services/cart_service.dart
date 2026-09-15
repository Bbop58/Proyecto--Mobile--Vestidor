import 'package:flutter/material.dart';
import '../models/branch.dart';
import '../models/cart_item.dart';
import '../models/product.dart';
import '../models/product_variant.dart';

class CartService extends ChangeNotifier {
  final List<CartItem> _items = [];
  Branch? _selectedBranch;

  List<CartItem> get items => List.unmodifiable(_items);
  Branch? get selectedBranch => _selectedBranch;

  int get totalItemCount => _items.fold(0, (sum, item) => sum + item.quantity);

  double get subtotal => _items.fold(0.0, (sum, item) => sum + item.totalPrice);

  double get total => subtotal;

  bool get isEmpty => _items.isEmpty;

  void setSelectedBranch(Branch? branch) {
    _selectedBranch = branch;
    notifyListeners();
  }

  void addItem(Product product, ProductVariant variant, {int quantity = 1}) {
    final existingIndex = _items.indexWhere(
      (item) => item.variant.id == variant.id,
    );

    if (existingIndex >= 0) {
      _items[existingIndex].quantity += quantity;
    } else {
      _items.add(CartItem(
        product: product,
        variant: variant,
        quantity: quantity,
      ));
    }
    notifyListeners();
  }

  void updateQuantity(String variantId, int quantity) {
    final index = _items.indexWhere((item) => item.variant.id == variantId);
    if (index >= 0) {
      if (quantity <= 0) {
        _items.removeAt(index);
      } else {
        _items[index].quantity = quantity;
      }
      notifyListeners();
    }
  }

  void removeItem(String variantId) {
    _items.removeWhere((item) => item.variant.id == variantId);
    notifyListeners();
  }

  void clearCart() {
    _items.clear();
    _selectedBranch = null;
    notifyListeners();
  }
}
