import 'dart:convert';

const String approvedCloudInvoiceQueryOrigin =
    'https://www.einvoice.nat.gov.tw';
const String approvedCloudInvoiceQueryPath =
    '/portal/btc/mobile/btc502w/search';
const int authenticatedSelectorProbeSchemaVersion = 1;

enum AuthenticatedSelectorCapability {
  startDate,
  endDate,
  carrierSelector,
  invoiceStatusSelector,
  buyerIdentifierInput,
  itemKeywordInput,
  queryButton,
  clearButton,
  pageSizeSelector,
  currentPageIndicator,
  totalPageIndicator,
  totalRowIndicator,
  resultTable,
}

const Set<AuthenticatedSelectorCapability> _queryCapabilities =
    <AuthenticatedSelectorCapability>{
  AuthenticatedSelectorCapability.startDate,
  AuthenticatedSelectorCapability.endDate,
  AuthenticatedSelectorCapability.carrierSelector,
  AuthenticatedSelectorCapability.invoiceStatusSelector,
  AuthenticatedSelectorCapability.buyerIdentifierInput,
  AuthenticatedSelectorCapability.itemKeywordInput,
  AuthenticatedSelectorCapability.queryButton,
  AuthenticatedSelectorCapability.clearButton,
};

const Set<AuthenticatedSelectorCapability> _resultCapabilities =
    <AuthenticatedSelectorCapability>{
  AuthenticatedSelectorCapability.pageSizeSelector,
  AuthenticatedSelectorCapability.currentPageIndicator,
  AuthenticatedSelectorCapability.totalPageIndicator,
  AuthenticatedSelectorCapability.totalRowIndicator,
  AuthenticatedSelectorCapability.resultTable,
};

extension AuthenticatedSelectorCapabilityId
    on AuthenticatedSelectorCapability {
  String get id => switch (this) {
        AuthenticatedSelectorCapability.startDate => 'startDate',
        AuthenticatedSelectorCapability.endDate => 'endDate',
        AuthenticatedSelectorCapability.carrierSelector => 'carrierSelector',
        AuthenticatedSelectorCapability.invoiceStatusSelector =>
          'invoiceStatusSelector',
        AuthenticatedSelectorCapability.buyerIdentifierInput =>
          'buyerIdentifierInput',
        AuthenticatedSelectorCapability.itemKeywordInput =>
          'itemKeywordInput',
        AuthenticatedSelectorCapability.queryButton => 'queryButton',
        AuthenticatedSelectorCapability.clearButton => 'clearButton',
        AuthenticatedSelectorCapability.pageSizeSelector => 'pageSizeSelector',
        AuthenticatedSelectorCapability.currentPageIndicator =>
          'currentPageIndicator',
        AuthenticatedSelectorCapability.totalPageIndicator =>
          'totalPageIndicator',
        AuthenticatedSelectorCapability.totalRowIndicator =>
          'totalRowIndicator',
        AuthenticatedSelectorCapability.resultTable => 'resultTable',
      };

  bool get requiredForQueryPopulation => _queryCapabilities.contains(this);
  bool get requiredForResultExtraction => _resultCapabilities.contains(this);
}

class AuthenticatedSelectorSpec {
  const AuthenticatedSelectorSpec({
    required this.capability,
    required this.selectors,
    this.maximumMatches = 1,
  }) : assert(maximumMatches > 0);

  final AuthenticatedSelectorCapability capability;
  final List<String> selectors;
  final int maximumMatches;
}

