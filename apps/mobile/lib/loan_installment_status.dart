enum LoanInstallmentState { upcoming, due, overdue, partial, paid }

LoanInstallmentState loanInstallmentState({
  required num amount,
  required num paidAmount,
  required DateTime dueDate,
  DateTime? today,
}) {
  if (paidAmount >= amount - 0.005) return LoanInstallmentState.paid;

  final reference = today ?? DateTime.now();
  final referenceDate = DateTime(reference.year, reference.month, reference.day);
  final scheduledDate = DateTime(dueDate.year, dueDate.month, dueDate.day);
  if (scheduledDate.isBefore(referenceDate)) return LoanInstallmentState.overdue;
  if (paidAmount > 0) return LoanInstallmentState.partial;
  if (scheduledDate.isAtSameMomentAs(referenceDate)) return LoanInstallmentState.due;
  return LoanInstallmentState.upcoming;
}

String loanInstallmentStateLabel(LoanInstallmentState state) => switch (state) {
  LoanInstallmentState.upcoming => 'আসন্ন',
  LoanInstallmentState.due => 'আজ প্রাপ্য',
  LoanInstallmentState.overdue => 'মেয়াদোত্তীর্ণ',
  LoanInstallmentState.partial => 'আংশিক',
  LoanInstallmentState.paid => 'পরিশোধিত',
};
