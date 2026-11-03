enum LoanInstallmentState { due, overdue, partial, paid }

LoanInstallmentState loanInstallmentState({
  required num amount,
  required num paidAmount,
  required DateTime dueDate,
  DateTime? today,
}) {
  if (paidAmount >= amount - 0.005) return LoanInstallmentState.paid;
  if (paidAmount > 0) return LoanInstallmentState.partial;

  final reference = today ?? DateTime.now();
  final referenceDate = DateTime(reference.year, reference.month, reference.day);
  final scheduledDate = DateTime(dueDate.year, dueDate.month, dueDate.day);
  if (scheduledDate.isBefore(referenceDate)) return LoanInstallmentState.overdue;
  return LoanInstallmentState.due;
}

String loanInstallmentStateLabel(LoanInstallmentState state) => switch (state) {
  LoanInstallmentState.due => 'বকেয়া',
  LoanInstallmentState.overdue => 'মেয়াদোত্তীর্ণ',
  LoanInstallmentState.partial => 'আংশিক',
  LoanInstallmentState.paid => 'পরিশোধিত',
};
