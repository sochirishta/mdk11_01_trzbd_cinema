import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/api_exceptions.dart';
import '../core/validators.dart';
import '../models/booking.dart';
import '../models/ticket.dart';
import '../models/booking_query.dart';
import '../repositories/booking_repository.dart';
import '../repositories/ticket_repository.dart';
import '../widgets/entity_form.dart';
import '../widgets/form_field_definition.dart';

class TicketFormScreen extends StatefulWidget {
  final String? id;

  const TicketFormScreen({
    super.key,
    this.id,
  });

  @override
  State<TicketFormScreen> createState() =>
      _TicketFormScreenState();
}

class _TicketFormScreenState extends State<TicketFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _numberController = TextEditingController();

  DateTime _issuedAt = DateTime.now();

  List<Booking> _bookings = [];
  String? _bookingId;

  bool _isLoading = false;
  bool _isSaving = false;
  bool _hasUnsavedChanges = false;

  bool get _isEditing => widget.id != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _numberController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final bookingRepository =
      context.read<BookingRepository>();

      final bookingResult = await bookingRepository.find(
        const BookingQuery(
          page: 1,
          size: 100,
          includeDeleted: false,
        ),
      );

      if (!mounted) return;

      _bookings = bookingResult.items;

      if (_isEditing) {
        final ticketRepository =
        context.read<TicketRepository>();

        final ticket = await ticketRepository.findById(
          widget.id!,
        );

        if (!mounted) return;

        if (ticket == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Билет не найден'),
            ),
          );

          context.go('/tickets');
          return;
        }

        _bookingId = ticket.bookingId;
        _numberController.text = ticket.number;
        _issuedAt = ticket.issuedAt;

        // Если текущее бронирование уже удалено
        // или отсутствует в первой загрузке, попробуем
        // получить его отдельно.
        if (!_bookings.any(
              (booking) => booking.id == ticket.bookingId,
        )) {
          final oldBooking =
          await bookingRepository.findById(
            ticket.bookingId,
          );

          if (!mounted) return;

          if (oldBooking != null) {
            _bookings = [
              ..._bookings,
              oldBooking,
            ];
          }
        }
      }
    } on ApiException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
        ),
      );

      context.go('/tickets');
      return;
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
        ),
      );

      context.go('/tickets');
      return;
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _markChanged() {
    if (!_hasUnsavedChanges) {
      setState(() {
        _hasUnsavedChanges = true;
      });
    }
  }

  Future<void> _selectIssuedAt() async {
    final initial = _issuedAt;

    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );

    if (time == null || !mounted) return;

    setState(() {
      _issuedAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      _hasUnsavedChanges = true;
    });
  }

  String _bookingLabel(Booking booking) {
    return '${booking.id} — '
        'ряд ${booking.row}, место ${booking.seat}';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final bookingId = _bookingId;

    if (bookingId == null || bookingId.isEmpty) {
      return;
    }

    final ticket = Ticket(
      id: widget.id ?? '',
      bookingId: bookingId,
      number: _numberController.text.trim(),
      issuedAt: _issuedAt,
    );

    setState(() {
      _isSaving = true;
    });

    try {
      final repository =
      context.read<TicketRepository>();

      if (_isEditing) {
        await repository.update(ticket);
      } else {
        await repository.create(ticket);
      }

      if (!mounted) return;

      context.go(
        _isEditing
            ? '/tickets/${widget.id}'
            : '/tickets',
      );
    } on ConflictException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _cancel() {
    if (_isEditing) {
      context.go('/tickets/${widget.id}');
    } else {
      context.go('/tickets');
    }
  }

  @override
  Widget build(BuildContext context) {
    return EntityForm(
      formKey: _formKey,
      title: _isEditing
          ? 'Редактирование билета'
          : 'Новый билет',
      isEditing: _isEditing,
      isLoading: _isLoading,
      isSaving: _isSaving,
      hasUnsavedChanges: _hasUnsavedChanges,
      onSubmit: _submit,
      onCancel: _cancel,
      fields: [
        FormFieldDefinition(
          label: 'Номер билета',
          type: FormFieldType.text,
          controller: _numberController,
          validator: (value) =>
              Validators.maxLength(value, 100),
          onChanged: (_) => _markChanged(),
        ),
      ],
      customFields: [
        DropdownButtonFormField<String>(
          initialValue: _bookingId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Бронирование',
            border: OutlineInputBorder(),
          ),
          items: _bookings.map((booking) {
            return DropdownMenuItem<String>(
              value: booking.id,
              child: Text(
                _bookingLabel(booking),
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          onChanged: _isSaving
              ? null
              : (value) {
            setState(() {
              _bookingId = value;
              _hasUnsavedChanges = true;
            });
          },
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Выберите бронирование';
            }

            return null;
          },
        ),
        const SizedBox(height: 16),
        InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Дата и время выдачи',
            border: OutlineInputBorder(),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _formatDateTime(_issuedAt),
                ),
              ),
              OutlinedButton(
                onPressed: _isSaving
                    ? null
                    : _selectIssuedAt,
                child: const Text('Изменить'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  static String _formatDateTime(DateTime value) {
    final local = value.toLocal();

    String two(int value) =>
        value.toString().padLeft(2, '0');

    return '${local.year}-'
        '${two(local.month)}-'
        '${two(local.day)} '
        '${two(local.hour)}:'
        '${two(local.minute)}';
  }
}