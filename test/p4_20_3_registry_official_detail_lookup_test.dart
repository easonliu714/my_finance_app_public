import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/database/production_schema_v24.dart';
import 'package:my_finance_app/features/merchant/business_registry_pack.dart';
import 'package:my_finance_app/features/merchant/business_registry_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('V24 keeps complete FIA row in replaceable registry-only detail cache',
      () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    addTearDown(db.close);
    await createCanonicalProductionV24Tables(db);

    const fields = <String, String>{
      '營業地址': '新北市土城區測試路1號',
      '統一編號': '31655572',
      '總機構統一編號': '22853565',
      '營業人名稱': '富達零售股份有限公司晶技門市',
      '資本額': '1000000',
      '設立日期': '20200101',
      '組織別名稱': '其他',
      '使用統一發票': 'Y',
      '行業代號': '471112',
      '名稱': '直營連鎖式便利商店',
      '行業代號1': '',
      '名稱1': '',
      '行業代號2': '',
      '名稱2': '',
      '行業代號3': '',
      '名稱3': '',
    };
    const entity = BusinessRegistryEntity(
      sellerIdentifier: '31655572',
      entityType: BusinessRegistryEntityType.branch,
      legalName: '富達零售股份有限公司晶技門市',
      registrationStatus: 'active_tax_registration',
      parentSellerIdentifier: '22853565',
      sourceDataset: 'MOF_FIA_BGMOPEN1_ACTIVE_TAX_REGISTRY',
      officialFields: fields,
    );
    final pack = BusinessRegistryPack(
      version: 'fia-detail-v1',
      sourceAuthority: 'MOF_FIA_ACTIVE_TAX_REGISTRY',
      sourceDataset: 'MOF_FIA_BGMOPEN1_ACTIVE_TAX_REGISTRY',
      sourceDataDate: '2026-09-08',
      coverage: BusinessRegistryPack.nationwideCoverage,
      contentSha256: await computeBusinessRegistryPayloadSha256(
        const <BusinessRegistryEntity>[entity],
      ),
      entities: const <BusinessRegistryEntity>[entity],
    );

    final repository = BusinessRegistryRepository(database: db);
    expect((await repository.install(pack)).isSuccess, isTrue);

    final core = await repository.lookup('31655572');
    expect(core.primaryEntity?.legalName, '富達零售股份有限公司晶技門市');
    expect(core.primaryEntity?.officialFields, isEmpty);

    final detail = await repository.lookupOfficialDetail('31655572');
    expect(detail.status, BusinessRegistryOfficialDetailLookupStatus.hit);
    expect(detail.fields.length, BusinessRegistryEntity.officialFieldOrder.length);
    expect(detail.fields['統一編號'], '31655572');
    expect(detail.fields['營業人名稱'], '富達零售股份有限公司晶技門市');
    expect(detail.fields['營業地址'], '新北市土城區測試路1號');
    expect(detail.fields['組織別名稱'], '其他');
    expect(detail.fields['使用統一發票'], 'Y');
  });

  test('core-only snapshot reports detailUnavailable rather than seller miss',
      () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    addTearDown(db.close);
    await createCanonicalProductionV24Tables(db);

    const entity = BusinessRegistryEntity(
      sellerIdentifier: '60282181',
      entityType: BusinessRegistryEntityType.branch,
      legalName: '本米股份有限公司土城中央路營業所',
      parentSellerIdentifier: '60769775',
      sourceDataset: 'MOF_FIA_BGMOPEN1_ACTIVE_TAX_REGISTRY',
    );
    final pack = BusinessRegistryPack(
      version: 'core-only',
      sourceAuthority: 'MOF_FIA_ACTIVE_TAX_REGISTRY',
      sourceDataset: 'MOF_FIA_BGMOPEN1_ACTIVE_TAX_REGISTRY',
      sourceDataDate: '2026-09-08',
      coverage: BusinessRegistryPack.nationwideCoverage,
      contentSha256: await computeBusinessRegistryPayloadSha256(
        const <BusinessRegistryEntity>[entity],
      ),
      entities: const <BusinessRegistryEntity>[entity],
    );
    final repository = BusinessRegistryRepository(database: db);
    await repository.install(pack);

    final detail = await repository.lookupOfficialDetail('60282181');
    expect(
      detail.status,
      BusinessRegistryOfficialDetailLookupStatus.detailUnavailable,
    );
  });
}
