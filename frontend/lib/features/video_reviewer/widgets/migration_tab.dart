import 'package:flutter/material.dart';

import '../models/upload_activity_models.dart';

class MigrationTab extends StatelessWidget {
  const MigrationTab({
    required this.selectedPaths,
    required this.totalPathCount,
    required this.uploadNameController,
    required this.uploadNameEnabled,
    required this.visibilitySetting,
    required this.onVisibilityChanged,
    required this.madeForKids,
    required this.onMadeForKidsChanged,
    required this.isKeepLocalLoading,
    required this.isKeepLocalAvailable,
    required this.keepLocalValue,
    required this.onKeepLocalChanged,
    required this.isBusy,
    required this.onUploadPressed,
    required this.onUploadArchivePressed,
    required this.onSelectAllPressed,
    required this.onDeselectAllPressed,
    required this.isActivityPanelExpanded,
    required this.onToggleActivityPanel,
    required this.uploadJobs,
    required this.isJobExpanded,
    required this.onToggleJobExpanded,
    super.key,
  });

  final List<String> selectedPaths;
  final int totalPathCount;
  final TextEditingController uploadNameController;
  final bool uploadNameEnabled;
  final String visibilitySetting;
  final ValueChanged<String?> onVisibilityChanged;
  final bool madeForKids;
  final ValueChanged<bool?> onMadeForKidsChanged;
  final bool isKeepLocalLoading;
  final bool isKeepLocalAvailable;
  final bool? keepLocalValue;
  final Future<void> Function(bool value) onKeepLocalChanged;
  final bool isBusy;
  final Future<void> Function() onUploadPressed;
  final Future<void> Function() onUploadArchivePressed;
  final Future<void> Function() onSelectAllPressed;
  final Future<void> Function() onDeselectAllPressed;
  final bool isActivityPanelExpanded;
  final VoidCallback onToggleActivityPanel;
  final List<UploadJobState> uploadJobs;
  final bool Function(String jobId) isJobExpanded;
  final void Function(String jobId) onToggleJobExpanded;

