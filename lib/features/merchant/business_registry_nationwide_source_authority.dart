enum BusinessRegistryNationwideSourceRole {
  invoiceSellerCoverageSpine,
  gcisCompanyEnrichment,
  gcisBusinessEnrichment,
  gcisBranchEnrichment,
}

class BusinessRegistryNationwideOfficialSource {
  const BusinessRegistryNationwideOfficialSource({
    required this.role,
    required this.datasetName,
    required this.provider,
    required this.catalogUri,
    required this.acquisitionUri,
    required this.bulkAcquisition,
    required this.updateCadence,
    required this.requiredSourceFields,
    required this.mobileProjectionFields,
  });

  final BusinessRegistryNationwideSourceRole role;
  final String datasetName;
  final String provider;
  final Uri catalogUri;
  final Uri acquisitionUri;
  final bool bulkAcquisition;
  final String updateCadence;
  final Set<String> requiredSourceFields;
  final Set<String> mobileProjectionFields;

  static const Set<String> prohibitedMobileFields = <String>{
    'Responsible_Name',
    'Branch_Office_Manager_Name',
    '負責人姓名',
    '分公司經理姓名',
  };

  List<String> validate() {
    final errors = <String>[];
    if (datasetName.trim().isEmpty) {
      errors.add('NATIONWIDE_SOURCE_DATASET_NAME_REQUIRED');
    }
    if (provider.trim().isEmpty) {
      errors.add('NATIONWIDE_SOURCE_PROVIDER_REQUIRED');
    }
    if (catalogUri.scheme != 'https' ||
        !const <String>{'data.gov.tw', 'data.gcis.nat.gov.tw'}
            .contains(catalogUri.host)) {
      errors.add('NATIONWIDE_SOURCE_CATALOG_NOT_OFFICIAL');
    }
    if (acquisitionUri.scheme != 'https' ||
        !const <String>{'eip.fia.gov.tw', 'data.gcis.nat.gov.tw'}
            .contains(acquisitionUri.host)) {
      errors.add('NATIONWIDE_SOURCE_ACQUISITION_NOT_OFFICIAL');
    }
    if (requiredSourceFields.isEmpty) {
      errors.add('NATIONWIDE_SOURCE_REQUIRED_FIELDS_EMPTY');
    }
    if (mobileProjectionFields.isEmpty) {
      errors.add('NATIONWIDE_SOURCE_MOBILE_PROJECTION_EMPTY');
    }
    if (mobileProjectionFields.any(prohibitedMobileFields.contains)) {
      errors.add('NATIONWIDE_SOURCE_SENSITIVE_FIELD_PROJECTED');
    }
    return List<String>.unmodifiable(errors);
  }
}

/// P4.20.3 source authority for the nationwide registry product.
///
/// The Ministry of Finance/Fiscal Information Agency nationwide active tax
/// registration archive is the coverage spine because it is a replayable bulk
/// artifact keyed by the same seller identifier that appears on invoices.
/// GCIS remains the legal-registration authority used by the controlled build
/// side to enrich company/business/branch type and parent-child identity.
/// None of these endpoints are called per invoice by the handset.
class BusinessRegistryNationwideSourceAuthority {
  const BusinessRegistryNationwideSourceAuthority._();

  static const String compositePackAuthority =
      'TW_GOV_MOF_FIA_MOEA_GCIS_OFFICIAL_REGISTRY';

  static final Uri licenseUri = Uri.parse('https://data.gov.tw/license');

  static final BusinessRegistryNationwideOfficialSource fiaActiveTaxRegistry =
      BusinessRegistryNationwideOfficialSource(
    role: BusinessRegistryNationwideSourceRole.invoiceSellerCoverageSpine,
    datasetName: '全國營業(稅籍)登記資料集',
    provider: '財政部財政資訊中心',
    catalogUri: Uri.parse('https://data.gov.tw/dataset/9400'),
    acquisitionUri: Uri.parse('https://eip.fia.gov.tw/data/BGMOPEN1.zip'),
    bulkAcquisition: true,
    updateCadence: 'daily',
    requiredSourceFields: const <String>{
      '統一編號',
      '總機構統一編號',
      '營業人名稱',
      '組織別名稱',
      '使用統一發票',
    },
    mobileProjectionFields: const <String>{
      'seller_identifier',
      'legal_name',
      'parent_seller_identifier',
      'registration_status',
      'source_dataset',
    },
  );

