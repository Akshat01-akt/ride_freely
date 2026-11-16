import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ride_freely/core/core.dart';
import 'package:ride_freely/features/forms/dynamic_form.dart';

import '../fakes.dart';

FormSpec _spec(List<Map<String, dynamic>> fields) =>
    FormSpec.fromJson({'version': 3, 'fields': fields});

Map<String, dynamic> _f(String key, String type, {bool required = false, List<String>? choices, String? help}) =>
    {'key': key, 'label': 'Label $key', 'field_type': type, 'required': required, 'choices': choices, 'help_text': help};

Future<List<Map<String, String>>> _pump(
  WidgetTester t,
  FormSpec spec, {
  Map<String, String> initial = const {},
  Set<String> flagged = const {},
  Map<String, DocumentState> documents = const {},
  Map<String, String> notes = const {},
  Set<String> alsoEditable = const {},
  Map<String, String> serverErrors = const {},
}) async {
  reduceMotionFor(t);
  final sent = <Map<String, String>>[];
  await t.pumpWidget(MaterialApp(
    theme: AppTheme.dark(),
    home: Scaffold(
      body: SingleChildScrollView(
        child: DynamicForm(
          spec: spec,
          initial: initial,
          flagged: flagged,
          notes: notes,
          alsoEditable: alsoEditable,
          serverErrors: serverErrors,
          documents: documents,
          onPickDocument: (_) {},
          onSubmit: (a) async => sent.add(a),
        ),
      ),
    ),
  ));
  return sent;
}

