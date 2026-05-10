import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'settings_scope.dart';

/// Network icon that gracefully handles SVG and raster images without
/// crashing on network errors. Uses [DefaultCacheManager] for disk caching
/// (shared with [CachedNetworkImage]) plus an in-memory cache for sanitized
/// SVG bytes so widget rebuilds don't re-decode.
class SafeNetworkIcon extends StatefulWidget {
  const SafeNetworkIcon({
    super.key,
    required this.url,
    this.size = 40,
    this.placeholder,
    this.fit,
  });

  final String? url;
  final double size;
  final Widget? placeholder;

  /// How to inscribe the image into the available space.
  /// When null, uses fixed [size] x [size]. When set, only [size] controls
  /// the height and the width adapts to the aspect ratio.
  final BoxFit? fit;

  @override
  State<SafeNetworkIcon> createState() => _SafeNetworkIconState();
}

/// Process-wide caches for SVG icons so re-mounted widgets don't refetch.
final Map<String, Uint8List> _svgMemoryCache = {};
final Map<String, Future<Uint8List?>> _svgInflight = {};
final Set<String> _svgFailed = {};

class _SafeNetworkIconState extends State<SafeNetworkIcon> {
  Uint8List? _svgBytes;
  bool _failed = false;
  bool _loading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(SafeNetworkIcon old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _svgBytes = null;
      _failed = false;
      _load();
    }
  }

  Future<void> _load() async {
    // Privacy gate: if the user has disabled remote icon loading, do not
    // contact the network at all.
    final settings = SettingsScope.maybeOf(context)?.settings;
    if (settings != null && !settings.loadRemoteIcons) return;

    final url = widget.url;
    if (url == null || url.isEmpty || !url.endsWith('.svg')) return;

    final cached = _svgMemoryCache[url];
    if (cached != null) {
      setState(() {
        _svgBytes = cached;
        _failed = false;
        _loading = false;
      });
      return;
    }
    if (_svgFailed.contains(url)) {
      setState(() => _failed = true);
      return;
    }

    setState(() => _loading = true);
    final bytes = await _fetchSvgDeduped(url);
    if (!mounted) return;
    if (bytes != null) {
      setState(() {
        _svgBytes = bytes;
        _loading = false;
      });
    } else {
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  Future<Uint8List?> _fetchSvgDeduped(String url) {
    return _svgInflight.putIfAbsent(url, () async {
      try {
        final bytes = await _fetchSvgWithRetry(url);
        final sanitized = _sanitizeSvg(bytes);
        _svgMemoryCache[url] = sanitized;
        return sanitized;
      } catch (_) {
        _svgFailed.add(url);
        return null;
      } finally {
        _svgInflight.remove(url);
      }
    });
  }

  Future<Uint8List> _fetchSvgWithRetry(String url) async {
    final manager = DefaultCacheManager();
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final file = await manager
            .getSingleFile(url)
            .timeout(const Duration(seconds: 8));
        return await file.readAsBytes();
      } catch (e) {
        lastError = e;
        if (attempt == 0) {
          await Future.delayed(const Duration(milliseconds: 400));
        }
      }
    }
    throw lastError ?? Exception('SVG fetch failed');
  }

  Uint8List _sanitizeSvg(Uint8List bytes) {
    try {
      var text = utf8.decode(bytes);
      // Inkscape metadata commonly triggers noisy "unhandled element" logs.
      text = text.replaceAll(
        RegExp(r'<sodipodi:namedview[^>]*\/>', multiLine: true),
        '',
      );
      text = text.replaceAll(
        RegExp(
          r'<sodipodi:namedview[\s\S]*?<\/sodipodi:namedview>',
          multiLine: true,
        ),
        '',
      );
      // Remove empty defs blocks that carry no rendering info.
      text = text.replaceAll(RegExp(r'<defs\s*/>', multiLine: true), '');
      return Uint8List.fromList(utf8.encode(text));
    } catch (_) {
      return bytes;
    }
  }

  Widget _defaultPlaceholder() {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        LucideIcons.globe,
        size: widget.size * 0.55,
        color: Colors.grey,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Privacy gate: when the user has disabled remote icon loading, render
    // nothing — not even a placeholder. The widget effectively disappears.
    final settings = SettingsScope.maybeOf(context)?.settings;
    if (settings != null && !settings.loadRemoteIcons) {
      return const SizedBox.shrink();
    }

    final url = widget.url;
    final placeholder = widget.placeholder ?? _defaultPlaceholder();

    if (url == null || url.isEmpty) return placeholder;

    // SVG path
    if (url.endsWith('.svg')) {
      if (_failed) return placeholder;
      if (_loading || _svgBytes == null) return placeholder;
      return SvgPicture.memory(
        _svgBytes!,
        width: widget.fit != null ? null : widget.size,
        height: widget.size,
        fit: widget.fit ?? BoxFit.contain,
      );
    }

    // Raster image — CachedNetworkImage handles disk caching out of the box.
    return CachedNetworkImage(
      key: ValueKey('cni:$url'),
      imageUrl: url,
      width: widget.fit != null ? null : widget.size,
      height: widget.size,
      fit: widget.fit ?? BoxFit.contain,
      fadeInDuration: const Duration(milliseconds: 120),
      fadeOutDuration: Duration.zero,
      errorWidget: (context, url, error) => placeholder,
      placeholder: (context, url) => placeholder,
    );
  }
}
