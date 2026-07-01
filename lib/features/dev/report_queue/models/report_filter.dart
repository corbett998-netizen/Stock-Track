import 'report.dart';

/// The triage buckets the owner filters by — each a predicate over a report, so
/// the underlying status values stay the source of truth. Ported from Blueprint's
/// `ReportFilter`, trimmed to the Stock-Track slice.
enum ReportFilter {
  all('All'),
  pending('Pending'),
  inProgress('In progress'),
  readyToTest('Ready to test'),
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
      case ReportFilter.readyToTest:
        // Dogfood check-items awaiting the owner's Works/Still-broken verdict.
        return r.awaitingVerification;
      case ReportFilter.resolved:
        // A check-item still awaiting verification is NOT "resolved" yet, even
        // though its raw status is 'fixed'.
        return !r.awaitingVerification &&
            (r.status == 'fixed' || r.status == 'wont_fix' || r.manualResolved);
      case ReportFilter.flagged:
        return r.flaggedForOrchestrator;
    }
  }
}
