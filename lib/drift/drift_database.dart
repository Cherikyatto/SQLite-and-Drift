import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'drift_database.g.dart';

class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
}

class Products extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get categoryId => integer().customConstraint('REFERENCES categories(id)')();
  TextColumn get name => text()();
  RealColumn get price => real()();
  IntColumn get quantity => integer()();
}

// Data model cho UI
class CategoryWithId {
  final int id;
  final String name;
  CategoryWithId({required this.id, required this.name});
}

class ProductWithCategory {
  final int id;
  final String name;
  final double price;
  final int quantity;
  final int categoryId;
  final String categoryName;
  ProductWithCategory({
    required this.id,
    required this.name,
    required this.price,
    required this.quantity,
    required this.categoryId,
    required this.categoryName,
  });
}

@DriftDatabase(tables: [Categories, Products])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;


  Future<int> insertCategory(CategoriesCompanion c) => into(categories).insert(c);

  Future<List<CategoryWithId>> getAllCategories() async {
    final list = await select(categories).get();
    return list.map((c) => CategoryWithId(id: c.id, name: c.name)).toList();
  }

  Future<int> deleteCategory(int id) async {
    await (delete(products)..where((p) => p.categoryId.equals(id))).go();
    return (delete(categories)..where((c) => c.id.equals(id))).go();
  }


  Future<int> insertProduct(ProductsCompanion p) => into(products).insert(p);

  Future<int> updateProduct(ProductsCompanion p) {
    final id = p.id.value;
    if (id == null) throw Exception('Product id cannot be null');

    return (update(products)..where((tbl) => tbl.id.equals(id)))
        .write(ProductsCompanion(
      name: p.name,
      price: p.price,
      quantity: p.quantity,
      categoryId: p.categoryId,
    ));
  }

  Future<int> deleteProduct(int id) => (delete(products)..where((p) => p.id.equals(id))).go();

  Future<int> insertProductsBatch(List<ProductsCompanion> list) async {
    return transaction(() async {
      int count = 0;
      for (var p in list) {
        count += await into(products).insert(p);
      }
      return count;
    });
  }

  Future<List<ProductWithCategory>> getProductsWithCategory({String? search}) async {
    final query = (select(products)
      ..orderBy([(p) => OrderingTerm(expression: p.price, mode: OrderingMode.desc)]))
        .join([innerJoin(categories, categories.id.equalsExp(products.categoryId))]);

    if (search != null && search.isNotEmpty) {
      query.where(products.name.like('%$search%') | categories.name.like('%$search%'));
    }

    final rows = await query.get();
    return rows.map((row) {
      final p = row.readTable(products);
      final c = row.readTable(categories);
      return ProductWithCategory(
        id: p.id,
        name: p.name,
        price: p.price,
        quantity: p.quantity,
        categoryId: c.id,
        categoryName: c.name,
      );
    }).toList();
  }


  Future<int> deleteAllTestData() async {
    final testCategories = await (select(categories)..where((c) => c.name.equals('TEST'))).get();
    for (var c in testCategories) {
      await deleteCategory(c.id);
    }
    return testCategories.length;
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'drift_demo.sqlite'));
    return NativeDatabase(file);
  });
}
