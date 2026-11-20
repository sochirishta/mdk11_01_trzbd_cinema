import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/api_exceptions.dart';
import '../models/app_user.dart';
import '../models/booking.dart';
import '../models/session.dart';
import '../models/session_query.dart';
import '../repositories/booking_repository.dart';
import '../repositories/session_repository.dart';
import '../state/auth_notifier.dart';

class BookingFormScreen extends StatefulWidget {
  final String? id;

  const BookingFormScreen({
    super.key,
    this.id,
  });

  bool get isEditing => id != null;

  @override
  State<BookingFormScreen> createState() =>
      _BookingFormScreenState();
}

class _BookingFormScreenState extends State<BookingFormScreen> {
  final _formKey = GlobalKey<FormState>();

  String? _sessionId;
  String? _userId;

  final _rowController = TextEditingController();
  final _seatController = TextEditingController();

  List<CinemaSession> _sessions = [];
  List<AppUser> _users = [];

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _rowController.dispose();
    _seatController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final sessionRepository =
      context.read<SessionRepository>();
      final dio = context.read<Dio>();
      final auth = context.read<AuthNotifier>();

      final currentUser = auth.user;
      final isViewer = currentUser?.role == Role.viewer;

      final sessionResult = await sessionRepository.find(
        const SessionQuery(
          page: 1,
          size: 100,
          includeDeleted: false,
        ),
      );

      List<AppUser> users = [];

      if (!isViewer) {
        final usersResponse = await dio.get(
          '/collections/users/records',
          queryParameters: {
            'page': 1,
            'perPage': 100,
            'sort': '+created',
          },
        );

        final usersData =
        usersResponse.data as Map<String, dynamic>;

        users = (usersData['items'] as List<dynamic>)
            .map(
              (item) => AppUser.fromJson(
            item as Map<String, dynamic>,
          ),
        )
            .toList();
      }

      if (!mounted) return;

      _sessions = sessionResult.items;
      _users = users;

      if (isViewer && !widget.isEditing) {
        _userId = currentUser?.id;
      }

