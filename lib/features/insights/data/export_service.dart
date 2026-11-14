import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../../core/utils/app_clock.dart';
import '../../../core/utils/date_range.dart';
import '../../../core/utils/formatters.dart';
import '../../dashboard/domain/period_aggregate.dart';
import '../../transactions/domain/transaction.dart';

/// PDF and Excel report export, shared through the platform share sheet.
class ExportService {
  String _money(double v, String c) => Fmt.money(v, currency: c, precise: true).replaceAll('₹', 'Rs ');

  Future<File> buildPdf({
    required String workspaceName,
    required DateRangePeriod period,
    required PeriodAggregate agg,
    required List<FinancialTransaction> transactions,
  }) async {
    final doc = pw.Document(title: 'Smart Spend Report – ${period.label}', author: 'Smart Spend Tracker');
    final navy = PdfColor.fromInt(0xFF142B4A);
    final c = agg.currency;

    pw.Widget kpi(String label, String value, PdfColor color) => pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(10),
            margin: const pw.EdgeInsets.only(right: 6),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300), borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
              pw.SizedBox(height: 4),
              pw.Text(value, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: color)),
            ]),
          ),
        );

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      header: (_) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 8),
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300))),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('Smart Spend Tracker', style: pw.TextStyle(color: navy, fontWeight: pw.FontWeight.bold, fontSize: 14)),
          pw.Text('$workspaceName • ${period.label}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        ]),
      ),
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
      ),
      build: (_) => [
        pw.SizedBox(height: 12),
        pw.Row(children: [
          kpi('Total inflow', _money(agg.inflow, c), PdfColors.green700),
          kpi('Total outflow', _money(agg.outflow, c), PdfColors.red700),
          kpi('Net cash flow', _money(agg.net, c), navy),
          kpi('Transactions', '${agg.count}', navy),
        ]),
        pw.SizedBox(height: 18),
        pw.Text('Category-wise spending', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
        pw.SizedBox(height: 6),
        pw.TableHelper.fromTextArray(
          headers: ['Category', 'Amount', 'Share', 'Count'],
          data: [for (final s in agg.expenseCategories) [s.category.name, _money(s.amount, c), Fmt.percent(s.percent), '${s.count}']],
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9),
          headerDecoration: pw.BoxDecoration(color: navy),
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellAlignments: {1: pw.Alignment.centerRight, 2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight},
        ),
        if (agg.byMonth.length > 1) ...[
          pw.SizedBox(height: 18),
          pw.Text('Month-over-month', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: ['Month', 'Income', 'Expense', 'Net'],
            data: [
              for (final e in (agg.byMonth.entries.toList()..sort((a, b) => a.key.compareTo(b.key))))
                [e.key, _money(e.value.inflow, c), _money(e.value.outflow, c), _money(e.value.net, c)],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9),
            headerDecoration: pw.BoxDecoration(color: navy),
            cellStyle: const pw.TextStyle(fontSize: 9),
          ),
        ],
        if (transactions.isNotEmpty) ...[
          pw.SizedBox(height: 18),
          pw.Text('Transactions', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: ['Date', 'Counterparty', 'Category', 'Mode', 'Amount'],
            data: [
              for (final t in transactions.take(500))
                [
                  Fmt.date(AppClock.toLocal(t.transactionDate)),
                  t.displayName,
                  t.categoryName,
                  t.paymentMode.label,
                  '${t.isInflow ? '+' : '-'}${_money(t.amount, t.currency)}',
                ],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 8),
            headerDecoration: pw.BoxDecoration(color: navy),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellAlignments: {4: pw.Alignment.centerRight},
          ),
        ],
      ],
    ));
    return _write('smart_spend_${_slug(period.label)}.pdf', await doc.save());
  }

  Future<File> buildExcel({
    required DateRangePeriod period,
    required PeriodAggregate agg,
    required List<FinancialTransaction> transactions,
  }) async {
    final x = Excel.createExcel();
    final summary = x['Summary'];
    x.setDefaultSheet('Summary');
    for (final s in x.sheets.keys.where((k) => k != 'Summary').toList()) {
      x.delete(s);
    }
    TextCellValue t(String s) => TextCellValue(s);
    DoubleCellValue d(double v) => DoubleCellValue(double.parse(v.toStringAsFixed(2)));

    summary.appendRow([t('Smart Spend Tracker report'), t(period.label)]);
    summary.appendRow([t('Currency'), t(agg.currency)]);
    summary.appendRow([t('Total inflow'), d(agg.inflow)]);
    summary.appendRow([t('Total outflow'), d(agg.outflow)]);
    summary.appendRow([t('Net cash flow'), d(agg.net)]);
    summary.appendRow([t('Transactions'), IntCellValue(agg.count)]);
    summary.appendRow([t('Refunds'), d(agg.refunds)]);
    summary.appendRow([]);
    summary.appendRow([t('Category'), t('Amount'), t('Share %'), t('Count')]);
    for (final s in agg.expenseCategories) {
      summary.appendRow([t(s.category.name), d(s.amount), d(s.percent), IntCellValue(s.count)]);
    }

    final months = x['Monthly'];
    months.appendRow([t('Month'), t('Income'), t('Expense'), t('Net'), t('Count')]);
    for (final e in (agg.byMonth.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))) {
      months.appendRow([t(e.key), d(e.value.inflow), d(e.value.outflow), d(e.value.net), IntCellValue(e.value.count)]);
    }

    final txSheet = x['Transactions'];
    txSheet.appendRow([
      t('Date'), t('Time'), t('Direction'), t('Amount'), t('Currency'), t('Category'), t('Subcategory'), t('Counterparty'),
      t('Narration'), t('Bank'), t('Account'), t('Payment mode'), t('Reference'), t('Source'), t('Contributed by'), t('Status'),
    ]);
    for (final tx in transactions) {
      final local = AppClock.toLocal(tx.transactionDate);
      txSheet.appendRow([
        t(Fmt.dayKey(local)), t(Fmt.time(local)), t(tx.isInflow ? 'Inflow' : 'Outflow'), d(tx.amount), t(tx.currency),
        t(tx.categoryName), t(tx.subcategory ?? ''), t(tx.counterparty ?? ''), t(tx.narration), t(tx.bankName ?? ''),
        t(tx.maskedAccountNumber ?? ''), t(tx.paymentMode.label), t(tx.referenceNumber ?? ''),
        t(tx.sources.map((s) => s.label).join(' + ')), t(tx.ownerName ?? ''), t(tx.status.label),
      ]);
    }
    final bytes = x.save()!;
    return _write('smart_spend_${_slug(period.label)}.xlsx', bytes);
  }

  Future<void> share(File f, {String? subject}) =>
      SharePlus.instance.share(ShareParams(files: [XFile(f.path)], subject: subject ?? 'Smart Spend report'));

  Future<File> _write(String name, List<int> bytes) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$name');
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  String _slug(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
}