const List<AuthenticatedSelectorSpec> officialQuerySelectorAllowlist =
    <AuthenticatedSelectorSpec>[
  AuthenticatedSelectorSpec(
    capability: AuthenticatedSelectorCapability.startDate,
    selectors: <String>[
      'input[name="startDate"]',
      'input[id="startDate"]',
      'input[name="beginDate"]',
      'input[id="beginDate"]',
      'input[placeholder="開始日期"]',
      'input[placeholder="起始日期"]',
    ],
  ),
  AuthenticatedSelectorSpec(
    capability: AuthenticatedSelectorCapability.endDate,
    selectors: <String>[
      'input[name="endDate"]',
      'input[id="endDate"]',
      'input[placeholder="結束日期"]',
      'input[placeholder="截止日期"]',
    ],
  ),
  AuthenticatedSelectorSpec(
    capability: AuthenticatedSelectorCapability.carrierSelector,
    selectors: <String>[
      'select[name="carrierType"]',
      'select[id="carrierType"]',
      '[role="combobox"][aria-label="歸戶載具列表"]',
    ],
  ),
  AuthenticatedSelectorSpec(
    capability: AuthenticatedSelectorCapability.invoiceStatusSelector,
    selectors: <String>[
      'select[name="invoiceStatus"]',
      'select[id="invoiceStatus"]',
      '[role="combobox"][aria-label="發票狀態"]',
    ],
  ),
  AuthenticatedSelectorSpec(
    capability: AuthenticatedSelectorCapability.buyerIdentifierInput,
    selectors: <String>[
      'input[name="buyerIdentifier"]',
      'input[id="buyerIdentifier"]',
      'input[placeholder="買方統編"]',
    ],
  ),
  AuthenticatedSelectorSpec(
    capability: AuthenticatedSelectorCapability.itemKeywordInput,
    selectors: <String>[
      'input[name="itemKeyword"]',
      'input[id="itemKeyword"]',
      'input[placeholder="品名關鍵字"]',
    ],
  ),
  AuthenticatedSelectorSpec(
    capability: AuthenticatedSelectorCapability.queryButton,
    selectors: <String>[
      'button[type="submit"]',
      'button[aria-label="查詢"]',
      'input[type="submit"][value="查詢"]',
    ],
  ),
  AuthenticatedSelectorSpec(
    capability: AuthenticatedSelectorCapability.clearButton,
    selectors: <String>[
      'button[type="reset"]',
      'button[aria-label="清除"]',
      'input[type="reset"][value="清除"]',
    ],
  ),
  AuthenticatedSelectorSpec(
    capability: AuthenticatedSelectorCapability.pageSizeSelector,
    selectors: <String>[
      'select[name="pageSize"]',
      'select[id="pageSize"]',
      'select[aria-label="每頁筆數"]',
      '[role="combobox"][aria-label="每頁筆數"]',
    ],
  ),
  AuthenticatedSelectorSpec(
    capability: AuthenticatedSelectorCapability.currentPageIndicator,
    selectors: <String>[
      '[aria-current="page"]',
      '[data-testid="current-page"]',
      'input[aria-label="目前頁碼"]',
    ],
  ),
  AuthenticatedSelectorSpec(
    capability: AuthenticatedSelectorCapability.totalPageIndicator,
    selectors: <String>[
      '[data-testid="total-pages"]',
      '[aria-label="總頁數"]',
    ],
  ),
  AuthenticatedSelectorSpec(
    capability: AuthenticatedSelectorCapability.totalRowIndicator,
    selectors: <String>[
      '[data-testid="total-rows"]',
      '[aria-label="總筆數"]',
    ],
  ),
  AuthenticatedSelectorSpec(
    capability: AuthenticatedSelectorCapability.resultTable,
    selectors: <String>[
      'table[aria-label="發票查詢結果"]',
      'table[id="invoiceResultTable"]',
      '[data-testid="invoice-result-table"]',
    ],
  ),
];

const List<String> expectedOfficialResultHeaders = <String>[
  '載具自訂名稱',
  '發票日期',
  '發票號碼',
  '發票金額',
  '發票狀態',
  '折讓',
  '賣方統一編號',
  '賣方名稱',
];

enum AuthenticatedSelectorProbeIssueCode {
  invalidPayload,
  unsupportedSchemaVersion,
  probeExecutionFailed,
  routeNotApproved,
  missingCapability,
  ambiguousCapability,
  invalidPageSize,
  missingExpectedHeader,
  unexpectedCapability,
  unexpectedHeader,
}

class AuthenticatedSelectorProbeIssue {
  const AuthenticatedSelectorProbeIssue({
    required this.code,
    required this.message,
    required this.isBlocking,
    this.capability,
    this.header,
  });

  final AuthenticatedSelectorProbeIssueCode code;
  final String message;
  final bool isBlocking;
  final AuthenticatedSelectorCapability? capability;
  final String? header;
}

class AuthenticatedSelectorCapabilityMatch {
  const AuthenticatedSelectorCapabilityMatch({
    required this.capability,
    required this.matchCount,
    required this.maximumMatches,
  });

  final AuthenticatedSelectorCapability capability;
  final int matchCount;
  final int maximumMatches;

