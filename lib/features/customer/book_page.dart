import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/core.dart';
import '../../routes.dart';
import '../auth/auth_scaffold.dart';
import '../bookings/bookings.dart';
import 'data/models.dart';

class BookPage extends StatefulWidget {
  const BookPage({super.key});

  @override
  State<BookPage> createState() => _BookPageState();
}

class _BookPageState extends State<BookPage> {
  static const _fullDayHours = 8;

  final _form = GlobalKey<FormState>();
  final _address = TextEditingController();
  final _notes = TextEditingController();
  final _bookings = bookingsFor(UserRole.customer);
  late final DriverSummary _driver = Get.arguments as DriverSummary;

  BookingType _type = BookingType.hourly;
  int _hours = 2;
  DateTime? _start; // null means "now"
  String? _whenError;

  @override
  void initState() {
    super.initState();
    _bookings.actionError.value = null;
  }

  @override
  void dispose() {
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  int get _billedHours => _type == BookingType.fullDay ? _fullDayHours : _hours;

  String get _estimate {
    final total = _driver.hourlyRate * _billedHours;
    return '₹${total == total.roundToDouble() ? total.round() : total.toStringAsFixed(2)}';
  }

  Future<void> _pickTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (time == null || !mounted) return;
    final picked = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      if (picked.isBefore(DateTime.now())) {
        _whenError = 'Pick a time in the future';
      } else {
        _start = picked;
        _whenError = null;
      }
    });
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final booking = await _bookings.create(
      driverId: _driver.id,
      type: _type,
      start: _start,
      hours: _type == BookingType.hourly ? _hours : null,
      address: _address.text,
      notes: _notes.text,
    );
    if (booking != null) {
      Get.offNamed(Routes.bookingConfirmed, arguments: booking);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('Book ${_driver.name}'),
        leading: IconButton(
          tooltip: 'Back',
          onPressed: Get.back,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: AnimatedGradientBackground(
        dark: false,
        child: SafeArea(
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                FadeSlideIn(
                  child: Row(
                    children: [
                      _Choice(
                        label: 'Hourly',
                        selected: _type == BookingType.hourly,
                        onTap: () => setState(() => _type = BookingType.hourly),
                      ),
                      const SizedBox(width: 10),
                      _Choice(
                        label: 'Full day',
                        selected: _type == BookingType.fullDay,
                        onTap: () =>
                            setState(() => _type = BookingType.fullDay),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 60),
                  child: _Card(
                    child: _type == BookingType.hourly
                        ? Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'How long?',
                                  style: text.titleMedium,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Fewer hours',
                                onPressed: _hours > 1
                                    ? () => setState(() => _hours--)
                                    : null,
                                icon: const Icon(
                                  Icons.remove_circle_outline_rounded,
                                ),
                              ),
                              SizedBox(
                                width: 70,
                                child: Text(
                                  _hours == 1 ? '1 hour' : '$_hours hours',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'More hours',
                                onPressed: _hours < 12
                                    ? () => setState(() => _hours++)
                                    : null,
                                icon: const Icon(
                                  Icons.add_circle_outline_rounded,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            'A full day is $_fullDayHours hours of driving.',
                            style: text.bodyLarge,
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 100),
                  child: _Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('When?', style: text.titleMedium),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            _Choice(
                              label: 'Now',
                              selected: _start == null,
                              onTap: () => setState(() {
                                _start = null;
                                _whenError = null;
                              }),
                            ),
                            _Choice(
                              label: _start == null
                                  ? 'Pick a time'
                                  : formatWindow(
                                      _start!,
                                      _start!.add(
                                        Duration(hours: _billedHours),
                                      ),
                                    ),
                              selected: _start != null,
                              onTap: _pickTime,
                            ),
                          ],
                        ),
                        if (_whenError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              _whenError!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 140),
                  child: AppTextField(
                    key: const Key('address'),
                    controller: _address,
                    label: 'Pickup address',
                    icon: Icons.place_rounded,
                    validator: (v) => (v ?? '').trim().isEmpty
                        ? 'Enter the pickup address'
                        : null,
                  ),
                ),
                const SizedBox(height: 14),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 180),
                  child: AppTextField(
                    key: const Key('notes'),
                    controller: _notes,
                    label: 'Notes for the driver (optional)',
                    icon: Icons.notes_rounded,
                    textInputAction: TextInputAction.done,
                  ),
                ),
                const SizedBox(height: 18),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 220),
                  child: _Card(
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Estimated total',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          _estimate,
                          style: text.headlineSmall?.copyWith(
                            color: AppColors.fuchsia,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'The driver confirms the request. Nothing is charged yet.',
                  style: TextStyle(fontSize: 12.5),
                ),
                Obx(() => FormError(_bookings.actionError.value)),
                const SizedBox(height: 16),
                Obx(
                  () => AppButton(
                    label: 'Send request',
                    icon: Icons.send_rounded,
                    loading: _bookings.actingId.value != null,
                    onPressed: _submit,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.md),
      boxShadow: softShadow(alpha: 0.05, blur: 14, y: 5),
    ),
    child: child,
  );
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    child: AnimatedContainer(
      duration: AppMotion.hover,
      curve: AppMotion.curve,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
      decoration: BoxDecoration(
        color: selected ? AppColors.fuchsia : Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: selected
            ? softShadow(color: AppColors.fuchsia, alpha: 0.3, blur: 14, y: 6)
            : softShadow(alpha: 0.05, blur: 10, y: 4),
      ),
      child: AnimatedDefaultTextStyle(
        duration: AppMotion.hover,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: selected ? AppColors.cream : AppColors.charcoal,
        ),
        child: Text(label),
      ),
    ),
  );
}
