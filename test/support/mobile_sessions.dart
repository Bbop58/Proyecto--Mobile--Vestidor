import 'dart:convert';

import 'package:mobile/models/mobile_session.dart';
import 'package:mobile/services/storage_service.dart';

const sessionA = '30000000-0000-4000-8000-000000000001';
const sessionB = '30000000-0000-4000-8000-000000000002';
const userA = '10000000-0000-4000-8000-000000000001';
const userB = '10000000-0000-4000-8000-000000000002';
const companyA = '20000000-0000-4000-8000-000000000001';
const companyB = '20000000-0000-4000-8000-000000000002';
String credential(String sid) =>
    'ms_${sid.replaceAll('-', '')}.${List.filled(43, 'x').join()}';
String access({
  String sid = sessionA,
  String user = userA,
  String company = companyA,
  int? expiry,
  String signature = 'synthetic',
}) {
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${encode({'alg': 'none'})}.${encode({'sub': user, 'tenant_id': company, 'mobile_session_id': sid, 'type': 'access', 'exp': expiry ?? DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.$signature';
}

Map<String, dynamic> response({
  String sid = sessionA,
  String user = userA,
  String company = companyA,
  int? expiry,
  String signature = 'synthetic',
}) => {
  'session_id': sid,
  'session_token': credential(sid),
  'access_token': access(
    sid: sid,
    user: user,
    company: company,
    expiry: expiry,
    signature: signature,
  ),
  'user': {
    'id': user,
    'tenant_id': company,
    'email': 'qa@example.com',
    'full_name': 'QA',
    'access_scope': 'COMPANY',
    'is_active': true,
    'is_verified': true,
    'is_platform_admin': false,
    'subscription_capabilities': {'offline': true},
  },
};
MobileSessionRecord record({
  String sid = sessionA,
  String user = userA,
  String company = companyA,
  int? expiry,
}) => MobileSessionRecord.fromJson(
  response(sid: sid, user: user, company: company, expiry: expiry),
);

class MemorySessionStorage extends StorageService {
  SessionEnvelope? saved;
  Map<String, String>? legacy;
  bool failWrites = false;
  bool failReads = false;
  int writes = 0;
  Future<void>? delayWrite;
  @override
  Future<SessionEnvelope?> readSessionEnvelope() async {
    if (failReads) throw const SessionStorageException();
    return saved;
  }

  @override
  Future<void> writeSessionEnvelope(SessionEnvelope value) async {
    if (delayWrite != null) await delayWrite;
    if (failWrites) throw const SessionStorageException();
    writes++;
    saved = SessionEnvelope.fromJson(
      Map<String, dynamic>.from(jsonDecode(jsonEncode(value.toJson())) as Map),
    );
  }

  @override
  Future<Map<String, String>?> readLegacySession() async => legacy;
  @override
  Future<void> clearLegacySession() async {
    legacy = null;
  }
}
