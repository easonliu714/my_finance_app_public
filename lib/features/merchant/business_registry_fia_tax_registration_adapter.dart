import 'business_registry_nationwide_source_authority.dart';

class BusinessRegistryNationwideInvoiceSellerSeed {
  const BusinessRegistryNationwideInvoiceSellerSeed({
    required this.sellerIdentifier,
    required this.legalName,
    required this.parentSellerIdentifier,
    required this.organizationType,
    required this.usesUniformInvoice,
    required this.sourceDataset,
  });

  final String sellerIdentifier;
  final String legalName;
  final String parentSellerIdentifier;
  final String organizationType;
  final String usesUniformInvoice;
  final String sourceDataset;

  bool get hasParent => parentSellerIdentifier.isNotEmpty;
}

/// Minimal, privacy-reduced projection from the Ministry of Finance / Fiscal
/// Information Agency nationwide active tax-registration CSV.
///
/// This adapter deliberately does not turn a tax-registration row directly
/// into a GCIS legal entity type. Company/business classification is resolved
/// later by the controlled enrichment stage; rows with a head-office identifier
/// do carry deterministic branch/outlet parent evidence.
class BusinessRegistryFiaTaxRegistrationAdapter {
  const BusinessRegistryFiaTaxRegistrationAdapter();

  static const String sourceDataset = 'MOF_FIA_BGMOPEN1_ACTIVE_TAX_REGISTRY';

  BusinessRegistryNationwideInvoiceSellerSeed parseRow(
    Map<String, String> row,
  ) {
    final seller = _digits(row['統一編號'] ?? '');
    final parent = _digits(row['總機構統一編號'] ?? '');
    final legalName = (row['營業人名稱'] ?? '').trim();
    final organizationType = (row['組織別名稱'] ?? '').trim();
    final usesUniformInvoice = (row['使用統一發票'] ?? '').trim();

    if (!RegExp(r'^\d{8}$').hasMatch(seller)) {
      throw const FormatException('FIA_TAX_REGISTRY_SELLER_IDENTIFIER_INVALID');
    }
    if (legalName.isEmpty) {
      throw const FormatException('FIA_TAX_REGISTRY_LEGAL_NAME_REQUIRED');
    }
    if (parent.isNotEmpty && !RegExp(r'^\d{8}$').hasMatch(parent)) {
      throw const FormatException('FIA_TAX_REGISTRY_PARENT_IDENTIFIER_INVALID');
    }
    if (parent == seller) {
      throw const FormatException('FIA_TAX_REGISTRY_PARENT_SELF_REFERENCE');
    }

    return BusinessRegistryNationwideInvoiceSellerSeed(
      sellerIdentifier: seller,
      legalName: legalName,
      parentSellerIdentifier: parent,
      organizationType: organizationType,
      usesUniformInvoice: usesUniformInvoice,
      sourceDataset: sourceDataset,
    );
  }

  List<String> validateHeader(Iterable<String> header) {
    final fields = header.map((value) => value.trim()).toSet();
    final errors = <String>[];
    for (final required in BusinessRegistryNationwideSourceAuthority
        .fiaActiveTaxRegistry.requiredSourceFields) {
      if (!fields.contains(required)) {
        errors.add('FIA_TAX_REGISTRY_REQUIRED_COLUMN_MISSING:$required');
      }
    }
    return List<String>.unmodifiable(errors);
  }

  static String _digits(String value) =>
      value.replaceAll(RegExp(r'[^0-9]'), '');
}