      if (widget.isEditing) {
        final bookingId = widget.id!;

        final bookingRepository =
        context.read<BookingRepository>();

        final booking =
        await bookingRepository.findById(bookingId);

        if (!mounted) return;

        if (booking == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Бронирование не найдено',
              ),
            ),
          );

          context.go('/bookings');
          return;
        }

        if (isViewer &&
            currentUser != null &&
            booking.userId != currentUser.id) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Вы не можете редактировать чужое бронирование',
              ),
            ),
          );

          context.go('/bookings');
          return;
        }

        _sessionId = booking.sessionId;
        _userId = booking.userId;

        _rowController.text =
            booking.row.toString();
        _seatController.text =
            booking.seat.toString();

        // Если бронирование связано с удалённым сеансом,
        // добавляем его в список, чтобы его можно было
        // отредактировать.
        if (!_sessions.any(
              (session) => session.id == booking.sessionId,
        )) {
          final oldSession =
          await sessionRepository.findById(
            booking.sessionId,
          );

          if (!mounted) return;

          if (oldSession != null) {
            _sessions = [
              ..._sessions,
              oldSession,
            ];
          }
        }

        if (!isViewer &&
            !_users.any(
                  (user) => user.id == booking.userId,
            )) {
          try {
            final response = await dio.get(
              '/collections/users/records/${booking.userId}',
            );

            final user = AppUser.fromJson(
              response.data
              as Map<String, dynamic>,
            );

            _users = [
              ..._users,
              user,
            ];
          } on DioException {
            //
          }
        }
      }

      if (!mounted) return;

      setState(() {
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;

      final exception = mapDioError(e);

      setState(() {
        _loading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(exception.message),
        ),
      );

      context.go('/bookings');
    } on ApiException catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
        ),
      );

      context.go('/bookings');
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
        ),
      );

      context.go('/bookings');
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final sessionId = _sessionId;
    final userId = _userId;

    final row = int.tryParse(
      _rowController.text.trim(),
    );

    final seat = int.tryParse(
      _seatController.text.trim(),
    );

    if (sessionId == null || userId == null) {
      return;
    }

    if (row == null || seat == null) {
      return;
    }

    setState(() {
      _saving = true;
    });

    final repository =
    context.read<BookingRepository>();

    try {
      if (widget.isEditing) {
        final bookingId = widget.id!;

        final old =
        await repository.findById(bookingId);

        if (old == null) {
          throw StateError(
            'Бронирование не найдено',
          );
        }

        await repository.update(
          old.copyWith(
            sessionId: sessionId,
            userId: userId,
            row: row,
            seat: seat,
          ),
        );
      } else {
        await repository.create(
          Booking(
            id: '',
            sessionId: sessionId,
            userId: userId,
            row: row,
            seat: seat,
          ),
        );
      }

      if (!mounted) return;

      context.go('/bookings');
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
          _saving = false;
        });
      }
    }
  }

  String _sessionLabel(CinemaSession session) {
    final localDate = session.date.toLocal();

    final day =
    localDate.day.toString().padLeft(2, '0');
    final month =
    localDate.month.toString().padLeft(2, '0');
    final year =
    localDate.year.toString();

    final hour =
    localDate.hour.toString().padLeft(2, '0');
    final minute =
    localDate.minute.toString().padLeft(2, '0');

    return '$day.$month.$year '
        '$hour:$minute — ${session.id}';
  }

  String _userLabel(AppUser user) {
    if (user.fullName.isNotEmpty) {
      return '${user.fullName} (@${user.username})';
    }

    return '@${user.username}';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthNotifier>();

    final isViewer =
        auth.user != null &&
            !auth.hasRole(Role.manager);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            widget.isEditing
                ? 'Редактирование бронирования'
                : 'Новое бронирование',
          ),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isEditing
              ? 'Редактирование бронирования'
              : 'Новое бронирование',
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<String>(
              initialValue: _sessionId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Сеанс',
                border: OutlineInputBorder(),
              ),
              items: _sessions.map((session) {
                return DropdownMenuItem<String>(
                  value: session.id,
                  child: Text(
                    _sessionLabel(session),
                    overflow:
                    TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: _saving
                  ? null
                  : (value) {
                setState(() {
                  _sessionId = value;
                });
              },
              validator: (value) {
                if (value == null ||
                    value.isEmpty) {
                  return 'Выберите сеанс';
                }

                return null;
              },
            ),

            if (!isViewer) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _userId,
                isExpanded: true,
                decoration:
                const InputDecoration(
                  labelText: 'Пользователь',
                  border: OutlineInputBorder(),
                ),
                items: _users.map((user) {
                  return DropdownMenuItem<String>(
                    value: user.id,
                    child: Text(
                      _userLabel(user),
                      overflow:
                      TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: _saving
                    ? null
                    : (value) {
                  setState(() {
                    _userId = value;
                  });
                },
                validator: (value) {
                  if (value == null ||
                      value.isEmpty) {
                    return 'Выберите пользователя';
                  }

                  return null;
                },
              ),
            ],

            const SizedBox(height: 12),

            TextFormField(
              controller: _rowController,
              enabled: !_saving,
              keyboardType:
              TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Ряд',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                final parsed = int.tryParse(
                  value?.trim() ?? '',
                );

                if (parsed == null) {
                  return 'Введите целое число';
                }

                if (parsed <= 0) {
                  return 'Ряд должен быть больше 0';
                }

                return null;
              },
            ),

            const SizedBox(height: 12),

            TextFormField(
              controller: _seatController,
              enabled: !_saving,
              keyboardType:
              TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Место',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                final parsed = int.tryParse(
                  value?.trim() ?? '',
                );

                if (parsed == null) {
                  return 'Введите целое число';
                }

                if (parsed <= 0) {
                  return 'Место должно быть больше 0';
                }

                return null;
              },
            ),

            const SizedBox(height: 24),

            Row(
              mainAxisAlignment:
              MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: _saving
                      ? null
                      : () => context.go(
                    '/bookings',
                  ),
                  child: const Text('Отмена'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed:
                  _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child:
                    CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                      : Text(
                    widget.isEditing
                        ? 'Сохранить'
                        : 'Создать',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}