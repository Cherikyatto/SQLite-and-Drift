// drift_page.dart
import 'package:flutter/material.dart';
import 'dart:math';
import 'drift_database.dart';
import 'package:drift/drift.dart' as drift;

class DriftPage extends StatefulWidget {
  const DriftPage({super.key});

  @override
  State<DriftPage> createState() => _DriftPageState();
}

class _DriftPageState extends State<DriftPage> {
  final TextEditingController _searchController = TextEditingController();
  final AppDatabase db = AppDatabase();

  List<CategoryWithId> categories = [];
  CategoryWithId? selectedCategory;
  List<ProductWithCategory> products = [];

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final cats = await db.getAllCategories();
    setState(() {
      categories = cats;
      if (cats.isNotEmpty) selectedCategory ??= cats.first;
    });
    _loadProducts(search: _searchController.text);
  }

  Future<void> _loadProducts({String? search}) async {
    final list = await db.getProductsWithCategory(search: search);
    setState(() {
      products = list;
    });
  }

  /// ----------------- DIALOGS -----------------
  Future<void> _showAddCategoryDialog() async {
    final TextEditingController nameController = TextEditingController();
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Category'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Category Name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isEmpty) return;
              await db.insertCategory(CategoriesCompanion(name: drift.Value(nameController.text)));
              Navigator.pop(context);
              _loadCategories();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddProductDialog([ProductWithCategory? existing]) async {
    final TextEditingController nameCtrl = TextEditingController(text: existing?.name ?? '');
    final TextEditingController priceCtrl = TextEditingController(
      text: existing != null
          ? (existing.price % 1 == 0 ? existing.price.toInt().toString() : existing.price.toString())
          : '',
    );
    final TextEditingController qtyCtrl = TextEditingController(
      text: existing != null ? existing.quantity.toString() : '',
    );

    // Null-safe selection for dropdown
    CategoryWithId dialogSelectedCategory = (categories.isNotEmpty)
        ? (existing != null
        ? categories.firstWhere(
          (c) => c.id == existing.categoryId,
      orElse: () => categories.first,
    )
        : selectedCategory ?? categories.first)
        : CategoryWithId(id: 0, name: 'Unknown'); // fallback dummy

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(existing == null ? 'Add Product' : 'Edit Product'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                if (categories.isNotEmpty)
                  DropdownButton<CategoryWithId>(
                    value: dialogSelectedCategory,
                    items: categories
                        .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
                        .toList(),
                    onChanged: (v) => setStateDialog(() => dialogSelectedCategory = v!),
                  ),
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Product Name')),
                TextField(
                  controller: priceCtrl,
                  decoration: const InputDecoration(labelText: 'Price'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: qtyCtrl,
                  decoration: const InputDecoration(labelText: 'Quantity'),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (dialogSelectedCategory.id == 0 || nameCtrl.text.isEmpty) return;

                final productCompanion = ProductsCompanion(
                  id: existing != null ? drift.Value(existing.id) : drift.Value.absent(),
                  categoryId: drift.Value(dialogSelectedCategory.id),
                  name: drift.Value(nameCtrl.text),
                  price: drift.Value(double.tryParse(priceCtrl.text) ?? 0),
                  quantity: drift.Value(int.tryParse(qtyCtrl.text) ?? 0),
                );

                if (existing == null) {
                  await db.insertProduct(productCompanion);
                } else {
                  await db.updateProduct(productCompanion);
                }

                Navigator.pop(context);
                _loadProducts(search: _searchController.text);
              },
              child: Text(existing == null ? 'Add' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteProduct(ProductWithCategory p) async {
    bool confirm = await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text('Delete ${p.name}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm) {
      await db.deleteProduct(p.id);
      _loadProducts(search: _searchController.text);
    }
  }

  Future<void> _deleteCategory(CategoryWithId c) async {
    bool confirm = await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text('Delete category ${c.name}? All products under it will also be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm) {
      await db.deleteCategory(c.id);
      _loadCategories();
    }
  }

  Future<void> _performTest() async {
    final BuildContext ctx = context;
    final testCategoryId = await db.insertCategory(CategoriesCompanion(name: drift.Value('TEST')));

    final List<ProductsCompanion> testProducts = List.generate(1000, (i) {
      return ProductsCompanion(
        categoryId: drift.Value(testCategoryId),
        name: drift.Value('Product $i'),
        price: drift.Value(Random().nextDouble() * 100),
        quantity: drift.Value(Random().nextInt(50)),
      );
    });

    final sw1 = Stopwatch()..start();
    for (var p in testProducts) await db.insertProduct(p);
    sw1.stop();

    await db.deleteAllTestData();

    final sw2 = Stopwatch()..start();
    await db.insertProductsBatch(testProducts);
    sw2.stop();

    await db.deleteAllTestData();

    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Performing Test'),
        content: Text('Ghi từng bản: ${sw1.elapsedMilliseconds} ms\nGhi 1000 bản 1 lúc: ${sw2.elapsedMilliseconds} ms'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  /// ----------------- UI -----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Drift Demo')),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            // Search
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search products or categories...',
                prefixIcon: const Icon(Icons.search, color: Colors.teal),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear, color: Colors.red),
                  onPressed: () {
                    _searchController.clear();
                    _loadProducts();
                  },
                ),
                filled: true,
                fillColor: Colors.teal[50],
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) => _loadProducts(search: value),
            ),
            const SizedBox(height: 8),

            // Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                ElevatedButton(onPressed: _showAddCategoryDialog, child: const Text('Add Category')),
                ElevatedButton(onPressed: () => _showAddProductDialog(), child: const Text('Add Product')),
                ElevatedButton(onPressed: _performTest, child: const Text('Perform Test')),
              ],
            ),
            const SizedBox(height: 8),

            // List products
            Expanded(
              child: ListView.builder(
                itemCount: products.length,
                itemBuilder: (_, i) {
                  final p = products[i];
                  return Card(
                    color: i % 2 == 0 ? Colors.teal[50] : Colors.white,
                    child: ListTile(
                      title: Text('${p.name} (${p.categoryName})'),
                      subtitle: Text('Price: ${p.price % 1 == 0 ? p.price.toInt() : p.price} - Qty: ${p.quantity}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                              icon: const Icon(Icons.edit, color: Colors.orange),
                              onPressed: () => _showAddProductDialog(p)),
                          IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteProduct(p)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // List categories
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: categories
                  .map((c) => ActionChip(
                label: Text(c.name),
                onPressed: () => _deleteCategory(c),
                avatar: const Icon(Icons.delete, size: 18, color: Colors.red),
                backgroundColor: Colors.teal[100],
              ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}