void main() {
  testWidgets('renders each supported type', (t) async {
    await _pump(
      t,
      _spec([
        _f('a_text', 'text', required: true),
        _f('a_number', 'number'),
        _f('a_date', 'date'),
        _f('a_choice', 'choice', choices: ['Sedan', 'SUV']),
        _f('LICENCE', 'document', required: true, help: 'A clear photo'),
      ]),
    );
    expect(find.byKey(const Key('field_a_text')), findsOneWidget);
    expect(find.byKey(const Key('field_a_number')), findsOneWidget);
    expect(find.byKey(const Key('field_a_date')), findsOneWidget);
    expect(find.byKey(const Key('field_a_choice')), findsOneWidget);
    expect(find.byKey(const Key('doc_LICENCE')), findsOneWidget);
    expect(find.text('A clear photo'), findsOneWidget);
    expect(find.text('Not uploaded'), findsOneWidget);
  });

  testWidgets('a required field blocks submit and an optional one does not', (t) async {
    final sent = await _pump(t, _spec([_f('name', 'text', required: true), _f('note', 'text')]));
    await t.tap(find.text('Submit'));
    await t.pump();
    expect(find.text('This is required'), findsOneWidget);
    expect(sent, isEmpty);
    await t.enterText(find.byKey(const Key('field_name')), '  Ravi  ');
    await t.tap(find.text('Submit'));
    await t.pump();
    expect(sent, [
      {'name': 'Ravi'}
    ]);
  });

  testWidgets('numbers and dates are checked before sending', (t) async {
    final sent = await _pump(t, _spec([_f('years', 'number', required: true), _f('dob', 'date', required: true)]));
    await t.enterText(find.byKey(const Key('field_years')), 'abc');
    await t.enterText(find.byKey(const Key('field_dob')), '31/12/1990');
    await t.tap(find.text('Submit'));
    await t.pump();
    expect(find.text('Enter a number'), findsOneWidget);
    expect(find.text('Use the format YYYY-MM-DD'), findsOneWidget);
    await t.enterText(find.byKey(const Key('field_years')), '6');
    await t.enterText(find.byKey(const Key('field_dob')), '1990-02-30');
    await t.tap(find.text('Submit'));
    await t.pump();
    expect(find.text('Use the format YYYY-MM-DD'), findsOneWidget);
    expect(sent, isEmpty);
    await t.enterText(find.byKey(const Key('field_dob')), '1990-12-31');
    await t.tap(find.text('Submit'));
    await t.pump();
    expect(sent.single, {'years': '6', 'dob': '1990-12-31'});
  });

  testWidgets('a choice must be picked from the list', (t) async {
    final sent = await _pump(t, _spec([_f('vehicle', 'choice', required: true, choices: ['Sedan', 'SUV'])]));
    await t.tap(find.text('Submit'));
    await t.pump();
    expect(sent, isEmpty);
    await t.tap(find.byKey(const Key('field_vehicle')));
    await t.pumpAndSettle();
    await t.tap(find.text('SUV').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Submit'));
    await t.pump();
    expect(sent.single, {'vehicle': 'SUV'});
  });

  testWidgets('an unknown optional field type is skipped', (t) async {
    final sent = await _pump(t, _spec([_f('name', 'text', required: true), _f('sig', 'signature')]));
    expect(find.byKey(const Key('field_sig')), findsNothing);
    await t.enterText(find.byKey(const Key('field_name')), 'Ravi');
    await t.tap(find.text('Submit'));
    await t.pump();
    expect(sent.single, {'name': 'Ravi'});
  });

  testWidgets('an unknown required field type asks for an update and offers no submit', (t) async {
    await _pump(t, _spec([_f('name', 'text', required: true), _f('sig', 'signature', required: true)]));
    expect(find.textContaining('Update the app to continue'), findsOneWidget);
    expect(find.text('Submit'), findsNothing);
    expect(find.byKey(const Key('field_name')), findsNothing);
  });

  testWidgets('when fixing flagged items only those are editable', (t) async {
    final sent = await _pump(
      t,
      _spec([_f('licence_number', 'text', required: true), _f('hourly_rate', 'number', required: true)]),
      initial: {'licence_number': 'DL-1', 'hourly_rate': '180'},
      flagged: {'hourly_rate'},
      notes: {'hourly_rate': 'Too high'},
    );
    expect(find.byKey(const Key('field_licence_number')), findsNothing);
    expect(find.text('DL-1'), findsOneWidget);
    expect(find.text('Needs changes: Too high'), findsOneWidget);
    await t.enterText(find.byKey(const Key('field_hourly_rate')), '150');
    await t.tap(find.text('Submit'));
    await t.pump();
    expect(sent.single, {'hourly_rate': '150'});
  });

  testWidgets('documents show their review state and the reviewer note', (t) async {
    await _pump(
      t,
      _spec([_f('LICENCE', 'document', required: true)]),
      documents: {'LICENCE': const DocumentState(status: 'REJECTED', note: 'Blurry')},
      flagged: {'LICENCE'},
    );
    expect(find.text('Rejected'), findsOneWidget);
    expect(find.text('Blurry'), findsOneWidget);
    expect(find.text('Upload again'), findsOneWidget);
  });

  testWidgets('a question added while fixing flagged items is editable too', (t) async {
    final sent = await _pump(
      t,
      _spec([_f('hourly_rate', 'number', required: true), _f('badge_no', 'text', required: true), _f('licence_number', 'text', required: true)]),
      initial: {'hourly_rate': '999', 'licence_number': 'DL-1'},
      flagged: {'hourly_rate'},
      alsoEditable: {'badge_no'},
    );
    expect(find.byKey(const Key('field_licence_number')), findsNothing);
    expect(find.text('Needs changes'), findsOneWidget); // only the flagged rate, not the new question
    await t.enterText(find.byKey(const Key('field_hourly_rate')), '150');
    await t.enterText(find.byKey(const Key('field_badge_no')), 'B-1');
    await t.tap(find.text('Submit'));
    await t.pump();
    expect(sent.single, {'hourly_rate': '150', 'badge_no': 'B-1'});
  });

  testWidgets('server errors name the field they belong to', (t) async {
    await _pump(
      t,
      _spec([_f('badge_no', 'text', required: true)]),
      serverErrors: {'badge_no': 'This is required', 'unknown_key': 'This is not a field on the form'},
    );
    expect(find.text('Label badge_no: This is required'), findsOneWidget);
    expect(find.text('unknown_key: This is not a field on the form'), findsOneWidget);
  });
}