  bool get found => matchCount > 0;
  bool get ambiguous => matchCount > maximumMatches;
  bool get valid => found && !ambiguous;
}

class AuthenticatedSelectorCapabilityReport {
  const AuthenticatedSelectorCapabilityReport({
    required this.probeSucceeded,
    required this.routeApproved,
    required this.matches,
    required this.availablePageSizes,
    required this.headerMatches,
    required this.issues,
  });

  final bool probeSucceeded;
  final bool routeApproved;
  final Map<AuthenticatedSelectorCapability,
      AuthenticatedSelectorCapabilityMatch> matches;
  final List<int> availablePageSizes;
  final Map<String, bool> headerMatches;
  final List<AuthenticatedSelectorProbeIssue> issues;

  bool get isBlocked => issues.any((issue) => issue.isBlocking);

  bool get canProceedToQueryPopulation =>
      probeSucceeded &&
      routeApproved &&
      !isBlocked &&
      _queryCapabilities.every(
        (capability) => matches[capability]?.valid ?? false,
      );

  bool get canProceedToResultExtraction =>
      canProceedToQueryPopulation &&
      _resultCapabilities.every(
        (capability) => matches[capability]?.valid ?? false,
      ) &&
      expectedOfficialResultHeaders.every(
        (header) => headerMatches[header] ?? false,
      );

  bool get requiresManualCsvFallback => !canProceedToQueryPopulation;
}

abstract interface class AuthenticatedSelectorCapabilityProbeRuntime {
  Future<AuthenticatedSelectorCapabilityReport> probeSelectorCapabilities();
}

class AuthenticatedSelectorCapabilityReportParser {
  const AuthenticatedSelectorCapabilityReportParser({
    this.allowlist = officialQuerySelectorAllowlist,
  });

  final List<AuthenticatedSelectorSpec> allowlist;