  static final BusinessRegistryNationwideOfficialSource gcisCompany =
      BusinessRegistryNationwideOfficialSource(
    role: BusinessRegistryNationwideSourceRole.gcisCompanyEnrichment,
    datasetName: '公司登記基本資料-應用一',
    provider: '經濟部商業發展署',
    catalogUri: Uri.parse(
      'https://data.gcis.nat.gov.tw/od/detail?oid=8776818F-EB3C-445F-BE95-AE22577CBEBC',
    ),
    acquisitionUri: Uri.parse(
      'https://data.gcis.nat.gov.tw/od/data/api/5F64D864-61CB-4D0D-8AD9-492047CC1EA6',
    ),
    bulkAcquisition: false,
    updateCadence: 'unspecified',
    requiredSourceFields: const <String>{
      'Business_Accounting_NO',
      'Company_Name',
      'Company_Status_Desc',
    },
    mobileProjectionFields: const <String>{
      'seller_identifier',
      'entity_type',
      'legal_name',
      'registration_status',
      'source_dataset',
    },
  );

  static final BusinessRegistryNationwideOfficialSource gcisBusiness =
      BusinessRegistryNationwideOfficialSource(
    role: BusinessRegistryNationwideSourceRole.gcisBusinessEnrichment,
    datasetName: '商業登記基本資料-應用一',
    provider: '經濟部商業發展署',
    catalogUri: Uri.parse(
      'https://data.gcis.nat.gov.tw/od/detail?oid=714461A2-506A-4F7F-A40B-DB0247C71A1B',
    ),
    acquisitionUri: Uri.parse(
      'https://data.gcis.nat.gov.tw/od/data/api/7E6AFA72-AD6A-46D3-8681-ED77951D912D',
    ),
    bulkAcquisition: false,
    updateCadence: 'unspecified',
    requiredSourceFields: const <String>{
      'President_No',
      'Business_Name',
      'Business_Current_Status_Desc',
    },
    mobileProjectionFields: const <String>{
      'seller_identifier',
      'entity_type',
      'legal_name',
      'registration_status',
      'source_dataset',
    },
  );

  static final BusinessRegistryNationwideOfficialSource gcisBranch =
      BusinessRegistryNationwideOfficialSource(
    role: BusinessRegistryNationwideSourceRole.gcisBranchEnrichment,
    datasetName: '統編查分公司資料',
    provider: '經濟部商業發展署',
    catalogUri: Uri.parse(
      'https://data.gcis.nat.gov.tw/od/detail?oid=3F69570B-8936-40C1-9AAD-8526C5ADE237',
    ),
    acquisitionUri: Uri.parse(
      'https://data.gcis.nat.gov.tw/od/data/api/FDB8D2C8-573D-4276-BFA4-8D3925ABE1CB',
    ),
    bulkAcquisition: false,
    updateCadence: 'unspecified',
    requiredSourceFields: const <String>{
      'Business_Accounting_NO',
      'Branch_Office_Business_Accounting_NO',
      'Branch_Office_Name',
    },
    mobileProjectionFields: const <String>{
      'seller_identifier',
      'entity_type',
      'legal_name',
      'parent_seller_identifier',
      'registration_status',
      'source_dataset',
    },
  );

  static List<BusinessRegistryNationwideOfficialSource> get sources =>
      <BusinessRegistryNationwideOfficialSource>[
        fiaActiveTaxRegistry,
        gcisCompany,
        gcisBusiness,
        gcisBranch,
      ];

  static List<String> validate() {
    final errors = <String>[];
    final coverageSpines = sources
        .where(
          (source) =>
              source.role ==
              BusinessRegistryNationwideSourceRole.invoiceSellerCoverageSpine,
        )
        .toList(growable: false);
    if (coverageSpines.length != 1 || !coverageSpines.single.bulkAcquisition) {
      errors.add('NATIONWIDE_COVERAGE_SPINE_MUST_BE_SINGLE_BULK_SOURCE');
    }
    if (fiaActiveTaxRegistry.acquisitionUri.toString() !=
        'https://eip.fia.gov.tw/data/BGMOPEN1.zip') {
      errors.add('NATIONWIDE_FIA_BULK_URI_DRIFT');
    }
    for (final source in sources) {
      errors.addAll(source.validate());
      if (source.role !=
              BusinessRegistryNationwideSourceRole.invoiceSellerCoverageSpine &&
          source.bulkAcquisition) {
        errors.add('NATIONWIDE_GCIS_ENRICHMENT_MUST_NOT_CLAIM_BULK');
      }
    }
    return List<String>.unmodifiable(errors.toSet());
  }
}
