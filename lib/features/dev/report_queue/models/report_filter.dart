import 'report.dart';

/// The triage buckets the owner filters by — each a predicate over a report, so
/// the underlying status values stay the source of truth. Ported from Blueprint's
/// `ReportFilter`, trimmed to the Stock-Track slice.
enum ReportFilter {
  all('All'),
  pending('Pending'),
  inProgress('In progress'),
  resolved('Resolved'),
  flagged('Flagged');

  const ReportFilter(this.label);
  final String label;

  bool matches(Report r) {
    switch (this) {
      case ReportFilter.all:
        return true;
      case ReportFilter.pending:
        return r.status == 'new' || r.status == 'queued';
      case ReportFilter.inProgress:
        return r.status == 'in_progress' || r.status == 'awaiting_decision';
      case ReportFilter.resolved:
        return r.status == 'fixed' || r.status == 'wont_fix' || r.manualResolved;
      case ReportFilter.flagged:
        return r.flaggedForOrchestrator;
    }
  }
}
