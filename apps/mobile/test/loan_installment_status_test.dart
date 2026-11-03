import 'package:flutter_test/flutter_test.dart';
import 'package:somityhub_app/loan_installment_status.dart';

void main() {
  final today = DateTime(2026, 11, 3);

  test('marks an unpaid installment before today as overdue', () {
    expect(
      loanInstallmentState(
        amount: 100,
        paidAmount: 0,
        dueDate: DateTime(2026, 11, 2),
        today: today,
      ),
      LoanInstallmentState.overdue,
    );
  });

  test('keeps an installment due today as due, not overdue', () {
    expect(
      loanInstallmentState(
        amount: 100,
        paidAmount: 0,
        dueDate: today,
        today: today,
      ),
      LoanInstallmentState.due,
    );
  });

  test('marks a future unpaid installment as upcoming', () {
    expect(
      loanInstallmentState(
        amount: 100,
        paidAmount: 0,
        dueDate: DateTime(2026, 11, 4),
        today: today,
      ),
      LoanInstallmentState.upcoming,
    );
  });

  test('marks a partially paid installment with a future due date as partial', () {
    expect(
      loanInstallmentState(
        amount: 100,
        paidAmount: 25,
        dueDate: DateTime(2026, 11, 10),
        today: today,
      ),
      LoanInstallmentState.partial,
    );
  });

  test('marks a partially paid installment past its due date as overdue', () {
    expect(
      loanInstallmentState(
        amount: 100,
        paidAmount: 25,
        dueDate: DateTime(2026, 11, 1),
        today: today,
      ),
      LoanInstallmentState.overdue,
    );
  });

  test('marks a fully paid installment as paid even after its due date', () {
    expect(
      loanInstallmentState(
        amount: 100,
        paidAmount: 100,
        dueDate: DateTime(2026, 10, 1),
        today: today,
      ),
      LoanInstallmentState.paid,
    );
  });

  test('accepts a one-cent rounding difference as paid', () {
    expect(
      loanInstallmentState(
        amount: 100,
        paidAmount: 99.995,
        dueDate: DateTime(2026, 11, 10),
        today: today,
      ),
      LoanInstallmentState.paid,
    );
  });

  test('exposes Bengali status labels', () {
    expect(loanInstallmentStateLabel(LoanInstallmentState.overdue), 'মেয়াদোত্তীর্ণ');
    expect(loanInstallmentStateLabel(LoanInstallmentState.upcoming), 'আসন্ন');
  });
}
