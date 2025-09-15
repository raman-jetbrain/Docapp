class DocumentItem {
  DocumentItem({
    required this.id,
    required this.title,
    this.localPath,
    this.remoteUrl,
    this.mimeType,
  });

  final String id;
  String title;
  String? localPath;
  String? remoteUrl;
  String? mimeType;

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'localPath': localPath,
        'remoteUrl': remoteUrl,
        'mimeType': mimeType,
      };

  factory DocumentItem.fromMap(Map<String, dynamic> map) => DocumentItem(
        id: map['id'],
        title: map['title'],
        localPath: map['localPath'],
        remoteUrl: map['remoteUrl'],
        mimeType: map['mimeType'],
      );
}