  AuthenticatedSelectorCapabilityReport parse(Object? rawResult) {
    final decoded = _decodeResult(rawResult);
    if (decoded == null) {
      return _invalidReport(
        AuthenticatedSelectorProbeIssueCode.invalidPayload,
        'The selector probe returned an invalid payload.',
      );
    }

    const allowedKeys = <String>{
      'schemaVersion',
      'probeSucceeded',
      'routeApproved',
      'capabilities',
      'availablePageSizes',
      'headers',
      'errorCode',
    };
    if (decoded.keys.toSet().difference(allowedKeys).isNotEmpty) {
      return _invalidReport(
        AuthenticatedSelectorProbeIssueCode.invalidPayload,
        'The selector probe returned unsupported fields.',
      );
    }
    if (decoded['schemaVersion'] != authenticatedSelectorProbeSchemaVersion) {
      return _invalidReport(
        AuthenticatedSelectorProbeIssueCode.unsupportedSchemaVersion,
        'The selector probe schema version is unsupported.',
      );
    }

    final probeSucceeded = decoded['probeSucceeded'] == true;
    final routeApproved = decoded['routeApproved'] == true;
    final issues = <AuthenticatedSelectorProbeIssue>[
      if (!probeSucceeded)
        const AuthenticatedSelectorProbeIssue(
          code: AuthenticatedSelectorProbeIssueCode.probeExecutionFailed,
          message: 'The structural probe could not be completed.',
          isBlocking: true,
        ),
      if (!routeApproved)
        const AuthenticatedSelectorProbeIssue(
          code: AuthenticatedSelectorProbeIssueCode.routeNotApproved,
          message: 'The current page is not the approved invoice query route.',
          isBlocking: true,
        ),
    ];

    final expectedSpecs = <String, AuthenticatedSelectorSpec>{
      for (final spec in allowlist) spec.capability.id: spec,
    };
    final rawCapabilities = _stringKeyedMap(decoded['capabilities']);
    if (rawCapabilities == null) {
      return _invalidReport(
        AuthenticatedSelectorProbeIssueCode.invalidPayload,
        'The capability section is invalid.',
      );
    }
    for (final unknownId
        in rawCapabilities.keys.toSet().difference(expectedSpecs.keys.toSet())) {
      issues.add(
        AuthenticatedSelectorProbeIssue(
          code: AuthenticatedSelectorProbeIssueCode.unexpectedCapability,
          message: 'Unexpected capability: $unknownId.',
          isBlocking: true,
        ),
      );
    }

    final matches = <AuthenticatedSelectorCapability,
        AuthenticatedSelectorCapabilityMatch>{};
    for (final entry in expectedSpecs.entries) {
      final rawCount = rawCapabilities[entry.key];
      final count = rawCount is int ? rawCount : null;
      if (count == null || count < 0) {
        issues.add(
          AuthenticatedSelectorProbeIssue(
            code: AuthenticatedSelectorProbeIssueCode.missingCapability,
            message: 'Capability ${entry.key} is missing or invalid.',
            isBlocking: entry.value.capability.requiredForQueryPopulation,
            capability: entry.value.capability,
          ),
        );
        continue;
      }
      final match = AuthenticatedSelectorCapabilityMatch(
        capability: entry.value.capability,
        matchCount: count,
        maximumMatches: entry.value.maximumMatches,
      );
      matches[entry.value.capability] = match;
      if (!match.found) {
        issues.add(
          AuthenticatedSelectorProbeIssue(
            code: AuthenticatedSelectorProbeIssueCode.missingCapability,
            message: 'Capability ${entry.key} was not found.',
            isBlocking: entry.value.capability.requiredForQueryPopulation,
            capability: entry.value.capability,
          ),
        );
      } else if (match.ambiguous) {
        issues.add(
          AuthenticatedSelectorProbeIssue(
            code: AuthenticatedSelectorProbeIssueCode.ambiguousCapability,
            message: 'Capability ${entry.key} matched too many elements.',
            isBlocking: true,
            capability: entry.value.capability,
          ),
        );
      }
    }

    final pageSizes = <int>[];
    final rawPageSizes = decoded['availablePageSizes'];
    if (rawPageSizes is List) {
      for (final value in rawPageSizes) {
        if (value is int && value > 0 && value <= 1000) {
          pageSizes.add(value);
        } else {
          issues.add(
            const AuthenticatedSelectorProbeIssue(
              code: AuthenticatedSelectorProbeIssueCode.invalidPageSize,
              message: 'The page-size probe returned an invalid value.',
              isBlocking: true,
            ),
          );
        }
      }
    } else {
      issues.add(
        const AuthenticatedSelectorProbeIssue(
          code: AuthenticatedSelectorProbeIssueCode.invalidPageSize,
          message: 'The page-size probe result is missing.',
          isBlocking: false,
        ),
      );
    }
    final normalizedPageSizes = pageSizes.toSet().toList()..sort();

    final rawHeaders = _stringKeyedMap(decoded['headers']);
    final headerMatches = <String, bool>{};
    if (rawHeaders != null) {
      for (final unknownHeader in rawHeaders.keys
          .toSet()
          .difference(expectedOfficialResultHeaders.toSet())) {
        issues.add(
          AuthenticatedSelectorProbeIssue(
            code: AuthenticatedSelectorProbeIssueCode.unexpectedHeader,
            message: 'Unexpected header capability: $unknownHeader.',
            isBlocking: true,
            header: unknownHeader,
          ),
        );
      }
    }
    for (final header in expectedOfficialResultHeaders) {
      final matched = rawHeaders?[header] == true;
      headerMatches[header] = matched;
      if (!matched) {
        issues.add(
          AuthenticatedSelectorProbeIssue(
            code: AuthenticatedSelectorProbeIssueCode.missingExpectedHeader,
            message: 'Expected result header is unavailable.',
            isBlocking: false,
            header: header,
          ),
        );
      }
    }

    return AuthenticatedSelectorCapabilityReport(
      probeSucceeded: probeSucceeded,
      routeApproved: routeApproved,
      matches: Map<AuthenticatedSelectorCapability,
          AuthenticatedSelectorCapabilityMatch>.unmodifiable(matches),
      availablePageSizes: List<int>.unmodifiable(normalizedPageSizes),
      headerMatches: Map<String, bool>.unmodifiable(headerMatches),
      issues: List<AuthenticatedSelectorProbeIssue>.unmodifiable(issues),
    );
  }

  Map<String, Object?>? _decodeResult(Object? rawResult) {
    Object? decoded = rawResult;
    for (var attempt = 0; attempt < 2 && decoded is String; attempt += 1) {
      try {
        decoded = jsonDecode(decoded);
      } on FormatException {
        return null;
      }
    }
    return _stringKeyedMap(decoded);
  }