  @override
  Widget build(BuildContext context) {
    final bool canSubmit = !isBusy && selectedPaths.isNotEmpty;
    final bool canSelectAll =
        !isBusy && totalPathCount > 0 && selectedPaths.length < totalPathCount;
    final bool canDeselectAll = !isBusy && selectedPaths.isNotEmpty;
    final bool keepLocalEnabled = !isBusy && isKeepLocalAvailable;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: uploadNameController,
              enabled: uploadNameEnabled && !isBusy,
              decoration: InputDecoration(
                hintText: 'Upload name (default to video title)',
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: const Color(0xFF232323),
                helperText: uploadNameEnabled
                    ? null
                    : 'Only enabled when exactly one video is selected.',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String>(
                    value: visibilitySetting,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Color(0xFF232323),
                    ),
                    items: const <DropdownMenuItem<String>>[
                      DropdownMenuItem<String>(
                        value: 'unlisted',
                        child: Text('Unlisted'),
                      ),
                      DropdownMenuItem<String>(
                        value: 'private',
                        child: Text('Private'),
                      ),
                      DropdownMenuItem<String>(
                        value: 'public',
                        child: Text('Public'),
                      ),
                    ],
                    onChanged: isBusy ? null : onVisibilityChanged,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: madeForKids,
                    onChanged: isBusy ? null : onMadeForKidsChanged,
                    title: const Text('Made for kids'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: keepLocalValue ?? false,
              onChanged: keepLocalEnabled
                  ? (bool? value) {
                      if (value == null) {
                        return;
                      }
                      onKeepLocalChanged(value);
                    }
                  : null,
              title: Text(
                isKeepLocalLoading
                    ? 'Mark to keep local (loading...)'
                    : 'Mark to keep local',
              ),
              subtitle: isKeepLocalLoading
                  ? null
                  : (isKeepLocalAvailable
                        ? null
                        : const Text(
                            'Available only when all selected files share the same value.',
                          )),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                OutlinedButton(
                  onPressed: canSelectAll ? onSelectAllPressed : null,
                  child: const Text('Select all'),
                ),
                OutlinedButton(
                  onPressed: canDeselectAll ? onDeselectAllPressed : null,
                  child: const Text('Deselect all'),
                ),
                FilledButton(
                  onPressed: canSubmit ? onUploadPressed : null,
                  child: const Text('Upload'),
                ),
                FilledButton(
                  onPressed: canSubmit ? onUploadArchivePressed : null,
                  child: const Text('Upload and archive'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildUploadActivityPanel(context),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadActivityPanel(BuildContext context) {
    final TextStyle? titleStyle = Theme.of(context).textTheme.titleSmall;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF1F1F1F),
        border: Border.all(color: const Color(0xFF3A3A3A)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: <Widget>[
          InkWell(
            onTap: onToggleActivityPanel,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Upload Activity (${uploadJobs.length})',
                      style: titleStyle,
                    ),
                  ),
                  Icon(
                    isActivityPanelExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                  ),
                ],
              ),
            ),
          ),
          if (isActivityPanelExpanded)
            const Divider(height: 1, color: Color(0xFF3A3A3A)),
          if (isActivityPanelExpanded)
            Padding(
              padding: const EdgeInsets.all(10),
              child: uploadJobs.isEmpty
                  ? const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'No upload jobs yet.',
                        style: TextStyle(color: Color(0xFFB0B0B0)),
                      ),
                    )
                  : Column(
                      children: uploadJobs.map(_buildJobCard).toList(),
                    ),
            ),
        ],
      ),
    );
  }

  Widget _buildJobCard(UploadJobState job) {
    final bool expanded = isJobExpanded(job.jobId);
    final String shortJobId = job.jobId.length <= 8
        ? job.jobId
        : job.jobId.substring(0, 8);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF232323),
        border: Border.all(color: const Color(0xFF3A3A3A)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: <Widget>[
          InkWell(
            onTap: () => onToggleJobExpanded(job.jobId),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Job $shortJobId',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  _buildStatusChip(job),
                  const SizedBox(width: 8),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: LinearProgressIndicator(
              value: (job.overallPercent / 100).clamp(0, 1).toDouble(),
              minHeight: 6,
              backgroundColor: const Color(0xFF121212),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Row(
              children: <Widget>[
                Text('Done ${job.finishedFiles}/${job.totalFiles}'),
                const SizedBox(width: 10),
                Text('Success ${job.successCount}'),
                const SizedBox(width: 10),
                Text('Failed ${job.errorCount}'),
                const Spacer(),
                Text('${job.overallPercent}%'),
              ],
            ),
          ),
          if (expanded)
            const Divider(height: 1, color: Color(0xFF3A3A3A)),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: job.files.isEmpty
                  ? const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Waiting for file events...',
                        style: TextStyle(color: Color(0xFFB0B0B0)),
                      ),
                    )
                  : Column(
                      children: job.files.map(_buildFileRow).toList(),
                    ),
            ),
        ],
      ),
    );
  }

  Widget _buildFileRow(UploadFileState file) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          border: Border.all(color: const Color(0xFF333333)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      _titleForPath(file.filePath),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${file.percent}%',
                    style: const TextStyle(color: Color(0xFFB0B0B0)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                file.message.isEmpty ? file.state : file.message,
                style: const TextStyle(color: Color(0xFFB0B0B0)),
              ),
              if (file.error != null && file.error!.trim().isNotEmpty) ...<
                Widget
              >[
                const SizedBox(height: 4),
                Text(
                  file.error!,
                  style: const TextStyle(color: Color(0xFFFF8888)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(UploadJobState job) {
    final String label = job.isComplete
        ? (job.errorCount > 0 ? 'Complete with errors' : 'Complete')
        : 'In progress';
    final Color chipColor = job.isComplete
        ? (job.errorCount > 0
              ? const Color(0xFF6E2B2B)
              : const Color(0xFF1F4D2C))
        : const Color(0xFF2A3B5C);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  String _titleForPath(String path) {
    final String normalized = path.replaceAll('\\', '/');
    final List<String> segments = normalized.split('/');
    return segments.isEmpty ? path : segments.last;
  }
}
