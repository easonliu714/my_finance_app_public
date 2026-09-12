import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/merchant/business_registry_pack.dart';

void main() {
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

  test('official detail wire is fixed-order 16-value array and round-trips', () {
    const entity = BusinessRegistryEntity(
      sellerIdentifier: '31655572',
      entityType: BusinessRegistryEntityType.branch,
      legalName: '富達零售股份有限公司晶技門市',
      parentSellerIdentifier: '22853565',
      sourceDataset: 'MOF_FIA_BGMOPEN1_ACTIVE_TAX_REGISTRY',
      officialFields: fields,
    );

    final json = entity.toCanonicalJson();
    final wire = json['official_fields'];
    expect(wire, isA<List<String>>());
    final values = wire! as List<String>;
    expect(values, hasLength(16));
    expect(values[1], '31655572');
    expect(values[3], '富達零售股份有限公司晶技門市');

    final decoded = BusinessRegistryEntity.fromJson(json);
    expect(decoded.officialFields, fields);
    expect(decoded.officialFields['營業地址'], '新北市土城區測試路1號');
    expect(decoded.officialFields['行業代號'], '471112');
  });

  test('legacy named-object detail remains readable during transition', () {
    final decoded = decodeBusinessRegistryOfficialFields(fields);
    expect(decoded, fields);
  });

  test('wrong official detail array length fails closed', () {
    expect(
      () => decodeBusinessRegistryOfficialFields(const <String>['only-one']),
      throwsFormatException,
    );
  });
}
