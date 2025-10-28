import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'dart:math';

class Category {
  final int? id;
  final String name;

  Category({this.id, required this.name});

  Map<String, dynamic> toMap() => {'id': id, 'name': name};

  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(id: map['id'], name: map['name']);
  }
}

class Product {
  final int? id;
  final int categoryId;
  final String name;
  final double price;
  final int quantity;

  Product({
    this.id,
    required this.categoryId,
    required this.name,
    required this.price,
    required this.quantity,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'category_id': categoryId,
    'name': name,
    'price': price,
    'quantity': quantity,
  };

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'] as int?,
      categoryId: map['category_id'] as int,
      name: map['name'] as String,
      price: (map['price'] as num).toDouble(),
      quantity: map['quantity'] as int,
    );
  }
}

class SQLiteService {
  static Database? _db;

  static Future<Database> getDatabase() async {
    if (_db != null) return _db!;
    final path = p.join(await getDatabasesPath(), 'products.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE categories(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE products(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            category_id INTEGER,
            name TEXT,
            price REAL,
            quantity INTEGER,
            FOREIGN KEY(category_id) REFERENCES categories(id)
          )
        ''');
      },
    );
    return _db!;
  }

  /// Category
  static Future<int> insertCategory(Category c) async {
    final db = await getDatabase();
    return db.insert('categories', c.toMap());
  }

  static Future<List<Category>> getAllCategories() async {
    final db = await getDatabase();
    final maps = await db.query('categories');
    return maps.map((e) => Category.fromMap(e)).toList();
  }

  static Future<int> deleteCategory(int categoryId) async {
    final db = await getDatabase();
    await db.delete('products', where: 'category_id = ?', whereArgs: [categoryId]);
    return db.delete('categories', where: 'id = ?', whereArgs: [categoryId]);
  }

  /// Product
  static Future<int> insertProduct(Product p) async {
    final db = await getDatabase();
    return db.insert('products', p.toMap());
  }

  static Future<int> updateProduct(Product p) async {
    final db = await getDatabase();
    return db.update('products', p.toMap(), where: 'id = ?', whereArgs: [p.id]);
  }

  static Future<int> deleteProduct(int productId) async {
    final db = await getDatabase();
    return db.delete('products', where: 'id = ?', whereArgs: [productId]);
  }

  static Future<int> insertProductsBatch(List<Product> products) async {
    final db = await getDatabase();
    return await db.transaction((txn) async {
      int count = 0;
      for (var p in products) {
        count += await txn.insert('products', p.toMap());
      }
      return count;
    });
  }

  /// Truy vấn phức tạp: JOIN + filter
  static Future<List<Map<String, dynamic>>> getProductsWithCategory({String? search}) async {
    final db = await getDatabase();
    String query = '''
      SELECT p.id, p.name AS product_name, p.price, p.quantity, c.name AS category_name, p.category_id
      FROM products p
      JOIN categories c ON p.category_id = c.id
    ''';

    List<String> whereClauses = [];
    List<dynamic> args = [];

    if (search != null && search.isNotEmpty) {
      whereClauses.add('(p.name LIKE ? OR c.name LIKE ?)');
      args.add('%$search%');
      args.add('%$search%');
    }

    if (whereClauses.isNotEmpty) {
      query += ' WHERE ' + whereClauses.join(' AND ');
    }

    query += ' ORDER BY p.price DESC';

    return db.rawQuery(query, args);
  }

  /// Xoá dữ liệu test (category = 'TEST')
  static Future<int> deleteAllTestData() async {
    final db = await getDatabase();
    await db.delete('products',
        where: 'category_id IN (SELECT id FROM categories WHERE name = ?)', whereArgs: ['TEST']);
    return db.delete('categories', where: 'name = ?', whereArgs: ['TEST']);
  }
}
//UI
class SQLitePage extends StatefulWidget {
  const SQLitePage({super.key});

  @override
  State<SQLitePage> createState() => _SQLitePageState();
}

class _SQLitePageState extends State<SQLitePage> {
  final TextEditingController _searchController = TextEditingController();

  List<Category> categories = [];
  Category? selectedCategory;
  List<Map<String, dynamic>> products = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCategories();
    });
  }

  Future<void> _loadCategories() async {
    final cats = await SQLiteService.getAllCategories();
    setState(() {
      categories = cats;
      if (cats.isNotEmpty) selectedCategory ??= cats.first;
    });
    _loadProducts(search: _searchController.text);
  }

  Future<void> _loadProducts({String? search}) async {
    final list = await SQLiteService.getProductsWithCategory(search: search);
    setState(() {
      products = list;
    });
  }

  /// ----------------- Dialogs -----------------
  Future<void> _showAddCategoryDialog() async {
    final TextEditingController nameController = TextEditingController();
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Category'),
        content: TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Category Name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isEmpty) return;
              await SQLiteService.insertCategory(Category(name: nameController.text));
              Navigator.pop(context);
              _loadCategories();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddProductDialog([Map<String, dynamic>? existing]) async {
    Product? productObj;
    if (existing != null) {
      productObj = Product(
        id: existing['id'] as int?,
        categoryId: existing['category_id'] as int,
        name: existing['product_name'] as String,
        price: (existing['price'] as num).toDouble(),
        quantity: existing['quantity'] as int,
      );
    }

    final TextEditingController nameCtrl = TextEditingController(text: existing?['product_name'] ?? '');
    final TextEditingController priceCtrl = TextEditingController(
      text: existing != null
          ? ((existing['price'] as double) % 1 == 0
          ? (existing['price'] as double).toInt().toString()
          : (existing['price'] as double).toString())
          : '',
    );
    final TextEditingController qtyCtrl = TextEditingController(text: existing?['quantity']?.toString() ?? '');

    Category dialogSelectedCategory = (categories.isNotEmpty)
        ? (existing != null
        ? categories.firstWhere(
          (c) => c.id == existing['category_id'],
      orElse: () => categories.first,
    )
        : selectedCategory ?? categories.first)
        : Category(id: 0, name: 'Unknown');

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(existing == null ? 'Add Product' : 'Edit Product'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                if (categories.isNotEmpty)
                  DropdownButton<Category>(
                    value: dialogSelectedCategory,
                    items: categories
                        .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
                        .toList(),
                    onChanged: (v) => setStateDialog(() => dialogSelectedCategory = v!),
                  ),
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Product Name')),
                TextField(controller: priceCtrl, decoration: const InputDecoration(labelText: 'Price'), keyboardType: TextInputType.number),
                TextField(controller: qtyCtrl, decoration: const InputDecoration(labelText: 'Quantity'), keyboardType: TextInputType.number),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (dialogSelectedCategory.id == 0 || nameCtrl.text.isEmpty) return;
                final product = Product(
                  id: productObj?.id,
                  categoryId: dialogSelectedCategory.id!,
                  name: nameCtrl.text,
                  price: double.tryParse(priceCtrl.text) ?? 0,
                  quantity: int.tryParse(qtyCtrl.text) ?? 0,
                );
                if (productObj == null) {
                  await SQLiteService.insertProduct(product);
                } else {
                  await SQLiteService.updateProduct(product);
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

  Future<void> _deleteProduct(Map<String, dynamic> p) async {
    bool confirm = await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text('Delete ${p['product_name']}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm) {
      await SQLiteService.deleteProduct(p['id'] as int);
      _loadProducts(search: _searchController.text);
    }
  }

  Future<void> _deleteCategory(Category c) async {
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
      await SQLiteService.deleteCategory(c.id!);
      _loadCategories();
    }
  }

  Future<void> _performTest() async {
    final BuildContext ctx = context;
    final testCategoryId = await SQLiteService.insertCategory(Category(name: 'TEST'));
    final List<Product> testProducts = List.generate(1000, (i) {
      return Product(
        categoryId: testCategoryId,
        name: 'Product $i',
        price: Random().nextDouble() * 100,
        quantity: Random().nextInt(50),
      );
    });

    final sw1 = Stopwatch()..start();
    for (var p in testProducts) await SQLiteService.insertProduct(p);
    sw1.stop();

    await SQLiteService.deleteAllTestData();

    final sw2 = Stopwatch()..start();
    await SQLiteService.insertProductsBatch(testProducts);
    sw2.stop();

    await SQLiteService.deleteAllTestData();

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
      appBar: AppBar(title: const Text('SQLite Demo')),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            // Search trên cùng
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

            // Buttons Add Category / Add Product / Perform Test
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                ElevatedButton(onPressed: _showAddCategoryDialog, child: const Text('Add Category')),
                ElevatedButton(onPressed: () => _showAddProductDialog(), child: const Text('Add Product')),
                ElevatedButton(onPressed: _performTest, child: const Text('Perform Test')),
              ],
            ),
            const SizedBox(height: 8),

            // List
            Expanded(
              child: ListView.builder(
                itemCount: products.length,
                itemBuilder: (_, i) {
                  final p = products[i];
                  double price = p['price'] as double;
                  String priceStr = price % 1 == 0 ? price.toInt().toString() : price.toString();
                  return Card(
                    color: i % 2 == 0 ? Colors.teal[50] : Colors.white,
                    child: ListTile(
                      title: Text('${p['product_name']} (${p['category_name']})'),
                      subtitle: Text('Price: $priceStr - Qty: ${p['quantity']}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(icon: const Icon(Icons.edit, color: Colors.orange), onPressed: () => _showAddProductDialog(p)),
                          IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _deleteProduct(p)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // List Category để xoá
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
