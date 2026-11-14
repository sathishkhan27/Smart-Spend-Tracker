import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/engines/bank_templates.dart';
import '../domain/engines/categorization_engine.dart';

/// Workspace-level learned rules (`transaction_rules`):
/// * `type: merchant_category` – merchant → category mapping from user corrections
/// * `type: bank_template` – extra parsing templates (admin-managed)
class RulesRepository {
  RulesRepository(this._db);
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('transaction_rules');

  Future<Map<String, String>> merchantMappings(String workspaceId) async {
    final q = await _col.where('workspaceId', isEqualTo: workspaceId).where('type', isEqualTo: 'merchant_category').get();
    return {
      for (final d in q.docs)
        d['merchantKey'] as String: d['subcategory'] == null ? d['categoryId'] as String : '${d['categoryId']}/${d['subcategory']}',
    };
  }

  Future<List<BankTemplate>> bankTemplates(String workspaceId) async {
    try {
      final q = await _col.where('workspaceId', isEqualTo: workspaceId).where('type', isEqualTo: 'bank_template').get();
      return q.docs.map((d) => BankTemplate.fromJson(d.data())).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveMerchantMapping({
    required String workspaceId,
    required String merchant,
    required String categoryId,
    String? subcategory,
    required String userId,
  }) async {
    final key = CategorizationEngine.merchantKey(merchant);
    if (key.isEmpty) return;
    await _col.doc('${workspaceId}_mc_$key').set({
      'workspaceId': workspaceId,
      'type': 'merchant_category',
      'merchantKey': key,
      'merchantName': merchant,
      'categoryId': categoryId,
      'subcategory': subcategory,
      'updatedBy': userId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