  Map<String, Object?>? _stringKeyedMap(Object? value) {
    if (value is! Map) return null;
    return value.map((key, item) => MapEntry(key.toString(), item));
  }

  AuthenticatedSelectorCapabilityReport _invalidReport(
    AuthenticatedSelectorProbeIssueCode code,
    String message,
  ) {
    return AuthenticatedSelectorCapabilityReport(
      probeSucceeded: false,
      routeApproved: false,
      matches: const <AuthenticatedSelectorCapability,
          AuthenticatedSelectorCapabilityMatch>{},
      availablePageSizes: const <int>[],
      headerMatches: const <String, bool>{},
      issues: <AuthenticatedSelectorProbeIssue>[
        AuthenticatedSelectorProbeIssue(
          code: code,
          message: message,
          isBlocking: true,
        ),
      ],
    );
  }
}

String buildAuthenticatedSelectorCapabilityProbeScript({
  List<AuthenticatedSelectorSpec> allowlist = officialQuerySelectorAllowlist,
}) {
  final capabilityConfig = <String, Object?>{
    for (final spec in allowlist)
      spec.capability.id: <String, Object?>{
        'selectors': spec.selectors,
        'maximumMatches': spec.maximumMatches,
      },
  };
  final encodedConfig = jsonEncode(capabilityConfig);
  final encodedHeaders = jsonEncode(expectedOfficialResultHeaders);
  final encodedOrigin = jsonEncode(approvedCloudInvoiceQueryOrigin);
  final encodedPath = jsonEncode(approvedCloudInvoiceQueryPath);

  return '''
(() => {
  const schemaVersion = $authenticatedSelectorProbeSchemaVersion;
  const capabilityConfig = $encodedConfig;
  const expectedHeaders = $encodedHeaders;
  const approvedOrigin = $encodedOrigin;
  const approvedPath = $encodedPath;
  const safeCount = (selectors) => {
    const matches = new Set();
    for (const selector of selectors) {
      for (const element of document.querySelectorAll(selector)) {
        matches.add(element);
      }
    }
    return matches.size;
  };
  const normalizeHeader = (value) => String(value || '')
    .split('')
    .filter((character) => character.trim().length > 0)
    .join('');

  try {
    const routeApproved =
      window.location.origin === approvedOrigin &&
      window.location.pathname === approvedPath;
    const capabilities = {};
    for (const [id, config] of Object.entries(capabilityConfig)) {
      capabilities[id] = safeCount(config.selectors);
    }

    const pageSizes = new Set();
    const pageSizeSelectors =
      capabilityConfig.pageSizeSelector?.selectors ?? [];
    for (const selector of pageSizeSelectors) {
      for (const element of document.querySelectorAll(selector)) {
        if (element instanceof HTMLSelectElement) {
          for (const option of element.options) {
            const candidate = Number.parseInt(
              String(option.value || option.textContent || '').trim(),
              10,
            );
            if (Number.isInteger(candidate) && candidate > 0 && candidate <= 1000) {
              pageSizes.add(candidate);
            }
          }
        }
      }
    }

    const headers = {};
    for (const expectedHeader of expectedHeaders) {
      headers[expectedHeader] = false;
    }
    const resultTableSelectors =
      capabilityConfig.resultTable?.selectors ?? [];
    const tableMatches = new Set();
    for (const selector of resultTableSelectors) {
      for (const element of document.querySelectorAll(selector)) {
        tableMatches.add(element);
      }
    }
    for (const table of tableMatches) {
      for (const cell of table.querySelectorAll('th')) {
        const normalized = normalizeHeader(cell.textContent);
        for (const expectedHeader of expectedHeaders) {
          if (normalized === normalizeHeader(expectedHeader)) {
            headers[expectedHeader] = true;
          }
        }
      }
    }

    return JSON.stringify({
      schemaVersion,
      probeSucceeded: true,
      routeApproved,
      capabilities,
      availablePageSizes: Array.from(pageSizes).sort((a, b) => a - b),
      headers,
      errorCode: null,
    });
  } catch (_) {
    return JSON.stringify({
      schemaVersion,
      probeSucceeded: false,
      routeApproved: false,
      capabilities: {},
      availablePageSizes: [],
      headers: {},
      errorCode: 'PROBE_EXECUTION_FAILED',
    });
  }
})()
''';
}
