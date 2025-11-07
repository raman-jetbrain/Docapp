import 'dart:ui';

import 'package:flutter/material.dart';

class _DocCard extends StatelessWidget {
  const _DocCard({
    required this.title,
    required this.onTap,
    required this.onUpload,
    required this.onShare,
    required this.borderColor,
    required this.iconColor,
    required this.selected, 
    this.onDownload, 
    this.onLongPress, 
    this.onDelete, 
    this.onEdit,
  });
  final String title;
  final VoidCallback onTap;
  final VoidCallback onUpload;
  final VoidCallback? onDownload;
  final VoidCallback onShare;
  final VoidCallback? onLongPress;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit; 
  final Color borderColor;
  final Color iconColor;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onUpload,
          icon: Icon(Icons.upload_rounded, color: iconColor, size: 24),
          tooltip: 'Upload',
        ),
        if (onDownload != null)
          IconButton(
            onPressed: onDownload,
            icon: Icon(Icons.download_rounded, color: iconColor, size: 24),
            tooltip: 'Download',
          ),
        IconButton(
          onPressed: onShare,
          icon: Icon(Icons.share, color: iconColor, size: 22),
          tooltip: 'Share',
        ),
        if (selected && onEdit != null)
          IconButton(
            onPressed: onEdit,
            icon: const Icon(Icons.edit, color: Colors.white, size: 24),
            tooltip: 'Edit',
          ),
        if (selected && onDelete != null)
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete, color: Colors.white, size: 24),
            tooltip: 'Delete',
          ),
      ],
    );
  }
}