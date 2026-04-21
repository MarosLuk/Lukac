import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../services/sources/task_source.dart';
import '../state/providers.dart';
import '../widgets/ui/section_header.dart';

/// The Sources tab: list of connected external task sources and the
/// available catalogue below. No OAuth in this pass — all currently-listed
/// sources (ICS URL, Todoist) are form-based.
class SourcesScreen extends ConsumerWidget {
  const SourcesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final connectedAsync = ref.watch(connectedSourcesProvider);
    final descriptors = ref.watch(availableSourceTypesProvider);
    final descriptorsById = {for (final d in descriptors) d.id: d};

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: connectedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Could not load sources.\n\n$e'),
        ),
        data: (configs) {
          final connectedIds = configs.map((c) => c.sourceId).toSet();
          final available = descriptors
              .where((d) => !connectedIds.contains(d.id))
              .toList();

          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              SectionHeader(
                'Connected',
                trailing: TextButton.icon(
                  onPressed: configs.isEmpty
                      ? null
                      : () => ref
                          .read(externalTasksProvider.notifier)
                          .refresh(),
                  icon: const Icon(Icons.sync, size: 18),
                  label: const Text('Sync now'),
                ),
              ),
              if (configs.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
                  child: Text(
                    'No sources yet. Connect one below to start pulling '
                    'external tasks into your list.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                for (final cfg in configs)
                  _ConnectedRow(
                    config: cfg,
                    descriptor: descriptorsById[cfg.sourceId],
                  ),
              const SectionHeader('Available'),
              if (available.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
                  child: Text(
                    'All supported sources are connected.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                for (final d in available) _AvailableRow(descriptor: d),
            ],
          );
        },
      ),
    );
  }
}

class _ConnectedRow extends ConsumerWidget {
  const _ConnectedRow({required this.config, required this.descriptor});

  final TaskSourceConfig config;
  final SourceDescriptor? descriptor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final name = descriptor?.displayName ?? config.sourceId;
    final icon = descriptor?.icon ?? Icons.extension_outlined;
    final statusColor = config.enabled ? cs.primary : cs.outline;
    final lastSync = config.lastSyncAt;
    final subtitle = lastSync == null
        ? (config.enabled ? 'Not synced yet' : 'Disabled')
        : 'Last sync ${DateFormat.MMMd().add_jm().format(lastSync)}';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      leading: Icon(icon, color: cs.onSurfaceVariant),
      title: Row(
        children: [
          Text(name, style: theme.textTheme.bodyLarge),
          const SizedBox(width: 8),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: cs.onSurfaceVariant,
        ),
      ),
      trailing: IconButton(
        tooltip: 'Disconnect',
        icon: const Icon(Icons.link_off_outlined),
        onPressed: () => ref
            .read(connectedSourcesProvider.notifier)
            .disconnect(config.sourceId),
      ),
      onTap: descriptor == null
          ? null
          : () => _showConfigSheet(
                context,
                descriptor: descriptor!,
                existing: config,
              ),
    );
  }
}

class _AvailableRow extends StatelessWidget {
  const _AvailableRow({required this.descriptor});

  final SourceDescriptor descriptor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      leading: Icon(descriptor.icon, color: cs.onSurfaceVariant),
      title: Text(descriptor.displayName, style: theme.textTheme.bodyLarge),
      subtitle: Text(
        descriptor.description,
        style: theme.textTheme.bodySmall?.copyWith(
          color: cs.onSurfaceVariant,
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () =>
          _showConfigSheet(context, descriptor: descriptor, existing: null),
    );
  }
}

Future<void> _showConfigSheet(
  BuildContext context, {
  required SourceDescriptor descriptor,
  required TaskSourceConfig? existing,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _SourceConfigSheet(
      descriptor: descriptor,
      existing: existing,
    ),
  );
}

class _SourceConfigSheet extends ConsumerStatefulWidget {
  const _SourceConfigSheet({required this.descriptor, required this.existing});

  final SourceDescriptor descriptor;
  final TaskSourceConfig? existing;

  @override
  ConsumerState<_SourceConfigSheet> createState() => _SourceConfigSheetState();
}

class _SourceConfigSheetState extends ConsumerState<_SourceConfigSheet> {
  late final Map<String, TextEditingController> _controllers;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final spec in widget.descriptor.fields)
        spec.key: TextEditingController(
          text: widget.existing?.fields[spec.key] ?? '',
        ),
    };
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.existing != null;

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(widget.descriptor.icon,
                  color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Text(widget.descriptor.displayName,
                  style: theme.textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.descriptor.description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          for (final spec in widget.descriptor.fields) ...[
            TextField(
              controller: _controllers[spec.key],
              obscureText: spec.obscured,
              decoration: InputDecoration(
                labelText: spec.label,
                hintText: spec.hint.isEmpty ? null : spec.hint,
              ),
              autocorrect: false,
              enableSuggestions: false,
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _submit,
              child: Text(isEditing ? 'Save' : 'Connect'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final fields = <String, String>{
      for (final entry in _controllers.entries)
        entry.key: entry.value.text.trim(),
    };
    // Minimal validation: all declared fields must be non-empty.
    for (final spec in widget.descriptor.fields) {
      if ((fields[spec.key] ?? '').isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${spec.label} is required')),
        );
        return;
      }
    }
    setState(() => _saving = true);
    await ref
        .read(connectedSourcesProvider.notifier)
        .connect(widget.descriptor.id, fields);
    if (mounted) Navigator.of(context).pop();
  }
}
