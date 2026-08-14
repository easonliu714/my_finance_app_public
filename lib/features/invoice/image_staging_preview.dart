enum ImageSourceOption {
  camera,
  gallery,
  manual,
}

enum ImageStagingPreviewStatus {
  empty,
  pending,
  ready,
  rejected,
  converted,
}

enum ImageStagingPreviewKind {
  invoice,
  product,
}

class ImageSourceChoice {
  const ImageSourceChoice({
    required this.option,
    required this.label,
    required this.description,
    this.enabled = false,
  });

  final ImageSourceOption option;
  final String label;
  final String description;
  final bool enabled;
}

class ImageStagingPreviewItem {
  const ImageStagingPreviewItem({
    required this.id,
    required this.kind,
    required this.status,
    required this.sourceOption,
    required this.title,
    required this.summary,
  });

  final String id;
  final ImageStagingPreviewKind kind;
  final ImageStagingPreviewStatus status;
  final ImageSourceOption sourceOption;
  final String title;
  final String summary;

  bool get canReview => status == ImageStagingPreviewStatus.ready;
  bool get canConvert => status == ImageStagingPreviewStatus.ready;
  bool get isTerminal => status == ImageStagingPreviewStatus.rejected || status == ImageStagingPreviewStatus.converted;
}

class ImageStagingPreviewState {
  const ImageStagingPreviewState({
    this.sourceChoices = defaultSourceChoices,
    this.items = const <ImageStagingPreviewItem>[],
  });

  static const List<ImageSourceChoice> defaultSourceChoices = <ImageSourceChoice>[
    ImageSourceChoice(
      option: ImageSourceOption.camera,
      label: '拍照',
      description: '後續接入相機；本階段只顯示入口。',
    ),
    ImageSourceChoice(
      option: ImageSourceOption.gallery,
      label: '從相簿選擇',
      description: '後續接入相簿選擇；本階段只顯示入口。',
    ),
    ImageSourceChoice(
      option: ImageSourceOption.manual,
      label: '手動建立',
      description: '保留手動輸入與人工確認流程。',
      enabled: true,
    ),
  ];

  final List<ImageSourceChoice> sourceChoices;
  final List<ImageStagingPreviewItem> items;

  bool get isEmpty => items.isEmpty;
  int get pendingCount => items.where((item) => item.status == ImageStagingPreviewStatus.pending).length;
  int get readyCount => items.where((item) => item.status == ImageStagingPreviewStatus.ready).length;

  ImageStagingPreviewState copyWith({
    List<ImageSourceChoice>? sourceChoices,
    List<ImageStagingPreviewItem>? items,
  }) {
    return ImageStagingPreviewState(
      sourceChoices: sourceChoices ?? this.sourceChoices,
      items: items ?? this.items,
    );
  }
}

class ImageStagingPreviewCopy {
  const ImageStagingPreviewCopy._();

  static const String title = '影像輔助記帳';
  static const String subtitle = '支援發票與商品影像的 staging preview；正式寫入前必須人工確認。';
  static const String reviewFirst = '所有影像結果都只會進入待審核清單，不會自動建立交易。';
  static const String empty = '目前沒有待審核影像項目。';
}
