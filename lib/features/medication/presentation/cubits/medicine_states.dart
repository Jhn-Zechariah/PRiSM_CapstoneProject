import '../../domain/model/app_medicine.dart';
import '../../domain/model/app_medicine_intake.dart';

/// One state object holding every list the medication screens need.
///
/// Previously medicines, intakes and save results were separate state
/// classes, so each emission replaced the others — e.g. a stock change
/// emitted MedicineLoaded and blanked the intake history page. Saves now
/// report back through the Future the dialog awaits instead of the state.
class MedicineState {
  final List<Medicine> medicines;
  final bool medicinesLoading;
  final String? medicinesError;

  final List<MedicineIntake> intakes;
  final bool intakesLoading;
  final String? intakesError;

  /// Earliest batch expiry per medicine id, for the stock list.
  final Map<String, String> nextExpiries;

  const MedicineState({
    this.medicines = const [],
    this.medicinesLoading = false,
    this.medicinesError,
    this.intakes = const [],
    this.intakesLoading = false,
    this.intakesError,
    this.nextExpiries = const {},
  });

  MedicineState copyWith({
    List<Medicine>? medicines,
    bool? medicinesLoading,
    String? medicinesError,
    bool clearMedicinesError = false,
    List<MedicineIntake>? intakes,
    bool? intakesLoading,
    String? intakesError,
    bool clearIntakesError = false,
    Map<String, String>? nextExpiries,
  }) {
    return MedicineState(
      medicines: medicines ?? this.medicines,
      medicinesLoading: medicinesLoading ?? this.medicinesLoading,
      medicinesError:
          clearMedicinesError ? null : (medicinesError ?? this.medicinesError),
      intakes: intakes ?? this.intakes,
      intakesLoading: intakesLoading ?? this.intakesLoading,
      intakesError:
          clearIntakesError ? null : (intakesError ?? this.intakesError),
      nextExpiries: nextExpiries ?? this.nextExpiries,
    );
  }
}
